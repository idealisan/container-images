# Wraps the distrobuilder rootfs tarball into an OCI image for GHCR.
# The rootfs.tar.xz is produced by `distrobuilder build-incus image.yaml`.
FROM scratch
ADD rootfs.tar.xz /
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
