#!/usr/bin/env bash
# multisite-wp-sqlite entrypoint wrapper.
#
# Keeps 100% of the upstream official WordPress entrypoint behaviour and
# turns every install into a WordPress MULTISITE network backed by the
# official "SQLite Database Integration" plugin (via the wp-content/db.php
# drop-in). There is no switch: this image is dedicated to multisite — use
# the plain wordpress-sqlite image for single sites.
#
#   1. make sure wp-content/plugins/sqlite-database-integration exists in the
#      live docroot (copied from /usr/src/wordpress seed when missing),
#   2. generate wp-content/db.php from the plugin's db.copy template,
#   3. make sure /var/www/sqlite exists (outside the docroot) and is writable
#      by www-data, migrating an old wp-content/database/ install if needed,
#   4. generate wp-config.php from the official wp-config-docker.php template
#      (single-site for now — network constants are injected only once the
#      network tables exist, see below),
#   5. multisite orchestration, based on cheap SQLite state detection:
#        - network already populated  -> inject the managed MULTISITE
#          constants block into wp-config.php + network .htaccess rules,
#        - single site installed      -> convert it to a network in place
#          (wp-multisite-setup.php: install_network + populate_network),
#        - nothing installed yet      -> headless-install site + network when
#          WORDPRESS_ADMIN_USER/PASSWORD/EMAIL are set, otherwise ask the
#          user to finish the install wizard (conversion happens on the next
#          start — WordPress cannot bootstrap a network before it exists),
#   6. exec the untouched upstream /usr/local/bin/docker-entrypoint.sh.
#
# Environment variables (all optional):
#   WORDPRESS_URL                  site URL, e.g. http://localhost:8080
#                                  (headless install: sets siteurl/home and
#                                  derives the network domain from it)
#   WORDPRESS_ADMIN_USER           headless install: admin login
#   WORDPRESS_ADMIN_PASSWORD       headless install: admin password
#   WORDPRESS_ADMIN_EMAIL          headless install: admin email
#   WORDPRESS_SITE_TITLE           headless install: network title
#   WORDPRESS_DOMAIN_CURRENT_SITE  network domain (e.g. localhost:8080);
#                                  default: derived from WORDPRESS_URL or the
#                                  installed siteurl. With a non-standard port
#                                  the port MUST be part of the domain — core
#                                  only strips :80/:443 when matching hosts.
#   WORDPRESS_SUBDOMAIN_INSTALL    truthy = subdomain mode (site2.example.com,
#                                  needs wildcard DNS); default: subdirectory
#                                  mode (site2 under the main site's path).
#   WORDPRESS_TABLE_PREFIX         table prefix (default wp_)
#   WORDPRESS_DB_DIR/DB_FILE       SQLite location, defaults /var/www/sqlite/
#                                  and .ht.sqlite; quoted values are tolerated.
#   All upstream WORDPRESS_* variables keep working.
set -Eeuo pipefail

DOCROOT="/var/www/html"
SEED="/usr/src/wordpress"
PLUGIN_SLUG="sqlite-database-integration"
PLUGIN_MAIN="sqlite-database-integration/load.php"
BLOCK_BEGIN="// BEGIN wordpress-sqlite-multisite (managed by multisite-entrypoint.sh; do not edit)"
BLOCK_END="// END wordpress-sqlite-multisite"

cd "$DOCROOT"

truthy() {
	case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
		1 | true | yes | on) return 0 ;;
		*) return 1 ;;
	esac
}

strip_outer_single_quotes() {
	# Tolerate the previously documented quoted style ("'/app/sqlite/'").
	local v="${1:-}"
	case "$v" in
		"'"*"'") v="${v#\'}"; v="${v%\'}" ;;
	esac
	printf '%s' "$v"
}

# 1. Ensure the official plugin is present in the live docroot.
if [ ! -f "wp-content/plugins/${PLUGIN_MAIN}" ]; then
	if [ -f "${SEED}/wp-content/plugins/${PLUGIN_MAIN}" ]; then
		echo >&2 "multisite-entrypoint: installing '${PLUGIN_SLUG}' plugin into wp-content/plugins..."
		mkdir -p wp-content/plugins
		cp -a "${SEED}/wp-content/plugins/${PLUGIN_SLUG}" "wp-content/plugins/"
		chown -R www-data:www-data "wp-content/plugins/${PLUGIN_SLUG}" 2>/dev/null || true
	else
		echo >&2 "multisite-entrypoint: WARNING: plugin seed not found at ${SEED}/wp-content/plugins/${PLUGIN_MAIN}"
	fi
