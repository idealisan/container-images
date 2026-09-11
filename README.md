# lxc-images

Container image build configs, centrally managed and published to **GHCR**.

This repository holds the build configuration for all of my useful images. Every
image is built for **both `x86_64` (amd64) and `arm64`** and published as a
multi-architecture manifest to GitHub Container Registry — there are no release
binaries, the registry *is* the distribution channel.

## How it works

- Each image lives in its own directory (e.g. [`ubuntu-24-xrdp/`](ubuntu-24-xrdp)).
- A single [GitHub Actions workflow](.github/workflows/build-and-push.yml) runs on
  every **push to `main`** and **auto-discovers** all image
  directories (any dir containing an `image.yaml`), then for each one:
  1. builds the LXC/Incus rootfs with [`distrobuilder`](https://github.com/lxc/distrobuilder),
  2. wraps it into an OCI image, building `amd64` and `arm64` separately
     (arm64 is cross-built under `qemu-user-static`),
  3. merges both into a single multi-arch manifest and pushes it to GHCR.
- Images are **only** pushed to GHCR; no GitHub release is created.

### Tags

| Event | Tags pushed |
|-------|-------------|
| Push to `main` | `latest`, `sha-<commit>` |

## Image layout

Each image directory contains:

| File | Purpose |
|------|---------|
| `image.yaml` | distrobuilder config — base OS, packages, post-install actions |
| `Dockerfile` | `FROM scratch` + `ADD rootfs.tar.xz /` — wraps the rootfs as an OCI image |
| `entrypoint.sh` | container entrypoint (starts the service, e.g. xrdp) |
| `build.sh` | local helper to build + import the image into Incus/LXC |

## Adding a new image

1. Create a directory `my-image/` containing an `image.yaml` and the other files
   listed in [Image layout](#image-layout).
2. That's it — the workflow **auto-discovers** the new directory on the next
   push to `main` and publishes `ghcr.io/<owner>/lxc-images/my-image` for both
   architectures. No workflow changes needed.

## Consuming an image

Pull and run with Docker (the entrypoint starts the service):

```sh
docker pull ghcr.io/idealisan/lxc-images/ubuntu-24-xrdp:latest
docker run -p 3389:3389 ghcr.io/idealisan/lxc-images/ubuntu-24-xrdp:latest
```

Or launch directly with Incus (OCI support runs the distro init instead):

```sh
incus launch ghcr.io/idealisan/lxc-images/ubuntu-24-xrdp:latest mycontainer
```

## Images

| Image | Description |
|-------|-------------|
| [`ubuntu-24-xrdp`](ubuntu-24-xrdp) | Ubuntu 24.04 (Noble) + XRDP + XFCE desktop, for RDP access |
