#!/bin/sh
# Build and import the Ubuntu 24.04 + XRDP image into Incus/LXC.
#
# Requirements:
#   - distrobuilder  (https://github.com/lxc/distrobuilder)
#   - incus or lxc   (the CLI used to import the resulting image)
#
# Usage:
#   ./build.sh            # build + import into Incus
#   BUILDER=lxc ./build.sh   # import into LXD instead of Incus

set -eu

IMAGE_NAME="ubuntu-24-xrdp"
BUILDER="${BUILDER:-incus}"

command -v distrobuilder >/dev/null 2>&1 || {
  echo "error: 'distrobuilder' not found. Install it from https://github.com/lxc/distrobuilder"
  exit 1
}

if [ "$BUILDER" = "lxc" ]; then
  command -v lxc >/dev/null 2>&1 || { echo "error: 'lxc' not found"; exit 1; }
  distrobuilder build-lxd image.yaml
  lxc image import meta.tar.xz rootfs.tar.xz --alias "$IMAGE_NAME"
  echo "Imported image '$IMAGE_NAME' into LXD."
else
  command -v incus >/dev/null 2>&1 || { echo "error: 'incus' not found"; exit 1; }
  distrobuilder build-incus image.yaml
  incus image import meta.tar.xz rootfs.tar.xz --alias "$IMAGE_NAME"
  echo "Imported image '$IMAGE_NAME' into Incus."
fi

echo
echo "Next steps:"
echo "  incus launch $IMAGE_NAME desktop"
echo "  incus config device add desktop rdp proxy listen=tcp:0.0.0.0:3389 connect=tcp:127.0.0.1:3389"
echo "  # RDP to <host-ip>:3389  (user: ubuntu / ubuntu — change the password!)"
