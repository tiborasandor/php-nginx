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

### Alap PHP beállítások

- `upload_max_filesize=100M`
- `post_max_size=100M`
- `memory_limit=128M`
- `cgi.fix_pathinfo=0`
- `opcache.enable=1` (`opcache.memory_consumption=128`, `opcache.max_accelerated_files=10000`, `opcache.validate_timestamps=1`, `opcache.revalidate_freq=2`)

> ⚠️ **Fontos:** az `app/` könyvtárban lévő `index.php` egy puszta `phpinfo()` placeholder. Éles használat előtt mindenképp cseréld le a saját alkalmazásodra (vagy mountold felül egy volume-mal) — a `phpinfo()` a teljes szerver- és környezeti változó listát (útvonalak, PHP config, `$_SERVER`) nyilvánosan elérhetővé teszi, ha véletlenül bent marad.

## Alapértelmezett útvonalak

- Webroot: `/var/www/html`
- Nginx site config: `/etc/nginx/sites-available/default.conf`
- PHP-FPM pool config: `/usr/local/etc/php-fpm.d/www.conf`
- PHP ini override: `/usr/local/etc/php/conf.d/docker-vars.ini`

## Gyors indítás

### Build

```bash
docker build -t tiborasandor/php-nginx .
```

### Egyszerű futtatás

```bash
docker run -d \
  --name php-nginx \
  -p 8081:80 \
  tiborasandor/php-nginx
```

### Framework alapú alkalmazás futtatása

```bash
docker run -d \
  --name php-nginx-app \
  -p 8081:80 \
  -e WEBROOT=/var/www/html/public \
  -e PHP_FRONT_CONTROLLER=1 \
  -v /srv/app/myapp:/var/www/html \
  tiborasandor/php-nginx
```

## Egyedi nginx konfiguráció

Ha az alkalmazás a következő fájlokat tartalmazza, a konténer induláskor felülírja velük az alapértelmezett nginx konfigurációt:

- `/var/www/html/conf/nginx/nginx.conf`
- `/var/www/html/conf/nginx/nginx-site.conf`
- `/var/www/html/conf/nginx/nginx-site-ssl.conf`

> Fontos: ezek a fájlok teljesen felülírják az image alap nginx konfigurációját.

## Környezeti változók

| Változó | Alapérték | Jelentés |
|--------|-----------|----------|
| WEBROOT | `/var/www/html` | Az nginx document root módosítása |
| PHP_FRONT_CONTROLLER | `0` | Framework routing támogatás (`index.php` fallback) |
| ENABLE_REAL_IP | `0` | Proxy mögötti valós kliens IP kezelés |
| REAL_IP_FROM | `172.16.0.0/12` | Megbízható proxy hálózat |
| OPCACHE_DISABLE | `0` | PHP opcache kikapcsolása |
| PHP_DISPLAY_ERRORS | `0` | PHP hibák megjelenítése böngészőben |
| PHP_LOG_ERRORS_TO_STDERR | `0` | PHP hibák `docker logs` felé küldése |
| PHP_MEM_LIMIT | `128M` | PHP memória limit |
| PHP_POST_MAX_SIZE | `100M` | POST méret limit |
| PHP_UPLOAD_MAX_FILESIZE | `100M` | Upload limit |
| HIDE_HEADERS | `1` | Nginx és PHP verzió headerek elrejtése |
| PUID | nincs | nginx user UID beállítása |
| PGID | PUID értéke | nginx group GID beállítása |
| SKIP_CHOWN | `0` | Tulajdonosváltás kihagyása |
| GIT_REPO | nincs | Git repository teljes URL-je (pl. `https://github.com/user/repo.git` vagy SSH esetén `git@github.com:user/repo.git`) |
| GIT_BRANCH | default branch | Klónozandó branch |
| GIT_TAG | nincs | Checkout tag |
| GIT_COMMIT | nincs | Checkout commit |
| GIT_USERNAME | nincs | HTTPS git felhasználónév |
| GIT_PERSONAL_TOKEN | nincs | HTTPS git token |
| GIT_USE_SSH | `0` | SSH alapú git klónozás |
| GIT_NAME | nincs | Git user.name |
| GIT_EMAIL | nincs | Git user.email |
| REMOVE_FILES | `1` | Klónozás előtt törli a webroot tartalmát |
| RUN_COMPOSER | `0` | Composer install futtatása |
| APPLICATION_ENV | `production` | Composer dev dependency kezelés |
| TZ | `Europe/Budapest` | PHP timezone |

## Megjegyzések

- A git alapú deploy mindig a `/var/www/html` könyvtárba klónoz.
- `GIT_REPO` mindig a teljes URL-t várja (séma előtaggal), `GIT_USERNAME`/`GIT_PERSONAL_TOKEN` megadása esetén is. A hitelesítő adatokat a konténer nem ágyazza bele az URL-be, hanem `GIT_ASKPASS`-on keresztül adja át gitnek, hogy azok ne jelenjenek meg a klónozó parancs argumentumaiban.
- A `WEBROOT` csak az nginx kiszolgálási gyökérkönyvtárát módosítja.
- Framework alapú alkalmazásoknál általában ez a két beállítás szükséges:

```bash
WEBROOT=/var/www/html/public
PHP_FRONT_CONTROLLER=1
```

- Read-only volume mount esetén ajánlott:

```bash
SKIP_CHOWN=1
```
