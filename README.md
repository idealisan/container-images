# lxc-images

Container image build configs, centrally managed and published to **GHCR**.

This repository holds the build configuration for all of my useful images. Every
image is built for **both `x86_64` (amd64) and `arm64`** and published as a
multi-architecture manifest to GitHub Container Registry — there are no release
binaries, the registry *is* the distribution channel.

## How it works

- Each image lives in its own directory (e.g. [`ubuntu-24-xrdp/`](ubuntu-24-xrdp)).
- A [GitHub Actions workflow](.github/workflows/build-and-push.yml) runs on every
  **published release / pre-release** and:
  1. builds the LXC/Incus rootfs with [`distrobuilder`](https://github.com/lxc/distrobuilder),
  2. wraps it into an OCI image, building `amd64` and `arm64` separately
     (arm64 is cross-built under `qemu-user-static`),
  3. merges both into a single multi-arch manifest and pushes it to GHCR.
- Images are **only** pushed to GHCR; nothing is attached to the GitHub release.

### Tags

| Event | Tags pushed |
|-------|-------------|
| Stable release `v1.2.3` | `v1.2.3`, `latest` |
| Pre-release `v1.3.0-rc1` | `v1.3.0-rc1`, `prerelease` |

## Image layout

Each image directory contains:

| File | Purpose |
|------|---------|
| `image.yaml` | distrobuilder config — base OS, packages, post-install actions |
| `Dockerfile` | `FROM scratch` + `ADD rootfs.tar.xz /` — wraps the rootfs as an OCI image |
| `entrypoint.sh` | container entrypoint (starts the service, e.g. xrdp) |
| `build.sh` | local helper to build + import the image into Incus/LXC |

## Adding a new image

1. Create a directory `my-image/` with the files above.
2. Copy [`.github/workflows/build-and-push.yml`](.github/workflows/build-and-push.yml)
   to `.github/workflows/my-image.yml` and change `IMAGE_NAME` at the top.
3. Push, cut a release, and the workflow publishes
   `ghcr.io/<owner>/lxc-images/my-image` for both architectures.

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