fi

# 2. Ensure the wp-content/db.php drop-in exists (same replacement logic as
# the plugin's own sqlite_plugin_copy_db_file() activator).
PLUGIN_DIR="$DOCROOT/wp-content/plugins/${PLUGIN_SLUG}"
DROPIN="wp-content/db.php"
if [ -f "${PLUGIN_DIR}/db.copy" ]; then
	needs_dropin=0
	if [ ! -f "$DROPIN" ]; then
		needs_dropin=1
	elif grep -q '{SQLITE_IMPLEMENTATION_FOLDER_PATH}' "$DROPIN" 2>/dev/null; then
		# Unrendered template left behind — regenerate with the real path.
		needs_dropin=1
	elif grep -q 'SQLITE_DB_DROPIN_VERSION' "$DROPIN" 2>/dev/null; then
		# Existing SQLite drop-in: refresh it when it points elsewhere
		# (e.g. seed copied under a different docroot path).
		if ! grep -Fq "$PLUGIN_DIR" "$DROPIN" 2>/dev/null; then
			needs_dropin=1
		fi
	else
		echo >&2 "multisite-entrypoint: WARNING: '$DROPIN' exists and is not the SQLite drop-in; leaving it untouched."
	fi

	if [ "$needs_dropin" = '1' ]; then
		echo >&2 "multisite-entrypoint: installing SQLite db.php drop-in..."
		sed -e "s#{SQLITE_IMPLEMENTATION_FOLDER_PATH}#${PLUGIN_DIR}#g" \
			-e "s#{SQLITE_PLUGIN}#${PLUGIN_MAIN}#g" \
			"${PLUGIN_DIR}/db.copy" > "$DROPIN"
		chown www-data:www-data "$DROPIN" 2>/dev/null || true
		chmod 644 "$DROPIN"
	fi
else
	echo >&2 "multisite-entrypoint: WARNING: ${PLUGIN_DIR}/db.copy not found, skipping drop-in setup."
fi

# 3. Database directory: keep the SQLite file OUTSIDE the web-accessible
#    docroot (/var/www/html) so it can never be downloaded over HTTP, even if
#    a future Apache config change made ".ht*" files servable.
DB_DIR="/var/www/sqlite"
OLD_DB_DIR="$DOCROOT/wp-content/database"

# 3a. One-time migration for volumes created by older image versions, which
#     kept the database inside wp-content/database/: move the db file (with
#     its -wal/-shm sidecars) to the new location and repoint wp-config.php.
if [ -d "$OLD_DB_DIR" ]; then
	if [ ! -e "$DB_DIR/.ht.sqlite" ] && ls "$OLD_DB_DIR"/.ht.sqlite* >/dev/null 2>&1; then
		echo >&2 "multisite-entrypoint: migrating SQLite database from $OLD_DB_DIR to $DB_DIR ..."
		mkdir -p "$DB_DIR"
		mv "$OLD_DB_DIR"/.ht.sqlite* "$DB_DIR"/
		chown -R www-data:www-data "$DB_DIR" 2>/dev/null || true
	fi
fi
if [ -s wp-config.php ] && grep -q "wp-content/database" wp-config.php; then
	echo >&2 "multisite-entrypoint: repointing wp-config.php DB_DIR to $DB_DIR ..."
	sed -i "/define( 'DB_DIR',/{/wp-content\/database/s#.*#define( 'DB_DIR', '$DB_DIR/' );#}" wp-config.php
	chown www-data:www-data wp-config.php 2>/dev/null || true
fi

mkdir -p "$DB_DIR"
chown www-data:www-data "$DB_DIR" 2>/dev/null || true
chmod 750 "$DB_DIR" 2>/dev/null || true

