FROM php:8.5.3-fpm-alpine3.23

LABEL maintainer="tiborasandor"

ENV LD_PRELOAD=/usr/lib/preloadable_libiconv.so \
    PHP_CONF=/usr/local/etc/php-fpm.conf \
    FPM_CONF=/usr/local/etc/php-fpm.d/www.conf \
    PHP_VARS=/usr/local/etc/php/conf.d/docker-vars.ini

RUN apk add --no-cache \
    nginx \
    supervisor \
    gnu-libiconv \
    tzdata \
    curl \
    git \
    unzip \
    bash

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Install PHP extensions
RUN apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    mariadb-dev && \
    docker-php-ext-install pdo_mysql mysqli && \
    apk del .build-deps

# Directory structure
RUN rm -rf /var/www/* && \
    mkdir -p \
    /etc/supervisor \
    /etc/nginx/sites-available \
    /etc/nginx/sites-enabled \
    /etc/nginx/certs \
    /run/nginx \
    /var/www/html && \
    chown -R nginx:nginx /var/www/html

# Config
COPY conf/supervisord.conf /etc/supervisor/supervisord.conf
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/nginx-site.conf /etc/nginx/sites-available/default.conf
COPY conf/nginx-site-ssl.conf /etc/nginx/sites-available/default-ssl.conf
RUN ln -sf /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf

RUN echo "cgi.fix_pathinfo=0" > ${PHP_VARS} && \
    echo "upload_max_filesize=100M" >> ${PHP_VARS} &&\
    echo "post_max_size=100M" >> ${PHP_VARS} &&\
    echo "variables_order=\"EGPCS\"" >> ${PHP_VARS} && \
    echo "memory_limit=128M" >> ${PHP_VARS} && \
    sed -i -E \
    -e 's#^[;[:space:]]*catch_workers_output[[:space:]]*=[[:space:]]*yes#catch_workers_output = yes#' \
    -e 's#^[;[:space:]]*pm\.max_children[[:space:]]*=.*#pm.max_children = 4#' \
    -e 's#^[;[:space:]]*pm\.start_servers[[:space:]]*=.*#pm.start_servers = 3#' \
    -e 's#^[;[:space:]]*pm\.min_spare_servers[[:space:]]*=.*#pm.min_spare_servers = 2#' \
    -e 's#^[;[:space:]]*pm\.max_spare_servers[[:space:]]*=.*#pm.max_spare_servers = 4#' \
    -e 's#^[;[:space:]]*pm\.max_requests[[:space:]]*=.*#pm.max_requests = 200#' \
    -e 's#^[;[:space:]]*user[[:space:]]*=.*#user = nginx#' \
    -e 's#^[;[:space:]]*group[[:space:]]*=.*#group = nginx#' \
    -e 's#^[;[:space:]]*listen\.mode[[:space:]]*=.*#listen.mode = 0660#' \
    -e 's#^[;[:space:]]*listen\.owner[[:space:]]*=.*#listen.owner = nginx#' \
    -e 's#^[;[:space:]]*listen\.group[[:space:]]*=.*#listen.group = nginx#' \
    -e 's#^[;[:space:]]*listen[[:space:]]*=.*#listen = /var/run/php-fpm.sock#' \
    -e 's#^[;[:space:]]*clear_env[[:space:]]*=.*#clear_env = no#' \
    ${FPM_CONF}

# Startup script
COPY scripts/start.sh /start.sh
RUN chmod 755 /start.sh

# Application
WORKDIR /var/www/html
COPY app/ /var/www/html/

EXPOSE 443 80

CMD ["/start.sh"]