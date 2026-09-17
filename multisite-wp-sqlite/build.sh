#!/bin/sh
# Local helper: build the multisite-wp-sqlite Docker image.
#
# Usage:
#   ./build.sh                              # build :latest locally
#   ./build.sh my-tag                       # build with a custom tag
#   WORDPRESS_IMAGE=wordpress:apache ./build.sh
#   SQLITE_PLUGIN_VERSION=3.0.2 ./build.sh
#
# Run (headless, network ready immediately):
#   docker run -d -p 8080:80 \
#     -v wp-ms-sqlite:/var/www/html -v wp-ms-sqlite-db:/var/www/sqlite \
#     -e WORDPRESS_URL=http://localhost:8080 \
#     -e WORDPRESS_ADMIN_USER=admin -e WORDPRESS_ADMIN_PASSWORD=secret \
#     -e WORDPRESS_ADMIN_EMAIL=admin@example.com \
#     multisite-wp-sqlite:latest
#
# Or omit the credentials to finish the install wizard, then restart once.
set -eu

IMAGE_NAME="${IMAGE_NAME:-multisite-wp-sqlite}"
TAG="${1:-latest}"

docker build \
	${WORDPRESS_IMAGE:+--build-arg WORDPRESS_IMAGE="$WORDPRESS_IMAGE"} \
	${SQLITE_PLUGIN_VERSION:+--build-arg SQLITE_PLUGIN_VERSION="$SQLITE_PLUGIN_VERSION"} \
	-t "$IMAGE_NAME:$TAG" .

echo
echo "Built $IMAGE_NAME:$TAG"
echo "Run: docker run -d -p 8080:80 -v wp-ms-sqlite:/var/www/html -v wp-ms-sqlite-db:/var/www/sqlite $IMAGE_NAME:$TAG"
