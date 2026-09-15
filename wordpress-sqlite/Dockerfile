# WordPress + SQLite (no MySQL needed).
#
# Based on the official WordPress Docker image, everything stays identical
# except the database layer: the official
# "SQLite Database Integration" plugin (WordPress Team, distributed on
# wordpress.org, no third-party feature plugins) is baked in and wired up
# as the wp-content/db.php drop-in. The site database lives in a local
# SQLite file under /var/www/sqlite — outside the web-accessible docroot,
# so the database can never be downloaded over HTTP — instead of a MySQL
# server. Upload limits are raised to 50 MB per file.
#
# Build args:
#   WORDPRESS_IMAGE        base official image (default pins WP 7.1 + PHP 8.3)
#   SQLITE_PLUGIN_VERSION  official plugin version from wordpress.org
#
# Run:
#   docker run -d -p 8080:80 \
#     -v wp-sqlite:/var/www/html \
#     -v wp-sqlite-db:/var/www/sqlite \
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
# docroot (covers persisted volumes created from plain WordPress too), then
# chains into the untouched upstream docker-entrypoint.sh.
COPY sqlite-entrypoint.sh /usr/local/bin/sqlite-entrypoint.sh
RUN chmod +x /usr/local/bin/sqlite-entrypoint.sh

ENTRYPOINT ["sqlite-entrypoint.sh"]
CMD ["apache2-foreground"]