# 4. Ensure a wp-config.php exists. Core WordPress' config wizard always
#    connects to a real MySQL server (it re-builds $wpdb without any db.php
#    drop-in), so it can never succeed on this image — generate the config
#    from the very same wp-config-docker.php template the official image uses.
#    The MULTISITE constants are NOT written here: core cannot bootstrap a
#    network before its tables exist (ms-settings dies on the missing wp_site
#    table), so the block is injected by step 5 once the network is real.
if [ ! -s wp-config.php ]; then
	echo >&2 "multisite-entrypoint: no wp-config.php found - generating SQLite config..."
	config_template=""
	for candidate in \
		"wp-config-docker.php" \
		"${SEED}/wp-config-docker.php" \
		"${SEED}/wp-config-sample.php" \
	; do
		if [ -s "$candidate" ]; then
			config_template="$candidate"
			break
		fi
	done
	if [ -z "$config_template" ]; then
		echo >&2 "multisite-entrypoint: ERROR: no wp-config template found!"
		exit 1
	fi

	db_dir="$(strip_outer_single_quotes "${WORDPRESS_DB_DIR:-/var/www/sqlite/}")"
	db_file="$(strip_outer_single_quotes "${WORDPRESS_DB_FILE:-.ht.sqlite}")"

	{
		echo '<?php'
		echo '/**'
		echo ' * Generated by multisite-entrypoint.sh for the SQLite drop-in.'
		echo ' * Override the location with WORDPRESS_DB_DIR / WORDPRESS_DB_FILE.'
		echo ' */'
		echo "define( 'DB_DIR', '${db_dir}' );"
		echo "define( 'DB_FILE', '${db_file}' );"
		echo '?>'
		# Same salt replacement the upstream docker-entrypoint.sh does.
		awk '
			/put your unique phrase here/ {
				cmd = "head -c1m /dev/urandom | sha1sum | cut -d\\  -f1"
				cmd | getline str
				close(cmd)
				gsub("put your unique phrase here", str)
			}
			{ print }
		' "$config_template"
	} > wp-config.php.new

	chmod 644 wp-config.php.new
	mv wp-config.php.new wp-config.php
	chown www-data:www-data wp-config.php 2>/dev/null || true
	echo >&2 "multisite-entrypoint: wp-config.php generated (SQLite at ${db_dir}${db_file})."
fi

# 5. Multisite orchestration. All state detection reads the SQLite file
#    directly (no WordPress boot needed).
ms_db_dir="$(strip_outer_single_quotes "${WORDPRESS_DB_DIR:-/var/www/sqlite/}")"
ms_db_file="$(strip_outer_single_quotes "${WORDPRESS_DB_FILE:-.ht.sqlite}")"
sqlite_file="${ms_db_dir%/}/${ms_db_file#/}"

db_prefix="${WORDPRESS_TABLE_PREFIX:-}"
if [ -z "$db_prefix" ] && [ -s wp-config.php ]; then
	db_prefix="$(sed -n "s/^\$table_prefix *= *'\([^']*\)'.*/\1/p" wp-config.php | head -n1)"
fi
db_prefix="${db_prefix:-wp_}"

subdom=0
if truthy "${WORDPRESS_SUBDOMAIN_INSTALL:-}"; then
	subdom=1
fi

installed=0
networked=0
if [ -f "$sqlite_file" ]; then
	installed="$(sqlite3 "$sqlite_file" \
		"SELECT count(*) FROM sqlite_master WHERE type='table' AND name='${db_prefix}users';" 2>/dev/null || echo 0)"
	networked="$(sqlite3 "$sqlite_file" \
		"SELECT count(*) FROM sqlite_master WHERE type='table' AND name='${db_prefix}site';" 2>/dev/null || echo 0)"
	if [ "$networked" = '1' ]; then
		rows="$(sqlite3 "$sqlite_file" "SELECT count(*) FROM ${db_prefix}site;" 2>/dev/null || echo 0)"
		[ "${rows:-0}" -ge 1 ] 2>/dev/null || networked=0
	fi
fi
[ "$installed" = '1' ] || installed=0
[ "$networked" = '1' ] || networked=0

