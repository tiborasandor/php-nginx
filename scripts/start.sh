#!/bin/bash
set -e

echo "Starting container..."

DEFAULT_SITE=/etc/nginx/sites-available/default.conf
SSL_SITE=/etc/nginx/sites-available/default-ssl.conf

# --------------------------------------------------
# Helper: PHP ini kulcs beállítása vagy létrehozása
# --------------------------------------------------
set_php_var() {
  KEY="$1"
  VALUE="$2"

  grep -qE "^[[:space:]]*${KEY}[[:space:]]*=" "$PHP_VARS" \
    && sed -i -E "s#^[[:space:]]*${KEY}[[:space:]]*=.*#${KEY}=${VALUE}#" "$PHP_VARS" \
    || echo "${KEY}=${VALUE}" >> "$PHP_VARS"
}

# --------------------------------------------------
# Git deploy (ha nincs még repo a webrootban)
# --------------------------------------------------
if [ ! -d /var/www/html/.git ] && [ -n "${GIT_REPO:-}" ]; then
  if [ "${REMOVE_FILES:-1}" = "0" ]; then
    echo "Skipping removal of files"
  else
    rm -rf /var/www/html/*
  fi

  GIT_COMMAND='git clone'

  if [ -n "${GIT_BRANCH:-}" ]; then
    GIT_COMMAND="${GIT_COMMAND} -b ${GIT_BRANCH}"
  fi

  if [ -z "${GIT_USERNAME:-}" ] && [ -z "${GIT_PERSONAL_TOKEN:-}" ]; then
    GIT_COMMAND="${GIT_COMMAND} ${GIT_REPO}"
  else
    if [ "${GIT_USE_SSH:-0}" = "1" ]; then
      GIT_COMMAND="${GIT_COMMAND} ${GIT_REPO}"
    else
      GIT_COMMAND="${GIT_COMMAND} https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO}"
    fi
  fi

  ${GIT_COMMAND} /var/www/html || exit 1

  cd /var/www/html || exit 1

  [ -n "${GIT_TAG:-}" ] && git checkout "${GIT_TAG}" || true
  [ -n "${GIT_COMMIT:-}" ] && git checkout "${GIT_COMMIT}" || true
fi

# --------------------------------------------------
# Egyedi nginx config az alkalmazásból
# --------------------------------------------------
if [ -f /var/www/html/conf/nginx/nginx.conf ]; then
  echo "Using custom nginx.conf from application"
  cp /var/www/html/conf/nginx/nginx.conf /etc/nginx/nginx.conf
fi

if [ -f /var/www/html/conf/nginx/nginx-site.conf ]; then
  echo "Using custom nginx site config from application"
  cp /var/www/html/conf/nginx/nginx-site.conf /etc/nginx/sites-available/default.conf
fi

if [ -f /var/www/html/conf/nginx/nginx-site-ssl.conf ]; then
  echo "Using custom nginx SSL site config from application"
  cp /var/www/html/conf/nginx/nginx-site-ssl.conf /etc/nginx/sites-available/default-ssl.conf
fi

# --------------------------------------------------
# WEBROOT átállítása nginx-ben
# --------------------------------------------------
if [ -n "${WEBROOT:-}" ]; then
  sed -i -E "s#^[[:space:]]*root[[:space:]]+[^;]+;#    root ${WEBROOT};#" "$DEFAULT_SITE"

  if [ -f "$SSL_SITE" ]; then
    sed -i -E "s#^[[:space:]]*root[[:space:]]+[^;]+;#    root ${WEBROOT};#" "$SSL_SITE"
  fi
fi

# --------------------------------------------------
# Front controller bekapcsolása (Slim/Laravel/Symfony)
# --------------------------------------------------
if [ -n "${PHP_FRONT_CONTROLLER:-}" ]; then
  sed -i -E 's#^[[:space:]]*try_files[[:space:]]+\$uri[[:space:]]+\$uri/[[:space:]]+=404;#        try_files $uri $uri/ /index.php?$query_string;#' "$DEFAULT_SITE"

  if [ -f "$SSL_SITE" ]; then
    sed -i -E 's#^[[:space:]]*try_files[[:space:]]+\$uri[[:space:]]+\$uri/[[:space:]]+=404;#        try_files $uri $uri/ /index.php?$query_string;#' "$SSL_SITE"
  fi
fi

# --------------------------------------------------
# Real IP támogatás reverse proxy mögött
# --------------------------------------------------
if [ "${ENABLE_REAL_IP:-0}" = "1" ]; then
  for SITE in "$DEFAULT_SITE" "$SSL_SITE"; do
    [ -f "$SITE" ] || continue

    sed -i 's/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/' "$SITE"
    sed -i 's/#set_real_ip_from/set_real_ip_from/' "$SITE"

    if [ -n "${REAL_IP_FROM:-}" ]; then
      sed -i "s#172.16.0.0/12#${REAL_IP_FROM}#" "$SITE"
    fi
  done
fi

# --------------------------------------------------
# Opcache kikapcsolás
# --------------------------------------------------
if [ -n "${OPCACHE_DISABLE:-}" ]; then
  set_php_var opcache.enable 0
fi

# --------------------------------------------------
# PHP display_errors
# --------------------------------------------------
DISPLAY_ERRORS=off
[ "${PHP_DISPLAY_ERRORS:-0}" = "1" ] && DISPLAY_ERRORS=on

sed -i -E "s#^[;[:space:]]*php_flag\\[display_errors\\][[:space:]]*=.*#php_flag[display_errors] = ${DISPLAY_ERRORS}#" "$FPM_CONF" 2>/dev/null || true
grep -qE '^[;[:space:]]*php_flag\[display_errors\][[:space:]]*=' "$FPM_CONF" || echo "php_flag[display_errors] = ${DISPLAY_ERRORS}" >> "$FPM_CONF"

# --------------------------------------------------
# Header elrejtés
# --------------------------------------------------
if [ "${HIDE_HEADERS:-1}" = "1" ]; then
  sed -i -E 's#^[[:space:]]*server_tokens[[:space:]]+[^;]+;#    server_tokens off;#' /etc/nginx/nginx.conf
  set_php_var expose_php 0
else
  sed -i -E 's#^[[:space:]]*server_tokens[[:space:]]+[^;]+;#    server_tokens on;#' /etc/nginx/nginx.conf
  set_php_var expose_php 1
fi

# --------------------------------------------------
# PHP log stderr-re
# --------------------------------------------------
if [ -n "${PHP_LOG_ERRORS_TO_STDERR:-}" ]; then
  set_php_var log_errors 1
  set_php_var error_log /dev/stderr
fi

# --------------------------------------------------
# PHP limitek
# --------------------------------------------------
[ -n "${PHP_MEM_LIMIT:-}" ] && set_php_var memory_limit "$PHP_MEM_LIMIT"
[ -n "${PHP_POST_MAX_SIZE:-}" ] && set_php_var post_max_size "$PHP_POST_MAX_SIZE"
[ -n "${PHP_UPLOAD_MAX_FILESIZE:-}" ] && set_php_var upload_max_filesize "$PHP_UPLOAD_MAX_FILESIZE"

# --------------------------------------------------
# Composer install opcionálisan
# --------------------------------------------------
if [ -n "${RUN_COMPOSER:-}" ] && [ -f /var/www/html/composer.lock ]; then
  echo "Running composer install..."

  if [ "${APPLICATION_ENV:-production}" = "development" ]; then
    composer install --working-dir=/var/www/html
  else
    composer install --no-dev --working-dir=/var/www/html
  fi
fi

# --------------------------------------------------
# UID / GID igazítás host fájljogokhoz
# --------------------------------------------------
if [ -n "${PUID:-}" ]; then
  PGID="${PGID:-$PUID}"
  deluser nginx 2>/dev/null || true
  addgroup -g "$PGID" nginx 2>/dev/null || true
  adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u "$PUID" nginx
fi

# --------------------------------------------------
# Jogosultságok beállítása
# --------------------------------------------------
if [ -z "${SKIP_CHOWN:-}" ]; then
  chown -R nginx:nginx /var/www/html 2>/dev/null || true
fi

# --------------------------------------------------
# PHP timezone
# --------------------------------------------------
echo "date.timezone=${TZ:-Europe/Budapest}" > /usr/local/etc/php/conf.d/timezone.ini

# --------------------------------------------------
# Runtime könyvtárak
# --------------------------------------------------
mkdir -p /run/nginx /var/run

# --------------------------------------------------
# Indítás
# --------------------------------------------------
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf