# WordPress + SQLite (no MySQL needed).
#
# Based on the official WordPress Docker image, everything stays identical
# except the database layer: the official
# "SQLite Database Integration" plugin (WordPress Team, distributed on
# wordpress.org, no third-party feature plugins) is baked in and wired up
# as the wp-content/db.php drop-in. The site database lives in a local
# SQLite file under wp-content/database/ instead of a MySQL server.
#
# Build args:
#   WORDPRESS_IMAGE        base official image (default pins WP 7.1 + PHP 8.3)
#   SQLITE_PLUGIN_VERSION  official plugin version from wordpress.org
#
# Run:
#   docker run -d -p 8080:80 \
#     -v wp-sqlite:/var/www/html \
#     ghcr.io/idealisan/container-images/wordpress-sqlite:latest
# Then open http://localhost:8080 and finish the WordPress installer.
# No WORDPRESS_DB_* variables and no separate database container needed.
ARG WORDPRESS_IMAGE=wordpress:7.1-php8.3-apache
FROM ${WORDPRESS_IMAGE}

ARG SQLITE_PLUGIN_VERSION=3.0.2

# pdo_sqlite and sqlite3 are already compiled into the official php base
# image (built with --with-pdo-sqlite=/usr --with-sqlite3=/usr), which the
# official SQLite plugin requires — just verify them here. The sqlite3 CLI
# is a small extra for debugging / manual backups in the container.
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends sqlite3; \
	rm -rf /var/lib/apt/lists/*; \
	php -m | grep -Ei 'pdo_sqlite|sqlite3'; \
	php -r '$v = SQLite3::version(); if (version_compare($v["versionString"], "3.37.0", "<")) { fwrite(STDERR, "SQLite too old: " . $v["versionString"] . "\n"); exit(1); } echo "SQLite library: " . $v["versionString"] . PHP_EOL;'

# Bake the official SQLite Database Integration plugin into the seed tree
# (/usr/src/wordpress) so the upstream docker-entrypoint.sh copies it into
# /var/www/html on first start, exactly like any other bundled wp-content.
# Source: https://wordpress.org/plugins/sqlite-database-integration/
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends unzip; \
	cd /tmp; \
	curl -fL -o sqlite-database-integration.zip \
		"https://downloads.wordpress.org/plugin/sqlite-database-integration.${SQLITE_PLUGIN_VERSION}.zip"; \
	mkdir -p /usr/src/wordpress/wp-content/plugins; \
	rm -rf /usr/src/wordpress/wp-content/plugins/sqlite-database-integration; \
	unzip -q sqlite-database-integration.zip -d /usr/src/wordpress/wp-content/plugins; \
	rm sqlite-database-integration.zip; \
	test -f /usr/src/wordpress/wp-content/plugins/sqlite-database-integration/load.php; \
	test -f /usr/src/wordpress/wp-content/plugins/sqlite-database-integration/db.copy; \
	chown -R www-data:www-data /usr/src/wordpress/wp-content/plugins/sqlite-database-integration; \
	mkdir -p /usr/src/wordpress/wp-content/database; \
	chown www-data:www-data /usr/src/wordpress/wp-content/database; \
	chmod 775 /usr/src/wordpress/wp-content/database; \
	apt-get purge -y --auto-remove unzip; \
	rm -rf /var/lib/apt/lists/*

# Wrapper entrypoint: ensures the plugin + db.php drop-in exist in the live
# docroot (covers persisted volumes created from plain WordPress too), then
# chains into the untouched upstream docker-entrypoint.sh.
COPY sqlite-entrypoint.sh /usr/local/bin/sqlite-entrypoint.sh
RUN chmod +x /usr/local/bin/sqlite-entrypoint.sh

ENTRYPOINT ["sqlite-entrypoint.sh"]
CMD ["apache2-foreground"]
