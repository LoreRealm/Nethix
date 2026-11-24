#!/usr/bin/env bash
# fetch-cachy-patches.sh — pin and download the actual CachyOS kernel patchset
# for a given kernel version. Run from repo root; writes into overlay/.
set -euo pipefail

# Upstream tag pattern: linux-cachyos/vX.Y.Z-* ; adjust MAJOR.MINOR.PATCH as needed
KVER="${1:-6.12.0}"
BASE="https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/linux-cachyos"

mkdir -p "overlay/sys-kernel/nethix-sources/files/${KVER}"
curl -fL "${BASE}/patches/${KVER}/0001-bore.patch" \
     -o "overlay/sys-kernel/nethix-sources/files/${KVER}/0001-bore.patch"
curl -fL "${BASE}/patches/${KVER}/0002-cachy-default-config.patch" \
     -o "overlay/sys-kernel/nethix-sources/files/${KVER}/0002-cachy-default-config.patch" || \
     echo "WARN: config patch may not exist for ${KVER}, skipping"

echo "Patches fetched into overlay/sys-kernel/nethix-sources/files/${KVER}/"
echo "Now update the ebuild SRC_URI to reference files/ paths, then ebuild digest."
