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

Optional overrides via `WORDPRESS_CONFIG_EXTRA`:

```sh
# Custom SQLite location (defaults shown)
-e WORDPRESS_CONFIG_EXTRA="define('DB_DIR','/var/www/html/wp-content/database'); define('DB_FILE','.ht.sqlite');"
```

## How it works

- `Dockerfile` (`ARG WORDPRESS_IMAGE`, default `wordpress:7.1-php8.3-apache`):
  installs the `pdo_sqlite`/`sqlite3` PHP extensions and downloads the
  official plugin zip from `downloads.wordpress.org` into
  `/usr/src/wordpress/wp-content/plugins/`.
- `sqlite-entrypoint.sh`: on every start ensures the plugin exists in the
  live docroot (so volumes first created by plain WordPress upgrade cleanly),
  renders `wp-content/db.php` from the plugin's `db.copy` template with the
  same replacement the plugin activator uses, ensures
  `wp-content/database/` is writable, then execs the untouched upstream
  `docker-entrypoint.sh`.

## Versions

| Component | Default |
|-----------|---------|
| Base image | `wordpress:7.1-php8.3-apache` (bump via `WORDPRESS_IMAGE`) |
| SQLite plugin | `3.0.2` (bump via `SQLITE_PLUGIN_VERSION`) |
| PHP extensions added | `pdo_sqlite`, `sqlite3` (+ `sqlite3` CLI) |
