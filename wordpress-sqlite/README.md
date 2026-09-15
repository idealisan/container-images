# wordpress-sqlite

Official WordPress Docker image + local SQLite database. No MySQL needed.

Everything behaves exactly like the official `wordpress` image (same Apache +
PHP stack, same `docker-entrypoint.sh` install wizard, same `WORDPRESS_*`
environment variables) except the database layer: the **official**
[SQLite Database Integration](https://wordpress.org/plugins/sqlite-database-integration/)
plugin by the WordPress Team is baked in and enabled as the
`wp-content/db.php` drop-in. No third-party feature plugins are installed.

## Run

```sh
docker run -d --name wp -p 8080:80 \
  -v wp-sqlite:/var/www/html \
  -v wp-sqlite-db:/var/www/sqlite \
  ghcr.io/idealisan/container-images/wordpress-sqlite:latest
```

Then open `http://localhost:8080` and finish the WordPress installer.
You can skip all `WORDPRESS_DB_*` variables — there is no database server.

Or with Docker Compose (reference file in this directory):

```sh
docker compose up -d   # uses compose.yaml: port 8080, named volume wp_data
```

## Data

| Path | Purpose |
|------|---------|
| `/var/www/html` | WordPress install (mount a volume to persist) |
| `/var/www/sqlite/.ht.sqlite` | SQLite database file (+ `-wal`/`-shm` sidecars) — **outside the docroot**, so it can never be downloaded over HTTP |

Back up the `/var/www/sqlite/` volume like you would back up MySQL dumps for
a classic install.

### Upload limits

Uploads are raised to **50 MB** per file (official image default is 2 MB):
`upload_max_filesize = 50M`, `post_max_size = 64M`, `memory_limit = 256M`,
`max_execution_time = 120`, and Apache `LimitRequestBody` is set to 64 MB to
match. Configure via `WORDPRESS_CONFIG_EXTRA` or mount your own
`/usr/local/etc/php/conf.d/*.ini` if you need different values.

## Configuration

All upstream `WORDPRESS_*` variables keep working
(`WORDPRESS_TABLE_PREFIX`, `WORDPRESS_DEBUG`, `WORDPRESS_CONFIG_EXTRA`, …).
Database host/user/password variables are simply irrelevant.

On first start (when no `wp-config.php` exists yet) the entrypoint
auto-generates a SQLite-aware config from the official
`wp-config-docker.php` template, so you skip core's MySQL credential form
and go straight to the ordinary WordPress install wizard (site title +
admin account). The SQLite database file is created in
`/var/www/sqlite/` automatically.

Custom SQLite location (defaults shown):

```sh
# via dedicated variables (no WORDPRESS_CONFIG_EXTRA needed)
-e WORDPRESS_DB_DIR="'/app/sqlite/'" \
-e WORDPRESS_DB_FILE=".ht.sqlite"
```

> Note: `WORDPRESS_DB_DIR` is a PHP expression (it ends up inside
> `define( 'DB_DIR', … )`), so the default is `'/var/www/sqlite/'`.

## Upgrading from older versions

Versions of this image before 2026-09 kept the database inside the docroot
at `wp-content/database/`. The entrypoint migrates those automatically on
first start: the `.ht.sqlite*` files are moved to `/var/www/sqlite/` and
`wp-config.php` is repointed — no manual action needed (make sure both
volumes are mounted).

## How it works

- `Dockerfile` (`ARG WORDPRESS_IMAGE`, default `wordpress:7.1-php8.3-apache`):
  `pdo_sqlite`/`sqlite3` are already compiled into the official base image —
  only verified here — the official plugin zip is downloaded from
  `downloads.wordpress.org` into `/usr/src/wordpress/wp-content/plugins/`,
  upload limits are raised to 50 MB, and `/var/www/sqlite` is pre-created
  outside the docroot.
- `sqlite-entrypoint.sh`: on every start ensures the plugin exists in the
  live docroot (so volumes first created by plain WordPress upgrade cleanly),
  renders `wp-content/db.php` from the plugin's `db.copy` template with the
  same replacement the plugin activator uses, ensures `/var/www/sqlite` is
  writable (migrating an old `wp-content/database/` install if needed),
  generates `wp-config.php` if missing, then execs the untouched upstream
  `docker-entrypoint.sh`.

## Versions

| Component | Default |
|-----------|---------|
| Base image | `wordpress:7.1-php8.3-apache` (bump via `WORDPRESS_IMAGE`) |
| SQLite plugin | `3.0.2` (bump via `SQLITE_PLUGIN_VERSION`) |
| PHP extensions added | `pdo_sqlite`, `sqlite3` (+ `sqlite3` CLI) |
