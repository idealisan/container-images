#!/bin/sh
# Local helper: build the registry-proxy Docker image.
#
# Usage:
#   ./build.sh                              # build :latest locally
#   ./build.sh my-tag                       # build with a custom tag
#   CADDY_IMAGE=caddy:2 ./build.sh
#
# Run:
#   docker run -d -p 80:80 -p 443:443 \
#     -v registry-proxy-data:/data \
#     -e PROXY_DOMAIN=registry.example.com \
#     registry-proxy:latest
set -eu

IMAGE_NAME="${IMAGE_NAME:-registry-proxy}"
TAG="${1:-latest}"

docker build \
	${CADDY_IMAGE:+--build-arg CADDY_IMAGE="$CADDY_IMAGE"} \
	-t "$IMAGE_NAME:$TAG" .

echo
echo "Built $IMAGE_NAME:$TAG"
echo "Run: docker run -d -p 80:80 -p 443:443"
echo "  -v registry-proxy-data:/data -e PROXY_DOMAIN=registry.example.com $IMAGE_NAME:$TAG"