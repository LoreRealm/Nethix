#!/usr/bin/env bash
# bootstrap-portage.sh — build the nethix overlay into a live portage tree.
# Intended for the live ISO / fresh stage3 chroot.
set -euo pipefail

CONF="/etc/portage/repos.conf/nethix.conf"
OVERLAY_URL="https://github.com/LoreRealm/nethix"  # FIXME: change to a raw overlay-only URL once we split overlay/ out
OVERLAY_DEST="/var/db/repos/nethix"

[[ -d "$OVERLAY_DEST" ]] || git clone --depth 1 "$OVERLAY_URL" "$OVERLAY_DEST"

mkdir -p /etc/portage/repos.conf
cat > "$CONF" <<EOF
[nethix]
location = $OVERLAY_DEST
priority = 50
masters = gentoo
EOF

# Tuned make.conf
ARCH=$(uname -m)-linux-gnu
CPU_LEVEL=$(grep -o 'avx512' /proc/cpuinfo | head -n1 >/dev/null && echo v4 || (grep -o 'avx2' /proc/cpuinfo | head -n1 >/dev/null && echo v3 || echo x86-64))
cp "${OVERLAY_DEST}/profiles.d/makeconf.amd64-${CPU_LEVEL}" /etc/portage/make.conf || \
    cp "${OVERLAY_DEST}/profiles.d/makeconf.amd64-v3" /etc/portage/make.conf

echo "Nethix overlay wired up at priority 50. Run emerge --sync gentoo next."
