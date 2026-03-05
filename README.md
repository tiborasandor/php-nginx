# php-nginx

Rugalmas PHP-Nginx Docker image saját webalkalmazások futtatásához

## Tartalom

- PHP-FPM + Nginx egy konténerben  
- Unix socket alapú PHP-FPM kapcsolat  
- Futás közbeni konfigurálható környezet  
- PHP beállítások environment változókból  
- Git alapú deploy lehetőség

## Technikai jellemzők

- PHP 8.5 FPM Alpine alapon
- Nginx + Supervisor
- Unix socket alapú PHP-FPM kapcsolat (`/var/run/php-fpm.sock`)
- MySQL támogatás (`pdo_mysql`, `mysqli`)
- Alap PHP beállítások:
  - `upload_max_filesize=100M`
  - `post_max_size=100M`
  - `memory_limit=128M`
  - `cgi.fix_pathinfo=0`

## Alapértelmezett útvonalak

- Webroot: `/var/www/html`
- Nginx site config: `/etc/nginx/sites-available/default.conf`
- PHP-FPM pool config: `/usr/local/etc/php-fpm.d/www.conf`
- PHP ini override: `/usr/local/etc/php/conf.d/docker-vars.ini`