# Caddy-based reverse proxy exposing the Docker Hub and GHCR registry APIs
# under a single HTTPS domain, distinguished by a lowercase path marker:
#
#   https://<domain>/docker/<repo>...   -> registry-1.docker.io  (Docker Hub)
#   https://<domain>/ghcr/<repo>...     -> ghcr.io               (GitHub Container Registry)
#
# The marker segment (/docker, /ghcr) only selects the upstream; it is never
# forwarded — the rest of the path reaches the registry unchanged. Caddy
# terminates TLS automatically via Let's Encrypt.
#
# Build args:
#   CADDY_IMAGE  base official Caddy image (default caddy:2)
#
# Run:
#   docker run -d -p 80:80 -p 443:443 \
#     -v registry-proxy-data:/data \
#     -e PROXY_DOMAIN=registry.example.com \
#     ghcr.io/idealisan/container-images/registry-proxy:latest
ARG CADDY_IMAGE=caddy:2
FROM ${CADDY_IMAGE}

# Overwrite the bundled default Caddyfile with the registry reverse-proxy
# config. Everything else (entrypoint, EXPOSE 80/443, /data + /config
# volumes) comes unchanged from the official image.
COPY Caddyfile /etc/caddy/Caddyfile