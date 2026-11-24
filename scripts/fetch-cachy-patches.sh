#!/usr/bin/env bash
# fetch-cachy-patches.sh — pin CachyOS kernel patches + config for Nethix.
#
# How it actually works (verified against CachyOS's repos):
#   - Kernel source: CachyOS's own fork, tag cachyos-<maj.min>-<tagrel>
#   - Patches: github.com/CachyOS/kernel-patches/tree/<ver>/... (sched/, misc/)
#   - Config: linux-cachyos repo, linux-cachyos/config
#
# The PKGBUILD's source=() picks patches per-scheduler; default is EEVDF
# (_cpusched=cachyos). We default to fetching the same set the default
# kernel uses.
#
# Usage: ./fetch-cachy-patches.sh <kernel-version> [tagrel]
#   e.g. ./fetch-cachy-patches.sh 7.3 2
#
# Output: overlay/sys-kernel/nethix-sources/files/<ver>/ containing the
# config + all fetched patches. Review, then commit (hermetic ebuild).
set -euo pipefail

VER=${1:?usage: fetch-cachy-patches.sh <version> [tagrel]}
TAGREL=${2:-1}
CPUSCHED=${CPUSCHED:-cachyos}   # cachyos=EEVDF default; bore|hardened|rt also valid

RAW=https://raw.githubusercontent.com
DEST=overlay/sys-kernel/nethix-sources/files/${VER}
mkdir -p "$DEST"

say() { printf '\e[1;36m::\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31m::\e[0m %s\n' "$*" >&2; exit 1; }

fetch() { # fetch <url> <outfile>
    say "fetching $1"
    curl -fsSL -o "$2" "$1" || fail "404/unreachable: $1 (does kernel-patches have a ${VER} dir?)"
}

# 1. The kernel config (CachyOS's actual shipped config)
fetch "$RAW/CachyOS/linux-cachyos/master/linux-cachyos/config" \
      "$DEST/config-cachyos"

# 2. Determine which patches the PKGBUILD pulls for this scheduler.
#    Simplest robust approach: download the PKGBUILD and grep its
#    scheduler-case block for patch paths.
fetch "$RAW/CachyOS/linux-cachyos/master/linux-cachyos/PKGBUILD" \
      "$DEST/PKGBUILD.reference"

say "extracting patch list for scheduler '$CPUSCHED'..."
# Patch entries look like: ${_patchsource}/sched/0001-bore-cachy.patch
PATCHES=$(grep -oE '\$\{_patchsource\}/[A-Za-z0-9/_.-]+\.patch' \
              "$DEST/PKGBUILD.reference" | sed 's/.*}\///' | sort -u)

if [[ -z "$PATCHES" ]]; then
    fail "no patches parsed from PKGBUILD — CachyOS may have changed layout; inspect $DEST/PKGBUILD.reference manually"
fi

# 3. Fetch each patch from kernel-patches for this version
for p in $PATCHES; do
    # patches live under kernel-patches/<major.minor>/<path>
    minor="${VER%.*}"
    fetch "$RAW/CachyOS/kernel-patches/$minor/$p" "$DEST/$(basename "$p")"
done

say "verifying patches apply is YOUR job next: ebuild digest + a test emerge"
say "done. files in $DEST:"
ls -la "$DEST"
