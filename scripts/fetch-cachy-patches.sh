#!/usr/bin/env bash
# fetch-cachy-patches.sh — pin CachyOS kernel assets for Nethix.
#
# Reality check (verified against their live repos, 7.3 era):
#   - The DEFAULT cachyos kernel (EEVDF + Cachy Sauce) is built from
#     CachyOS's OWN FORK of the kernel (tags like cachyos-7.3-2), not from
#     mainline + patch files. So for CPUSCHED=cachyos|eevdf we fetch the
#     fork tarball + config, and expect ZERO patch files.
#   - kernel-patches/<ver>/{sched,misc} only serves ALTERNATIVE variants
#     (bore, bmq, hardened, rt, rt-bore) layered on top of the fork.
#
# Usage:
#   ./fetch-cachy-patches.sh 7.3                 # default (fork + config)
#   CPUSCHED=bore ./fetch-cachy-patches.sh 7.3  # fork + config + bore patches
#   ALL_PATCHES=1 ./fetch-cachy-patches.sh 7.3  # ignore parser, grab all
set -euo pipefail

VER=${1:?usage: fetch-cachy-patches.sh <maj.min e.g. 7.3>}
CPUSCHED=${CPUSCHED:-cachyos}   # cachyos|eevdf|bore|bmq|hardened|rt|rt-bore
ALL_PATCHES=${ALL_PATCHES:-0}
TAGREL=${TAGREL:-2}              # bumped per CachyOS release; check PKGBUILD _tagrel

RAW=https://raw.githubusercontent.com
DEST=overlay/sys-kernel/nethix-sources/files/${VER}
mkdir -p "$DEST"

say() { printf '\e[1;36m::\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31m!!\e[0m %s\n' "$*" >&2; exit 1; }

fetch() {
    say "fetching $1"
    curl -fsSL -o "$2" "$1" || fail "404/unreachable: $1"
}

# 1. Reference PKGBUILD + their actual config
fetch "$RAW/CachyOS/linux-cachyos/master/linux-cachyos/PKGBUILD" \
      "$DEST/PKGBUILD.reference"
fetch "$RAW/CachyOS/linux-cachyos/master/linux-cachyos/config" \
      "$DEST/config-cachyos"

# Track the real _tagrel from the PKGBUILD so the fork tarball is right
REAL_TAGREL=$(grep -E '^_tagrel=' "$DEST/PKGBUILD.reference" | head -n1 | cut -d= -f2)
[[ -n "${REAL_TAGREL:-}" ]] && TAGREL="$REAL_TAGREL"

# 2. The fork tarball (default kernels build from this)
TAG="cachyos-${VER}-${TAGREL}"
TARBALL="${TAG}.tar.gz"
say "downloading CachyOS kernel fork: $TARBALL"
curl -fsSL -o "$DEST/$TARBALL" \
    "https://github.com/CachyOS/linux-cachyos/archive/refs/tags/${TAG}.tar.gz" \
    || fail "couldn't fetch fork tag $TAG — check _tagrel in $DEST/PKGBUILD.reference"

# 3. Variant patches (default schedulers use none — that's correct)
if [[ "$ALL_PATCHES" == 1 ]]; then
    for SUBDIR in sched misc; do
        say "ALL_PATCHES=1: listing kernel-patches/$VER/$SUBDIR"
        LIST=$(curl -fsSL "https://api.github.com/repos/CachyOS/kernel-patches/contents/$VER/$SUBDIR" \
                | grep -oE '"name": "[^"]+\.patch"' | cut -d'"' -f4 | sort)
        for p in $LIST; do
            fetch "$RAW/CachyOS/kernel-patches/$VER/$SUBDIR/$p" "$DEST/$p"
        done
    done
    exit 0
fi

case "$CPUSCHED" in
    cachyos|eevdf)
        say "scheduler '$CPUSCHED' uses the fork kernel as-is: no extra patch files"
        say "(EEVDF is mainline; Cachy Sauce is baked into the fork tarball)"
        ;;
    *)
        say "extracting patches for scheduler variant '$CPUSCHED'..."
        # Walk the case block strictly: from the arm header to its ;;
        # Handles multi-pattern arms like 'bore|rt-bore|hardened)'.
        PATCHES=$(awk -v sched="$CPUSCHED" '
            /^[a-z0-9|-]+\)/ { inarm = ($0 ~ (sched "[|)]") || $0 ~ ("\\|" sched "\\)")) }
            inarm && /source\+=/ {
                line = $0
                sub(/.*_patchsource[}\]\)]?\//, "", line)
                gsub(/[" ;].*/, "", line)
                print line
            }
        ' "$DEST/PKGBUILD.reference" | sort -u)

        if [[ -z "$PATCHES" ]]; then
            fail "no patches parsed for '$CPUSCHED' — inspect $DEST/PKGBUILD.reference"
        fi
        for p in $PATCHES; do
            # entries look like sched/0001-bore-cachy.patch — path already included
            if curl -fsSL -o "$DEST/$(basename "$p")" \
                 "$RAW/CachyOS/kernel-patches/$VER/$p" 2>/dev/null; then
                :
            else
                fail "couldn't locate '$p' under kernel-patches/$VER/"
            fi
        done
        ;;
esac

say "done. contents of $DEST:"
ls -la "$DEST"
say "commit these to make nethix-sources hermetic."
say "NOTE: nethix-sources ebuild must now point at the fork tarball (${TARBALL}), not mainline + patches."
