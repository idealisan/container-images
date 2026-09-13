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
docker run -d --name wp -p 8080:80 -v wp-sqlite:/var/www/html \
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
| `/var/www/html/wp-content/database/.ht.sqlite` | SQLite database file (+ `-wal`/`-shm` sidecars) |

Back up the `wp-content/database/` directory (or the whole volume) like you
would back up MySQL dumps for a classic install.

## Configuration

All upstream `WORDPRESS_*` variables keep working
(`WORDPRESS_TABLE_PREFIX`, `WORDPRESS_DEBUG`, `WORDPRESS_CONFIG_EXTRA`, …).
Database host/user/password variables are simply irrelevant.

On first start (when no `wp-config.php` exists yet) the entrypoint
auto-generates a SQLite-aware config from the official
`wp-config-docker.php` template, so you skip core's MySQL credential form
and go straight to the ordinary WordPress install wizard (site title +
admin account). The SQLite database file is created in
`wp-content/database/` automatically.

Custom SQLite location (defaults shown):

```sh
# via dedicated variables (no WORDPRESS_CONFIG_EXTRA needed)
-e WORDPRESS_DB_DIR="'/app/sqlite/'" \
-e WORDPRESS_DB_FILE=".ht.sqlite"
```

> Note: `WORDPRESS_DB_DIR` is a PHP expression (it ends up inside
> `define( 'DB_DIR', … )`), so the default is `__DIR__ . '/wp-content/database/'`.

## How it works

- `Dockerfile` (`ARG WORDPRESS_IMAGE`, default `wordpress:7.1-php8.3-apache`):
  `pdo_sqlite`/`sqlite3` are already compiled into the official base image —
  only verified here — and the official plugin zip is downloaded from
  `downloads.wordpress.org` into `/usr/src/wordpress/wp-content/plugins/`.
- `sqlite-entrypoint.sh`: on every start ensures the plugin exists in the
  live docroot (so volumes first created by plain WordPress upgrade cleanly),
  renders `wp-content/db.php` from the plugin's `db.copy` template with the
  same replacement the plugin activator uses, ensures
  `wp-content/database/` is writable, generates `wp-config.php` if missing,
  then execs the untouched upstream `docker-entrypoint.sh`.

## Versions

| Component | Default |
|-----------|---------|
| Base image | `wordpress:7.1-php8.3-apache` (bump via `WORDPRESS_IMAGE`) |
| SQLite plugin | `3.0.2` (bump via `SQLITE_PLUGIN_VERSION`) |
| PHP extensions added | `pdo_sqlite`, `sqlite3` (+ `sqlite3` CLI) |
