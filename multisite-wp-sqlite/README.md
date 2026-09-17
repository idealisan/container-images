# multisite-wp-sqlite

Official WordPress Docker image running a **multisite network** on a local
SQLite database. No MySQL needed, no env switch, no Tools > Network Setup
detour — the network is the default.

Based on the official `wordpress` image: same Apache + PHP stack, same
`docker-entrypoint.sh`, same `WORDPRESS_*` environment variables. The
database layer is the **official**
[SQLite Database Integration](https://wordpress.org/plugins/sqlite-database-integration/)
plugin by the WordPress Team, baked in and enabled as the `wp-content/db.php`
drop-in (it fully supports multisite: per-blog table prefixes like
`wp_2_posts` are handled by the driver). No third-party feature plugins.

For a **single-site** SQLite install use
[`wordpress-sqlite`](../wordpress-sqlite) instead — this image always runs a
network.

## Run

### Headless (recommended — network ready on first boot)

```sh
docker run -d --name wp-ms -p 8080:80 \
  -v wp-ms-sqlite:/var/www/html \
  -v wp-ms-sqlite-db:/var/www/sqlite \
  -e WORDPRESS_URL=http://localhost:8080 \
  -e WORDPRESS_ADMIN_USER=admin \
  -e WORDPRESS_ADMIN_PASSWORD=change-me \
  -e WORDPRESS_ADMIN_EMAIL=admin@example.com \
  ghcr.io/idealisan/container-images/multisite-wp-sqlite:latest
```

The entrypoint installs WordPress (site + admin account) **and** populates
the network on the first start — no install wizard, no restart. Log in at
`http://localhost:8080/wp-admin/` and you are a super admin.

### Wizard (no credentials provided)

```sh
docker run -d --name wp-ms -p 8080:80 \
  -v wp-ms-sqlite:/var/www/html \
  -v wp-ms-sqlite-db:/var/www/sqlite \
  ghcr.io/idealisan/container-images/multisite-wp-sqlite:latest
```

Open `http://localhost:8080`, finish the ordinary WordPress installer
(site title + admin account), then `docker restart wp-ms` **once** — the
entrypoint converts the installed site into a network automatically.

Or with Docker Compose (reference file in this directory, headless vars
commented out):

```sh
docker compose up -d
```

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `WORDPRESS_ADMIN_USER` | — | Headless install: admin login |
| `WORDPRESS_ADMIN_PASSWORD` | — | Headless install: admin password |
| `WORDPRESS_ADMIN_EMAIL` | — | Headless install: admin email |
| `WORDPRESS_SITE_TITLE` | `My WordPress Network` | Headless install: network title |
| `WORDPRESS_URL` | derived | Site URL (e.g. `http://localhost:8080`); sets `siteurl`/`home` on headless install and derives the network domain from it |
| `WORDPRESS_DOMAIN_CURRENT_SITE` | derived | Network domain for `DOMAIN_CURRENT_SITE`; overrides the derivation |
| `WORDPRESS_SUBDOMAIN_INSTALL` | `false` | `true` = subdomain mode (`site2.example.com`), default = subdirectory mode (`site.com/site2`) |
| `WORDPRESS_TABLE_PREFIX` | `wp_` | Table prefix |
| `WORDPRESS_DB_DIR` / `WORDPRESS_DB_FILE` | `/var/www/sqlite/` / `.ht.sqlite` | SQLite location (values are quoted automatically) |

All other upstream `WORDPRESS_*` variables keep working
(`WORDPRESS_DEBUG`, `WORDPRESS_CONFIG_EXTRA`, …). Database host/user/password
variables are irrelevant — there is no database server.

### Domain and ports (important)

WordPress core matches the network domain against `HTTP_HOST`, stripping
only `:80`/`:443`. If you browse to the site via a non-standard port (e.g.
`http://localhost:8080`), the domain **must include the port**:

```sh
-e WORDPRESS_DOMAIN_CURRENT_SITE=localhost:8080
# or simply:
-e WORDPRESS_URL=http://localhost:8080
```

Without it the entrypoint falls back to `localhost` with a warning, and
requests through the port will not match the network. When the value is not
given explicitly it is derived from `WORDPRESS_URL` or from the installed
site's `siteurl`, so `docker run -p 8080:80` + `WORDPRESS_URL=http://localhost:8080`
just works.

### Subdomain mode

```sh
-e WORDPRESS_SUBDOMAIN_INSTALL=true -e WORDPRESS_DOMAIN_CURRENT_SITE=example.com
```

Requires wildcard DNS (`*.example.com` → this host) and, for HTTPS, a
wildcard certificate. The container's Apache default vhost already serves
every host name, so no container-side configuration is needed.

### Adding sites

Subdirectory mode: Network Admin → Sites → Add New (e.g. `/site2`).
Subdomain mode: same screen, enter `site2` as the subdomain.

## Data

| Path | Purpose |
|------|---------|
| `/var/www/html` | WordPress install (mount a volume to persist) |
| `/var/www/sqlite/.ht.sqlite` | SQLite database file (+ `-wal`/`-shm` sidecars) — **outside the docroot**, so it can never be downloaded over HTTP |

All sites of the network share this single SQLite file.

### Upload limits

Uploads are raised to **50 MB** per file (official image default is 2 MB):
`upload_max_filesize = 50M`, `post_max_size = 64M`, `memory_limit = 256M`,
`max_execution_time = 120`, and Apache `LimitRequestBody` is set to 64 MB to
match. Mount your own `/usr/local/etc/php/conf.d/*.ini` to change them.

## How it works

- `Dockerfile` (`ARG WORDPRESS_IMAGE`, default `wordpress:7.1-php8.3-apache`):
  `pdo_sqlite`/`sqlite3` are already compiled into the official base image —
  only verified here — the official plugin zip is downloaded from
  `downloads.wordpress.org` into `/usr/src/wordpress/wp-content/plugins/`
  (its `db.copy` placeholders are grep-verified at build time), upload
  limits are raised to 50 MB, and `/var/www/sqlite` is pre-created outside
  the docroot.
- `multisite-entrypoint.sh`: on every start ensures the plugin + `db.php`
  drop-in exist in the live docroot, generates a single-site
  `wp-config.php` if missing, then reads the install/network state directly
  from the SQLite file (`sqlite3` CLI) and dispatches:
  - **network populated** → injects the managed `MULTISITE` constants block
    into `wp-config.php` (marked `// BEGIN/END wordpress-sqlite-multisite`)
    and the network rewrite rules into `.htaccess` (subdirectory mode) or
    the ordinary rules (subdomain mode);
  - **single site installed** → converts it in place with
    `wp-multisite-setup.php` (`install_network()` + `populate_network()`,
    exactly what the admin "Network Setup" screen does), then injects the
    constants;
  - **nothing installed** → headless-installs site + network when
    `WORDPRESS_ADMIN_*` credentials are set, otherwise lets the install
    wizard run (core cannot bootstrap a network before the site exists —
    `wp_install()` never populates one).
- `wp-multisite-setup.php`: CLI-only helper (runs as `www-data` so the
  SQLite/WAL files stay writable by Apache). Boots through `wp-load.php`,
  so everything happens on the SQLite plugin's `db.php` drop-in.
- The managed constants block and the `.htaccess` rules are idempotent:
  every start re-ensures them, so switching
  `WORDPRESS_SUBDOMAIN_INSTALL`/`WORDPRESS_DOMAIN_CURRENT_SITE` and
  restarting updates them in place.

## Versions

| Component | Default |
|-----------|---------|
| Base image | `wordpress:7.1-php8.3-apache` (bump via `WORDPRESS_IMAGE`) |
| SQLite plugin | `3.0.2` (bump via `SQLITE_PLUGIN_VERSION`) |
| Multisite | always on (network), subdirectory mode by default |
