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
#   3. make sure wp-content/database/ exists and is writable by www-data,
#   4. exec the untouched upstream /usr/local/bin/docker-entrypoint.sh.
#
# The SQLite file itself defaults to wp-content/database/.ht.sqlite and is
# created by the plugin on first request. Persist it with a volume on
# /var/www/html. Override the location from wp-config.php if needed:
#   -e WORDPRESS_CONFIG_EXTRA="define('DB_DIR','/var/www/html/wp-content/database'); define('DB_FILE','.ht.sqlite');"
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

# 3. Ensure the database directory exists and is writable.
mkdir -p wp-content/database
chown www-data:www-data wp-content/database 2>/dev/null || true
chmod 775 wp-content/database 2>/dev/null || true

# 4. Hand over to the upstream official WordPress entrypoint.
exec /usr/local/bin/docker-entrypoint.sh "$@"
