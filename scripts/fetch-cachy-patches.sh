#!/usr/bin/env bash
# fetch-cachy-patches.sh — pin CachyOS kernel patches + config for Nethix.
#
# Verified against CachyOS's live repos (kernel 7.3.x era):
#   - Patches: github.com/CachyOS/kernel-patches/tree/<ver>/... (sched/, misc/)
#     where <ver> is the full maj.min (e.g. 7.3)
#   - Config: github.com/CachyOS/linux-cachyos/blob/master/linux-cachyos/config
#
# By default fetches ONLY the patches the stock default kernel uses
# (parsed from the PKGBUILD's scheduler case-block + unconditional source
# entries). To grab everything in a directory instead, set ALL_PATCHES=1.
#
# Usage:
#   ./fetch-cachy-patches.sh <maj.min>            # default (EEVDF) set only
#   CPUSCHED=bore ./fetch-cachy-patches.sh 7.3    # bore-selected set only
#   ALL_PATCHES=1 ./fetch-cachy-patches.sh 7.3    # everything in the dirs
set -euo pipefail

VER=${1:?usage: fetch-cachy-patches.sh <maj.min e.g. 7.3>}
ALL_PATCHES=${ALL_PATCHES:-0}
CPUSCHED=${CPUSCHED:-cachyos}   # cachyos|eevdf|bore|bmq|hardened|rt|rt-bore

RAW=https://raw.githubusercontent.com
DEST=overlay/sys-kernel/nethix-sources/files/${VER}
mkdir -p "$DEST"

say() { printf '\e[1;36m::\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31m::\e[0m %s\n' "$*" >&2; exit 1; }

fetch() {
    say "fetching $1"
    curl -fsSL -o "$2" "$1" || fail "404/unreachable: $1"
}

# 1. CachyOS's actual shipped kernel config
fetch "$RAW/CachyOS/linux-cachyos/master/linux-cachyos/config" \
      "$DEST/config-cachyos"

# 2. Reference PKGBUILD — both for parsing and for audit trail
fetch "$RAW/CachyOS/linux-cachyos/master/linux-cachyos/PKGBUILD" \
      "$DEST/PKGBUILD.reference"

if [[ "$ALL_PATCHES" == 1 ]]; then
    say "ALL_PATCHES=1: grabbing everything under kernel-patches/$VER"
    for SUBDIR in sched misc; do
        LIST_URL="https://api.github.com/repos/CachyOS/kernel-patches/contents/$VER/$SUBDIR"
        PATCHES=$(curl -fsSL "$LIST_URL" | grep -oE '"name": "[^"]+\.patch"' | cut -d'"' -f4 | sort)
        for p in $PATCHES; do
            fetch "$RAW/CachyOS/kernel-patches/$VER/$SUBDIR/$p" "$DEST/$p"
        done
    done
else
    # Parse exactly what the PKGBUILD pulls for this scheduler.
    # Pattern 1: unconditional source+= entries (apply to every variant)
    # Pattern 2: the case-block arm for $CPUSCHED
    say "extracting patches used by scheduler '$CPUSCHED' from PKGBUILD..."
    UNCONDITIONAL=$(grep -oE 'source\+=\("?\$\{?_patchsource\}?/[A-Za-z0-9/_.-]+\.patch' \
                        "$DEST/PKGBUILD.reference" | sed 's/.*patchsource[}\/]//;s/"//' || true)

    # Extract the case arm: from 'CPUSCHED)' to the next ';;'
    CASEARM=$(awk -v sched="$CPUSCHED" '
        $0 ~ sched"\)" {grab=1}
        grab && /source\+\=/ {
            line=$0
            gsub(/.*_patchsource[}\/]/, "", line)
            gsub(/[";].*/, "", line)
            print line
        }
        grab && /;;/ {grab=0}
    ' "$DEST/PKGBUILD.reference")

    PATCHES=$(printf '%s\n%s\n' "$UNCONDITIONAL" "$CASEARM" | grep -E '\.patch$' | sort -u)

    if [[ -z "$PATCHES" ]]; then
        fail "no patches parsed for scheduler '$CPUSCHED' — inspect $DEST/PKGBUILD.reference; layout may have changed"
    fi

    say "patches the default build uses:"
    printf '  %s\n' $PATCHES

    # Try sched/ then misc/ for each path (patches live under one of them)
    for p in $PATCHES; do
        if curl -fsSL -o "$DEST/$(basename "$p")" \
             "$RAW/CachyOS/kernel-patches/$VER/$p" 2>/dev/null; then
            :  # fetched
        elif curl -fsSL -o "$DEST/$(basename "$p")" \
             "$RAW/CachyOS/kernel-patches/$VER/sched/$p" 2>/dev/null; then
            :  # fetched from sched/
        elif curl -fsSL -o "$DEST/$(basename "$p")" \
             "$RAW/CachyOS/kernel-patches/$VER/misc/$p" 2>/dev/null; then
            :  # fetched from misc/
        else
            fail "couldn't locate patch '$p' under kernel-patches/$VER/{,sched/,misc/}"
        fi
    done
fi

say "done. files in $DEST:"
ls -la "$DEST"
say "next: ebuild digest + test apply against linux-$VER tarball before committing"
