#!/bin/sh
# Local helper: build the wordpress-sqlite Docker image.
#
# Usage:
#   ./build.sh                              # build :latest locally
#   ./build.sh my-tag                       # build with a custom tag
#   WORDPRESS_IMAGE=wordpress:apache ./build.sh
#   SQLITE_PLUGIN_VERSION=3.0.2 ./build.sh
#
# Run:
#   docker run -d -p 8080:80 -v wp-sqlite:/var/www/html wordpress-sqlite:latest
set -eu

IMAGE_NAME="${IMAGE_NAME:-wordpress-sqlite}"
TAG="${1:-latest}"

docker build \
	${WORDPRESS_IMAGE:+--build-arg WORDPRESS_IMAGE="$WORDPRESS_IMAGE"} \
	${SQLITE_PLUGIN_VERSION:+--build-arg SQLITE_PLUGIN_VERSION="$SQLITE_PLUGIN_VERSION"} \
	-t "$IMAGE_NAME:$TAG" .

echo
echo "Built $IMAGE_NAME:$TAG"
echo "Run: docker run -d -p 8080:80 -v wp-sqlite:/var/www/html $IMAGE_NAME:$TAG"
