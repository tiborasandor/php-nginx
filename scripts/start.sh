#!/bin/bash
set -e

echo "Starting container..."

DEFAULT_SITE=/etc/nginx/sites-available/default.conf
SSL_SITE=/etc/nginx/sites-available/default-ssl.conf

if [ -n "${WEBROOT:-}" ]; then
  sed -i "s#root /var/www/html;#root ${WEBROOT};#g" "$DEFAULT_SITE" || true
  if [ -f "$SSL_SITE" ]; then
    sed -i "s#root /var/www/html;#root ${WEBROOT};#g" "$SSL_SITE" || true
  fi
fi

if [ -n "${PHP_CATCHALL:-}" ]; then
  sed -i 's#try_files $uri $uri/ =404;#try_files $uri $uri/ /index.php?$query_string;#g' "$DEFAULT_SITE" || true
  if [ -f "$SSL_SITE" ]; then
    sed -i 's#try_files $uri $uri/ =404;#try_files $uri $uri/ /index.php?$query_string;#g' "$SSL_SITE" || true
  fi
fi

if [ -n "${OPCACHE_DISABLE:-}" ]; then
  sed -i 's/^opcache\.enable=.*/opcache.enable=0/' "$PHP_VARS" 2>/dev/null || true
fi

if [ "${ERRORS:-0}" != "1" ]; then
  sed -i -E 's/^php_flag\[display_errors\]\s*=.*/php_flag[display_errors] = off/' "$FPM_CONF" 2>/dev/null || true
  grep -q '^php_flag\[display_errors\]' "$FPM_CONF" || echo 'php_flag[display_errors] = off' >> "$FPM_CONF"
else
  sed -i -E 's/^php_flag\[display_errors\]\s*=.*/php_flag[display_errors] = on/' "$FPM_CONF" 2>/dev/null || true
  grep -q '^php_flag\[display_errors\]' "$FPM_CONF" || echo 'php_flag[display_errors] = on' >> "$FPM_CONF"
fi

if [ "${HIDE_HEADERS:-1}" = "1" ]; then
  sed -i 's/server_tokens on;/server_tokens off;/' /etc/nginx/nginx.conf 2>/dev/null || true
  grep -q '^expose_php=' "$PHP_VARS" \
    && sed -i -E 's/^expose_php=.*/expose_php=0/' "$PHP_VARS" \
    || echo 'expose_php=0' >> "$PHP_VARS"
else
  sed -i 's/server_tokens off;/server_tokens on;/' /etc/nginx/nginx.conf 2>/dev/null || true
  grep -q '^expose_php=' "$PHP_VARS" \
    && sed -i -E 's/^expose_php=.*/expose_php=1/' "$PHP_VARS" \
    || echo 'expose_php=1' >> "$PHP_VARS"
fi

if [ "${REAL_IP_HEADER:-0}" = "1" ]; then
  sed -i "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" "$DEFAULT_SITE" || true
  sed -i "s/#set_real_ip_from/set_real_ip_from/" "$DEFAULT_SITE" || true
  if [ -n "${REAL_IP_FROM:-}" ]; then
    sed -i "s#172.16.0.0/12#${REAL_IP_FROM}#" "$DEFAULT_SITE" || true
  fi

  if [ -f "$SSL_SITE" ]; then
    sed -i "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" "$SSL_SITE" || true
    sed -i "s/#set_real_ip_from/set_real_ip_from/" "$SSL_SITE" || true
    if [ -n "${REAL_IP_FROM:-}" ]; then
      sed -i "s#172.16.0.0/12#${REAL_IP_FROM}#" "$SSL_SITE" || true
    fi
  fi
fi

if [ -n "${PHP_ERRORS_STDERR:-}" ]; then
  grep -q '^log_errors=' "$PHP_VARS" || echo 'log_errors=1' >> "$PHP_VARS"
  grep -q '^error_log=' "$PHP_VARS" || echo 'error_log=/dev/stderr' >> "$PHP_VARS"
fi

if [ -n "${PHP_MEM_LIMIT:-}" ]; then
  sed -i -E "s/^memory_limit=.*/memory_limit=${PHP_MEM_LIMIT}/" "$PHP_VARS" 2>/dev/null || true
fi
if [ -n "${PHP_POST_MAX_SIZE:-}" ]; then
  sed -i -E "s/^post_max_size=.*/post_max_size=${PHP_POST_MAX_SIZE}/" "$PHP_VARS" 2>/dev/null || true
fi
if [ -n "${PHP_UPLOAD_MAX_FILESIZE:-}" ]; then
  sed -i -E "s/^upload_max_filesize=.*/upload_max_filesize=${PHP_UPLOAD_MAX_FILESIZE}/" "$PHP_VARS" 2>/dev/null || true
fi

if [ -n "${PUID:-}" ]; then
  PGID="${PGID:-$PUID}"
  deluser nginx 2>/dev/null || true
  addgroup -g "$PGID" nginx
  adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u "$PUID" nginx
else
  if [ -z "${SKIP_CHOWN:-}" ]; then
    chown -R nginx:nginx /var/www/html
  fi
fi

echo "date.timezone=${TZ:-Europe/Budapest}" > /usr/local/etc/php/conf.d/timezone.ini

mkdir -p /run/nginx /var/run

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf