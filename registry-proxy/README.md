# registry-proxy

A Caddy-based reverse proxy that exposes **Docker Hub** and **GHCR** (GitHub
Container Registry) under a single HTTPS domain. The domain is followed by a
lowercase path marker that selects the upstream registry; the marker is
**never forwarded** — only the rest of the path reaches the registry. Caddy
terminates TLS automatically (Let's Encrypt).

## URLs

| You pull / request                                        | Upstream receives                                  |
|-----------------------------------------------------------|----------------------------------------------------|
| `docker pull <domain>/docker/<repo>:<tag>`                | Docker Hub `/v2/<repo>/manifests/<tag>`            |
| `docker pull <domain>/ghcr/<user>/<repo>:<tag>`           | `ghcr.io` `/v2/<user>/<repo>/manifests/<tag>`      |
| `curl https://<domain>/docker/v2/<repo>/tags/list`        | Docker Hub `/v2/<repo>/tags/list`                  |
| `curl https://<domain>/docker/<repo>/tags/list`           | Docker Hub `/v2/<repo>/tags/list` (shorthand)      |

In `docker pull <domain>/docker/...` the `/v2/` API prefix is added by the
Docker client itself, so nothing extra to type. Worked examples (same layout
as Huawei SWR's `.../docker.io/<repo>` proxy):

```sh
docker pull registry.example.com/docker/library/nginx:latest
docker pull registry.example.com/ghcr/idealisan/container-images/wordpress-sqlite:latest
```

> Note: Docker Hub owns the `docker` namespace. To reach Hub images that are
> themselves named `docker/...` (e.g. `docker/compose`), express the namespace
> twice: `docker pull registry.example.com/docker/docker/compose:latest`.

## Run

```sh
docker run -d --name registry-proxy -p 80:80 -p 443:443 \
  -v registry-proxy-data:/data \
  -e PROXY_DOMAIN=registry.example.com \
  ghcr.io/idealisan/container-images/registry-proxy:latest
```

Then all the pulls above work. Or with Docker Compose (reference file in this
directory):

```sh
docker compose up -d   # uses compose.yaml: ports 80/443, volumes proxy_data + proxy_config
```

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `PROXY_DOMAIN` | *(required)* | Public domain of the proxy; site address + Let's Encrypt certificate |
| `PROXY_DOCKER_UPSTREAM` | `registry-1.docker.io` | Upstream for `/docker/...` (https) |
| `PROXY_GHCR_UPSTREAM` | `ghcr.io` | Upstream for `/ghcr/...` (https) |

Point an A/AAAA record for `PROXY_DOMAIN` at this host and keep ports
`80` + `443` open (port 80 is needed for ACME HTTP-01 validation). Mount a
volume at `/data` so the certificate survives restarts; `/config` (Caddy's
config autosave) can be mounted too.

## How it works

- `Dockerfile` (`ARG CADDY_IMAGE`, default `caddy:2`): official Caddy image,
  our Caddyfile replaces the bundled one; multi-arch comes from upstream.
- `Caddyfile`: a site block on `{$PROXY_DOMAIN}`. For each marker
  (`/docker`, `/ghcr`) a matcher accepts both the Docker client wire form
  (`/v2/<marker>/...`) and a `/v2`-less shorthand; `uri path_regexp` drops the
  marker and restores the `/v2` registry API prefix before forwarding.
  `header_up Host` is set to the upstream host.
- Registry auth just works: upstreams answer with `WWW-Authenticate`
  challenges scoped to the path *they* see (after the marker is stripped),
  clients fetch a token and retry, and the proxy relays everything untouched.

## Versions

| Component | Default |
|-----------|---------|
| Base image | `caddy:2` (bump via `CADDY_IMAGE`) |