#!/bin/sh
# Container entrypoint: bring up the pieces XRDP needs, then run xrdp in
# the foreground so the container stays alive for RDP connections.
set -e

mkdir -p /run/xrdp

# Start D-Bus if it is installed (some XFCE/applets expect a bus).
if command -v dbus-daemon >/dev/null 2>&1; then
  mkdir -p /run/dbus
  dbus-daemon --system --fork 2>/dev/null || true
fi

# sesman brokers the user session; xrdp handles the RDP protocol.
command -v xrdp-sesman >/dev/null 2>&1 && xrdp-sesman 2>/dev/null || true

# -n = do not daemonize (run in foreground).
exec xrdp -n