# The network domain must match what populate_network() stored (and core
# matches against HTTP_HOST, which only loses :80/:443 — keep other ports).
derive_domain_from_url() {
	local host
	host="$(printf '%s' "${1:-}" | sed -n 's|^[a-zA-Z][a-zA-Z0-9+.-]*://\([^/?#]*\).*|\1|p')"
	case "$host" in
		*:80) host="${host%:80}" ;;
		*:443) host="${host%:443}" ;;
	esac
	printf '%s' "$host" | tr '[:upper:]' '[:lower:]'
}

ms_domain="${WORDPRESS_DOMAIN_CURRENT_SITE:-}"
if [ -z "$ms_domain" ] && [ -n "${WORDPRESS_URL:-}" ]; then
	ms_domain="$(derive_domain_from_url "$WORDPRESS_URL")"
fi
if [ -z "$ms_domain" ] && [ "$installed" = '1' ] && [ -f "$sqlite_file" ]; then
	ms_domain="$(derive_domain_from_url \
		"$(sqlite3 "$sqlite_file" "SELECT option_value FROM ${db_prefix}options WHERE option_name='siteurl' LIMIT 1;" 2>/dev/null || true)")"
fi
if [ -z "$ms_domain" ]; then
	ms_domain='localhost'
	echo >&2 "multisite-entrypoint: WARNING: could not derive the network domain, falling back to '${ms_domain}' (set WORDPRESS_DOMAIN_CURRENT_SITE or WORDPRESS_URL to override)"
fi

# --- managed wp-config.php block (MULTISITE constants) ----------------------

strip_multisite_block() {
	awk '
		index($0, "// BEGIN wordpress-sqlite-multisite") { skip = 1; next }
		index($0, "// END wordpress-sqlite-multisite") { skip = 0; next }
		!skip { print }
	' wp-config.php
}

print_multisite_block() {
	local php_domain="${1//\'/\\\'}"
	local subdom_php='false'
	if [ "$2" = '1' ]; then
		subdom_php='true'
	fi
	cat <<BLOCK
${BLOCK_BEGIN}
define( 'MULTISITE', true );
define( 'SUBDOMAIN_INSTALL', ${subdom_php} );
define( 'DOMAIN_CURRENT_SITE', '${php_domain}' );
define( 'PATH_CURRENT_SITE', '/' );
define( 'SITE_ID_CURRENT_SITE', 1 );
define( 'BLOG_ID_CURRENT_SITE', 1 );
${BLOCK_END}
BLOCK
}

ensure_multisite_block() {
	local tmp out rc
	tmp="$(mktemp)"
	out="$(mktemp)"
	strip_multisite_block >"$tmp" || true
	# Insert before the "stop editing" marker (present in the official
	# template and in ordinary wp-config.php files); fall back to just before
	# the wp-settings require. Failing that, refuse loudly — appending after
	# the require would silently leave WordPress in single-site mode.
	MS_BLOCK="$(print_multisite_block "$ms_domain" "$subdom")" \
		MS_MARKER1="That's all, stop editing" \
		MS_MARKER2="wp-settings.php" \
		awk '
			!done && ( index($0, ENVIRON["MS_MARKER1"]) || index($0, ENVIRON["MS_MARKER2"]) ) {
				print ENVIRON["MS_BLOCK"]
				done = 1
			}
			{ print }
			END { if ( !done ) exit 3 }
		' "$tmp" >"$out"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		rm -f "$tmp" "$out"
		echo >&2 "multisite-entrypoint: ERROR: no insertion point found in wp-config.php (no 'stop editing' marker) — cannot manage the MULTISITE constants block."
		return 1
	fi
	mv "$out" wp-config.php
	rm -f "$tmp"
	chown www-data:www-data wp-config.php 2>/dev/null || true
}

remove_multisite_block() {
	if [ ! -s wp-config.php ]; then
		return 0
	fi
	local tmp
	tmp="$(mktemp)"
	strip_multisite_block >"$tmp"
	mv "$tmp" wp-config.php
	chown www-data:www-data wp-config.php 2>/dev/null || true
}

# --- managed .htaccess rules -------------------------------------------------

