#!/usr/bin/env bash
# wordpress-sqlite entrypoint wrapper.
#
# Keeps 100% of the upstream official WordPress entrypoint behaviour and
# only ensures the official "SQLite Database Integration" plugin is active
# via the wp-content/db.php drop-in before delegating:
#
#   1. make sure wp-content/plugins/sqlite-database-integration exists in the
#      live docroot (copied from /usr/src/wordpress seed when missing, so
#      volumes first created by plain WordPress also get upgraded cleanly),
#   2. generate wp-content/db.php from the plugin's db.copy template with the
#      same placeholder replacement the plugin's own activator uses,
#   3. make sure /var/www/sqlite exists (outside the docroot) and is writable
#      by www-data, migrating an old wp-content/database/ install if needed,
#   4. generate wp-config.php from the official wp-config-docker.php template
#      (core's config wizard always needs a real MySQL server, so we skip it
#      and let the user go straight to the install wizard instead),
#   5. exec the untouched upstream /usr/local/bin/docker-entrypoint.sh.
#
# The SQLite file itself defaults to /var/www/sqlite/.ht.sqlite — outside the
# web-accessible docroot so it can never be downloaded over HTTP — and is
# created by the plugin on first request. Persist it with a volume on
# /var/www/sqlite. Override the location from wp-config.php if needed:
#   -e WORDPRESS_DB_DIR=/somewhere/writable/ -e WORDPRESS_DB_FILE=.ht.sqlite
# (both values are quoted automatically when written into wp-config.php)
set -Eeuo pipefail

DOCROOT="/var/www/html"
SEED="/usr/src/wordpress"
PLUGIN_SLUG="sqlite-database-integration"
PLUGIN_MAIN="sqlite-database-integration/load.php"

cd "$DOCROOT"

# 1. Ensure the official plugin is present in the live docroot.
if [ ! -f "wp-content/plugins/${PLUGIN_MAIN}" ]; then
	if [ -f "${SEED}/wp-content/plugins/${PLUGIN_MAIN}" ]; then
		echo >&2 "sqlite-entrypoint: installing '${PLUGIN_SLUG}' plugin into wp-content/plugins..."
		mkdir -p wp-content/plugins
		cp -a "${SEED}/wp-content/plugins/${PLUGIN_SLUG}" "wp-content/plugins/"
		chown -R www-data:www-data "wp-content/plugins/${PLUGIN_SLUG}" 2>/dev/null || true
	else
		echo >&2 "sqlite-entrypoint: WARNING: plugin seed not found at ${SEED}/wp-content/plugins/${PLUGIN_MAIN}"
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
		echo >&2 "sqlite-entrypoint: WARNING: '$DROPIN' exists and is not the SQLite drop-in; leaving it untouched."
	fi

	if [ "$needs_dropin" = '1' ]; then
		echo >&2 "sqlite-entrypoint: installing SQLite db.php drop-in..."
		sed -e "s#{SQLITE_IMPLEMENTATION_FOLDER_PATH}#${PLUGIN_DIR}#g" \
			-e "s#{SQLITE_PLUGIN}#${PLUGIN_MAIN}#g" \
			"${PLUGIN_DIR}/db.copy" > "$DROPIN"
		chown www-data:www-data "$DROPIN" 2>/dev/null || true
		chmod 644 "$DROPIN"
	fi
else
	echo >&2 "sqlite-entrypoint: WARNING: ${PLUGIN_DIR}/db.copy not found, skipping drop-in setup."
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
		echo >&2 "sqlite-entrypoint: migrating SQLite database from $OLD_DB_DIR to $DB_DIR ..."
		mkdir -p "$DB_DIR"
		mv "$OLD_DB_DIR"/.ht.sqlite* "$DB_DIR"/
		chown -R www-data:www-data "$DB_DIR" 2>/dev/null || true
	fi
fi
if [ -s wp-config.php ] && grep -q "wp-content/database" wp-config.php; then
	echo >&2 "sqlite-entrypoint: repointing wp-config.php DB_DIR to $DB_DIR ..."
	sed -i "/define( 'DB_DIR',/{/wp-content\/database/s#.*#define( 'DB_DIR', '$DB_DIR/' );#}" wp-config.php
	chown www-data:www-data wp-config.php 2>/dev/null || true
fi

mkdir -p "$DB_DIR"
chown www-data:www-data "$DB_DIR" 2>/dev/null || true
chmod 750 "$DB_DIR" 2>/dev/null || true

# 4. Ensure a wp-config.php exists. Core WordPress' config wizard always
# connects to a real MySQL server (it re-builds $wpdb without any db.php
# drop-in), so it can never succeed on this image — generate the config
# from the very same wp-config-docker.php template the official image uses,
# but point it at the SQLite drop-in instead. The user then finishes the
# ordinary install wizard (site title + admin account) on install.php.
if [ ! -s wp-config.php ]; then
	echo >&2 "sqlite-entrypoint: no wp-config.php found - generating SQLite config..."
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
		echo >&2 "sqlite-entrypoint: ERROR: no wp-config template found!"
		exit 1
	fi

	db_dir="${WORDPRESS_DB_DIR:-/var/www/sqlite/}"
	db_file="${WORDPRESS_DB_FILE:-.ht.sqlite}"
	# Tolerate the previously documented quoted style ("'/app/sqlite/'"):
	# strip one pair of matching outer single quotes before emitting.
	case "$db_dir" in
		"'"*"'") db_dir="${db_dir#\'}"; db_dir="${db_dir%\'}" ;;
	esac
	case "$db_file" in
		"'"*"'") db_file="${db_file#\'}"; db_file="${db_file%\'}" ;;
	esac

	{
		echo '<?php'
		echo '/**'
		echo ' * Generated by sqlite-entrypoint.sh for the SQLite drop-in.'
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
	echo >&2 "sqlite-entrypoint: wp-config.php generated (SQLite at ${db_dir}${db_file})."
fi

# 5. Hand over to the upstream official WordPress entrypoint.
exec /usr/local/bin/docker-entrypoint.sh "$@"
