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

## Nginx alternative (no image needed)

If you prefer Nginx over Caddy, you don't need this image at all — save the
server block below to `/etc/nginx/conf.d/registry-proxy.conf`, run
`nginx -t && systemctl reload nginx`, and you get the **exact same routing**
as the image's Caddyfile:

| You pull / request                          | Upstream receives                        |
|---------------------------------------------|------------------------------------------|
| `docker pull <domain>/docker/<repo>...`     | Docker Hub `/v2/<repo>/...`              |
| `docker pull <domain>/ghcr/<user>/<repo>...`| `ghcr.io` `/v2/<user>/<repo>/...`        |
| `curl https://<domain>/docker/<repo>/...`   | Docker Hub `/v2/<repo>/...`              |

The only difference is TLS: Nginx does not issue certificates by itself.
Run `certbot --nginx -d registry.example.com` once to obtain them (the
`/.well-known/acme-challenge/` location below is already wired for that), or
point `ssl_certificate` / `ssl_certificate_key` at certs of your own
(Let's Encrypt, ZeroSSL, internal CA, ...).

```nginx
# /etc/nginx/conf.d/registry-proxy.conf
#
# Replaces the registry-proxy image with plain Nginx. The /docker and /ghcr
# markers only select the upstream; they are stripped and the /v2 registry
# API prefix is restored, so the registry always receives /v2/<rest> —
# identical to the Caddyfile.
#
# Change these lines to fit your setup:
#   server_name            -> your PROXY_DOMAIN
#   proxy_pass             -> your PROXY_DOCKER_UPSTREAM  (keep https://)
#                             your PROXY_GHCR_UPSTREAM    (keep https://)
#   proxy_set_header Host  -> the same upstream hostnames

# Port 80: ACME validation + redirect to HTTPS.
server {
    listen 80;
    server_name registry.example.com;

    # Let's Encrypt HTTP-01 challenge (used by certbot).
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    # nginx >= 1.25.1: use `http2 on;`. Older builds: `listen 443 ssl http2;`.
    http2 on;
    server_name registry.example.com;

    # --- TLS (fill in after running `certbot --nginx -d registry.example.com`,
    # or point these at any certs/keys you already have) ---
    ssl_certificate     /etc/letsencrypt/live/registry.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/registry.example.com/privkey.pem;

    # Registry traffic streams large layers and supports chunked uploads.
    client_max_body_size 0;            # allow pushes of any blob size
    proxy_request_buffering off;       # stream uploads instead of spooling
    proxy_http_version 1.1;            # HTTP/1.1 upstream (chunked PUT/PATCH)
    proxy_set_header Connection "";    # enable keep-alive to the upstream
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;
    proxy_ssl_server_name on;          # send SNI to the upstream host

    # Docker Hub — marker /docker, wire form /v2/docker, shorthand /docker.
    location ~ ^/(?:v2/)?docker(/.*)$ {
        rewrite ^/(?:v2/)?docker(/.*)$ /v2$1 break;
        proxy_pass https://registry-1.docker.io;
        proxy_set_header Host registry-1.docker.io;
    }

    # GHCR — marker /ghcr, wire form /v2/ghcr, shorthand /ghcr.
    location ~ ^/(?:v2/)?ghcr(/.*)$ {
        rewrite ^/(?:v2/)?ghcr(/.*)$ /v2$1 break;
        proxy_pass https://ghcr.io;
        proxy_set_header Host ghcr.io;
    }

    # Not a proxied registry request.
    location / {
        return 404;
    }
}
```

Notes:

- The `rewrite ... break` rewrites the request URI to `/v2/<rest>` and
  `proxy_pass` without a trailing path forwards that rewritten URI verbatim,
  keeping the query string — so no `resolver` directive is needed and the
  upstream host is resolved at startup.
- `proxy_set_header Host` points at the real upstream host (same as Caddy's
  `header_up Host`); the token flow still works because upstreams challenge
  scoped to the `/v2/<rest>` path they actually see.
- Registry auth, multi-arch, and `docker/compose`-style namespace escaping
  behave exactly as described under [URLs](#urls) above.