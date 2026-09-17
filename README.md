# container-images

Container image build configs, centrally managed and published to **GHCR**.

This repository holds the build configuration for all of my useful images. Every
image is built for **both `x86_64` (amd64) and `arm64`** and published as a
multi-architecture manifest to GitHub Container Registry — there are no release
binaries, the registry *is* the distribution channel.

## How it works

- Each image lives in its own directory (e.g. [`ubuntu-24-xrdp/`](ubuntu-24-xrdp)).
- A single [GitHub Actions workflow](.github/workflows/build-and-push.yml) runs on
  every **push to `main`** and **auto-discovers** all image
  directories (any dir containing an `image.yaml` and/or a `Dockerfile`),
  then for each one:
  1. for distrobuilder images: builds the LXC/Incus rootfs with
     [`distrobuilder`](https://github.com/lxc/distrobuilder), then wraps it
     into an OCI image; for plain Docker images (e.g. `wordpress-sqlite`,
     based on an upstream image): builds the `Dockerfile` directly —
     in both cases `amd64` and `arm64` are built separately
     (arm64 is cross-built under `qemu-user-static`),
  2. merges both into a single multi-arch manifest and pushes it to GHCR.
- Images are **only** pushed to GHCR; no GitHub release is created.

There are two kinds of images:

| Type | Marker | Example |
|------|--------|---------|
| distrobuilder / LXC-Incus | `image.yaml` + `FROM scratch` Dockerfile | `ubuntu-24-xrdp` |
| plain Docker (upstream base) | `Dockerfile` only (`FROM <upstream>`) | `wordpress-sqlite` |

### Tags

| Event | Tags pushed |
|-------|-------------|
| Push to `main` | `latest`, `sha-<commit>` |

## Image layout

distrobuilder images contain:

| File | Purpose |
|------|---------|
| `image.yaml` | distrobuilder config — base OS, packages, post-install actions |
| `Dockerfile` | `FROM scratch` + `ADD rootfs.tar.xz /` — wraps the rootfs as an OCI image |
| `entrypoint.sh` | container entrypoint (starts the service, e.g. xrdp) |
| `build.sh` | local helper to build + import the image into Incus/LXC |

Plain Docker images (upstream base) contain:

| File | Purpose |
|------|---------|
| `Dockerfile` | `FROM <upstream>` + customizations (see image README) |
| `*-entrypoint.sh` | wrapper ensuring local setup, then chains to upstream entrypoint |
| `build.sh` | local helper (`docker build -t … .`) |
| `README.md` | usage docs for the image |

## Adding a new image

1. Create a directory `my-image/` containing a `Dockerfile` (and an
   `image.yaml` too if it is a distrobuilder/LXC image).
2. That's it — the workflow **auto-discovers** the new directory on the next
   push to `main` and publishes `ghcr.io/<owner>/container-images/my-image`
   for both architectures. No workflow changes needed.

## Consuming an image

Pull and run with Docker:

```sh
docker pull ghcr.io/idealisan/container-images/ubuntu-24-xrdp:latest
docker run -p 3389:3389 ghcr.io/idealisan/container-images/ubuntu-24-xrdp:latest
```

```sh
docker pull ghcr.io/idealisan/container-images/wordpress-sqlite:latest
docker run -d -p 8080:80 -v wp-sqlite:/var/www/html \
  ghcr.io/idealisan/container-images/wordpress-sqlite:latest
```

```sh
docker pull ghcr.io/idealisan/container-images/registry-proxy:latest
docker run -d -p 80:80 -p 443:443 -v registry-proxy-data:/data \
  -e PROXY_DOMAIN=registry.example.com \
  ghcr.io/idealisan/container-images/registry-proxy:latest
# then: docker pull registry.example.com/docker/library/nginx:latest
```

Or launch distrobuilder images directly with Incus
(OCI support runs the distro init instead):

```sh
incus launch ghcr.io/idealisan/container-images/ubuntu-24-xrdp:latest mycontainer
```

## Images

| Image | Description |
|-------|-------------|
| [`ubuntu-24-xrdp`](ubuntu-24-xrdp) | Ubuntu 24.04 (Noble) + XRDP + XFCE desktop, for RDP access |
| [`wordpress-sqlite`](wordpress-sqlite) | Official WordPress + official SQLite Database Integration plugin, no MySQL needed |
| [`multisite-wp-sqlite`](multisite-wp-sqlite) | Same as `wordpress-sqlite`, but always a WordPress multisite network (headless install or wizard + one restart) |
| [`registry-proxy`](registry-proxy) | Caddy reverse proxy exposing Docker Hub `/docker/...` and GHCR `/ghcr/...` under one HTTPS domain (Let's Encrypt) |