ensure_htaccess() {
	local ht="$DOCROOT/.htaccess"
	local block
	if [ "$subdom" = '1' ]; then
		# Subdomain installs need no extra rules beyond the ordinary ones.
		block='# BEGIN WordPress
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
# END WordPress'
	else
		# Subdirectory installs need the network rewrite block from the
		# wordpress.org "Create A Network" guide.
		block='# BEGIN WordPress
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteRule ^([_0-9a-zA-Z-]+/)?wp-admin$ $1wp-admin/ [R=301,L]
RewriteCond %{REQUEST_FILENAME} -f [OR]
RewriteCond %{REQUEST_FILENAME} -d
RewriteRule ^ - [L]
RewriteRule ^([_0-9a-zA-Z-]+/)?(wp-(content|admin|includes).*) $2 [L]
RewriteRule ^([_0-9a-zA-Z-]+/)?(.*\.php)$ $2 [L]
RewriteRule . index.php [L]
# END WordPress'
	fi

	local tmp
	tmp="$(mktemp)"
	if [ -f "$ht" ] && grep -q '^# BEGIN WordPress' "$ht" 2>/dev/null && grep -q '^# END WordPress' "$ht" 2>/dev/null; then
		MS_BLOCK="$block" awk '
			index($0, "# BEGIN WordPress") { print ENVIRON["MS_BLOCK"]; skip = 1; next }
			index($0, "# END WordPress") { skip = 0; next }
			!skip { print }
		' "$ht" >"$tmp"
		mv "$tmp" "$ht"
	elif [ -f "$ht" ]; then
		# Custom .htaccess without the standard markers: append, don't clobber.
		printf '\n%s\n' "$block" >>"$ht"
	else
		printf '%s\n' "$block" >"$ht"
	fi
	chown www-data:www-data "$ht" 2>/dev/null || true
}

# --- dispatch -----------------------------------------------------------------

run_wp_multisite_setup() {
	# wp-multisite-setup.php must run as www-data so the SQLite/WAL files it
	# creates stay writable by Apache. su (non-login) preserves the env.
	if [ "$(id -u)" = '0' ]; then
		su -s /bin/sh www-data -c "php /usr/local/bin/wp-multisite-setup.php $1"
	else
		php /usr/local/bin/wp-multisite-setup.php "$1"
	fi
}

if [ "$networked" = '1' ]; then
	if ! ensure_multisite_block; then
		echo >&2 "multisite-entrypoint: WARNING: MULTISITE constants not managed — the network may not bootstrap."
	fi
	ensure_htaccess
elif [ "$installed" = '1' ]; then
	# Wizard-installed single site: convert it to a network right now.
	# Safety first: never boot with MULTISITE constants while wp_site is empty.
	remove_multisite_block
	echo >&2 "multisite-entrypoint: converting the installed single site into a network..."
	if run_wp_multisite_setup populate-network; then
		ensure_multisite_block || true
		ensure_htaccess
	else
		echo >&2 "multisite-entrypoint: WARNING: network conversion failed — starting as a single site, will retry on the next start."
	fi
else
	# Nothing installed yet. Headless-install site + network when credentials
	# are provided; otherwise the install wizard runs and the conversion
	# happens on the next start (WordPress cannot bootstrap a network before
	# the site exists — wp_install() never populates one).
	remove_multisite_block
	if [ -n "${WORDPRESS_ADMIN_USER:-}" ] && [ -n "${WORDPRESS_ADMIN_PASSWORD:-}" ] && [ -n "${WORDPRESS_ADMIN_EMAIL:-}" ]; then
		echo >&2 "multisite-entrypoint: headless install requested — creating site + network..."
		if run_wp_multisite_setup install; then
			ensure_multisite_block || true
			ensure_htaccess
		else
			echo >&2 "multisite-entrypoint: WARNING: headless install failed — check the credentials, then retry (or finish the install wizard; the network is created on the next start)."
		fi
	else
		echo >&2 "multisite-entrypoint: WordPress is not installed yet — open the site and finish the install wizard. The network is created automatically on the next container start (or set WORDPRESS_ADMIN_USER/PASSWORD/EMAIL for a fully headless install)."
	fi
fi

# 6. Hand over to the upstream official WordPress entrypoint.
exec /usr/local/bin/docker-entrypoint.sh "$@"
