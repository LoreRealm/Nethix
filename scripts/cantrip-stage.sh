#!/usr/bin/env bash
# cantrip-stage — stage everything the exec backend expects in /var/lib/nethix.
# Run once from the live ISO (or a repo checkout) before starting the install.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST=/var/lib/nethix
[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }

mkdir -p "$DEST"

# tuned make.conf profiles
install -m0644 "$SRC/profiles.d/makeconf.amd64-v3" "$DEST/makeconf.amd64-v3"
install -m0644 "$SRC/profiles.d/makeconf.amd64-v4" "$DEST/makeconf.amd64-v4"
# fall back alias for v2 hardware
install -m0644 "$SRC/profiles.d/makeconf.amd64-v3" "$DEST/makeconf.x86-64"

# overlay (self-contained: repo IS the overlay + tooling)
rm -rf "$DEST/overlay"
mkdir -p "$DEST/overlay"
cp -r "$SRC/overlay/." "$DEST/overlay/"

# systemd flag for the stage3 pick
echo "systemd" > "$DEST/stage3-flavor"

echo "staged: makeconf v3/v4, overlay, flavor -> $DEST"
