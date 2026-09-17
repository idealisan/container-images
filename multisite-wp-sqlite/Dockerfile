# WordPress multisite + SQLite (no MySQL needed).
#
# A dedicated, multisite-first variant of the wordpress-sqlite image: based on
# the official WordPress Docker image, with the official "SQLite Database
# Integration" plugin (WordPress Team, wordpress.org) baked in as the
# wp-content/db.php drop-in, and WordPress configured as a multisite NETWORK
# out of the box — no env switch, no Tools > Network Setup detour.
#
# The database lives in a local SQLite file under /var/www/sqlite — outside
# the web-accessible docroot, so it can never be downloaded over HTTP.
# Upload limits are raised to 50 MB per file.
#
# Installation paths (handled by multisite-entrypoint.sh):
#   - Headless (zero restart): set WORDPRESS_ADMIN_USER / WORDPRESS_ADMIN_PASSWORD /
#     WORDPRESS_ADMIN_EMAIL (+ optional WORDPRESS_URL / WORDPRESS_SITE_TITLE) and the
#     container bootstraps the single site AND the network on first start.
#   - Wizard (default): open http://localhost:8080, finish the ordinary installer,
#     then `docker restart` once — the entrypoint converts the site to a network.
#
# Build args:
#   WORDPRESS_IMAGE        base official image (default pins WP 7.1 + PHP 8.3)
#   SQLITE_PLUGIN_VERSION  official plugin version from wordpress.org
#
# Run:
#   docker run -d -p 8080:80 \
#     -v wp-ms-sqlite:/var/www/html \
#     -v wp-ms-sqlite-db:/var/www/sqlite \
#     ghcr.io/idealisan/container-images/multisite-wp-sqlite:latest
# Then open http://localhost:8080, finish the installer, restart once.
ARG WORDPRESS_IMAGE=wordpress:7.1-php8.3-apache
FROM ${WORDPRESS_IMAGE}

ARG SQLITE_PLUGIN_VERSION=3.0.2

# pdo_sqlite and sqlite3 are already compiled into the official php base
# image (built with --with-pdo-sqlite=/usr --with-sqlite3=/usr), which the
# official SQLite plugin requires — just verify them here. The sqlite3 CLI
# is a small extra: the entrypoint uses it to detect install/network state.
#
# Bake the official SQLite Database Integration plugin into the seed tree
# (/usr/src/wordpress) so the upstream docker-entrypoint.sh copies it into
# /var/www/html on first start, exactly like any other bundled wp-content.
# Source: https://wordpress.org/plugins/sqlite-database-integration/
#
# The db.copy placeholder greps guard against the entrypoint's sed renderer
# silently breaking when a future plugin release renames its placeholders.
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends sqlite3 unzip; \
	rm -rf /var/lib/apt/lists/*; \
	php -m | grep -Ei 'pdo_sqlite|sqlite3'; \
	php -r '$v = SQLite3::version(); if (version_compare($v["versionString"], "3.37.0", "<")) { fwrite(STDERR, "SQLite too old: " . $v["versionString"] . "\n"); exit(1); } echo "SQLite library: " . $v["versionString"] . PHP_EOL;'; \
	cd /tmp; \
	curl -fL -o sqlite-database-integration.zip \
		"https://downloads.wordpress.org/plugin/sqlite-database-integration.${SQLITE_PLUGIN_VERSION}.zip"; \
	plugin_dir=/usr/src/wordpress/wp-content/plugins/sqlite-database-integration; \
	mkdir -p /usr/src/wordpress/wp-content/plugins; \
	rm -rf "$plugin_dir"; \
	unzip -q sqlite-database-integration.zip -d /usr/src/wordpress/wp-content/plugins; \
	rm sqlite-database-integration.zip; \
	test -f "$plugin_dir/load.php"; \
	test -f "$plugin_dir/db.copy"; \
	grep -Fq '{SQLITE_IMPLEMENTATION_FOLDER_PATH}' "$plugin_dir/db.copy"; \
	grep -Fq '{SQLITE_PLUGIN}' "$plugin_dir/db.copy"; \
	chown -R www-data:www-data "$plugin_dir"; \
	apt-get purge -y --auto-remove unzip; \
	rm -rf /var/lib/apt/lists/*

# Pre-create the SQLite directory OUTSIDE the docroot (/var/www/html), so the
# database file is never reachable over HTTP. The entrypoint re-ensures this
# at runtime (named volumes mount over it, so permissions are re-applied).
RUN set -eux; \
	mkdir -p /var/www/sqlite; \
	chown www-data:www-data /var/www/sqlite; \
	chmod 750 /var/www/sqlite

# Raise upload limits (the official image only allows 2 MB uploads) and make
# Apache accept bodies of the same size. post_max_size must be >=
# upload_max_filesize, and LimitRequestBody >= post_max_size.
RUN set -eux; \
	{ \
		echo "upload_max_filesize = 50M"; \
		echo "post_max_size = 64M"; \
		echo "memory_limit = 256M"; \
		echo "max_execution_time = 120"; \
	} > /usr/local/etc/php/conf.d/wordpress-uploads.ini; \
	{ \
		echo "LimitRequestBody 67108864"; \
	} > /etc/apache2/conf-available/wordpress-limits.conf; \
	a2enconf wordpress-limits

# Wrapper entrypoint: ensures the plugin + db.php drop-in exist in the live
# docroot, generates a SQLite wp-config.php, installs/bootstrap the multisite
# network (headless or converts a wizard-installed single site), then chains
# into the untouched upstream docker-entrypoint.sh.
# wp-multisite-setup.php is the CLI helper doing wp_install /
# install_network + populate_network on the SQLite database.
COPY multisite-entrypoint.sh wp-multisite-setup.php /usr/local/bin/
RUN chmod +x /usr/local/bin/multisite-entrypoint.sh

ENTRYPOINT ["multisite-entrypoint.sh"]
CMD ["apache2-foreground"]
