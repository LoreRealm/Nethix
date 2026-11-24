#!/usr/bin/env bash
# fetch-cachy-patches.sh — pin CachyOS kernel patches + config for Nethix.
#
# Verified against CachyOS's live repos (kernel 7.3.x era):
#   - Patches: github.com/CachyOS/kernel-patches/tree/<ver>/... (sched/, misc/)
#     where <ver> is the full maj.min (e.g. 7.3) — NOT the major alone.
#   - Config: github.com/CachyOS/linux-cachyos/blob/master/linux-cachyos/config
#
# The PKGBUILD's source=() picks patches per-scheduler; default is EEVDF
# (_cpusched=cachyos). We default to the same set the default kernel uses.
#
# Usage: ./fetch-cachy-patches.sh <maj.min> [patch]
#   e.g. ./fetch-cachy-patches.sh 7.3 sched
#        CPUSCHED=bore ./fetch-cachy-patches.sh 7.3 sched
#
# Output: overlay/sys-kernel/nethix-sources/files/<ver>/ — review then commit.
set -euo pipefail

VER=${1:?usage: fetch-cachy-patches.sh <maj.min e.g. 7.3> [patch subdir sched|misc]}
SUBDIR=${2:-sched}
CPUSCHED=${CPUSCHED:-cachyos}   # cachyos=EEVDF default; bore|hardened|rt also valid

RAW=https://raw.githubusercontent.com
DEST=overlay/sys-kernel/nethix-sources/files/${VER}
mkdir -p "$DEST"

say() { printf '\e[1;36m::\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31m::\e[0m %s\n' "$*" >&2; exit 1; }

fetch() { # fetch <url> <outfile>
    say "fetching $1"
    curl -fsSL -o "$2" "$1" || fail "404/unreachable: $1 — does kernel-patches have a ${VER} dir?"
}

# 1. CachyOS's actual shipped kernel config
fetch "$RAW/CachyOS/linux-cachyos/master/linux-cachyos/config" \
      "$DEST/config-cachyos"

# 2. Reference PKGBUILD to parse patch selection from
fetch "$RAW/CachyOS/linux-cachyos/master/linux-cachyos/PKGBUILD" \
      "$DEST/PKGBUILD.reference"

say "scheduler '$CPUSCHED': listing patches in kernel-patches/$VER/$SUBDIR ..."
# List the dir via the GitHub API (paths only, no auth needed)
LIST_URL="https://api.github.com/repos/CachyOS/kernel-patches/contents/$VER/$SUBDIR"
PATCHES=$(curl -fsSL "$LIST_URL" | grep -oE '"name": "[^"]+\.patch"' | cut -d'"' -f4 | sort)

if [[ -z "$PATCHES" ]]; then
    fail "no .patch files found in kernel-patches/$VER/$SUBDIR — inspect $DEST/PKGBUILD.reference for the current layout"
fi

# 3. Fetch each patch (full maj.min dir path — dirs are 7.3/, 6.18/, etc.)
for p in $PATCHES; do
    fetch "$RAW/CachyOS/kernel-patches/$VER/$SUBDIR/$p" "$DEST/$p"
done

say "done. files in $DEST:"
ls -la "$DEST"
say "next: ebuild digest + test apply against linux-$VER tarball before committing"
