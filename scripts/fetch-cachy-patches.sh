#!/usr/bin/env bash
# fetch-cachy-patches.sh — pin CachyOS kernel assets for Nethix.
#
# VERIFIED against CachyOS/linux-cachyos master PKGBUILD (7.3.6 era):
#   - Kernel source: RELEASE ASSETS of github.com/CachyOS/linux
#     (the actual fork), named  cachyos-<maj.min>-<tagrel>.tar.gz
#     e.g. https://github.com/CachyOS/linux/releases/download/cachyos-7.3-1/cachyos-7.3-1.tar.gz
#   - linux-cachyos repo itself only hosts PKGBUILD + config.
#   - Variant patches: cachyos/kernel-patches/master/<MAJOR>/{sched,misc}
#     keyed by MAJOR only (7/, not 7.3/).
#   - Their "default" scheduler (_cpusched=cachyos) enables SCHED_BORE
#     via scripts/config — plus the fork's baked-in Cachy Sauce.
set -euo pipefail

MAJMIN=${1:?usage: fetch-cachy-patches.sh <maj.min e.g. 7.3>}
CPUSCHED=${CPUSCHED:-cachyos}   # cachyos|eevdf|bore|bmq|hardened|rt|rt-bore
ALL_PATCHES=${ALL_PATCHES:-0}

RAW=https://raw.githubusercontent.com
DEST=overlay/sys-kernel/nethix-sources/files/${MAJMIN}
mkdir -p "$DEST"

say() { printf '\e[1;36m::\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31m!!\e[0m %s\n' "$*" >&2; exit 1; }
fetch() {
    say "fetching $1"
    curl -fsSL -o "$2" "$1" || fail "404/unreachable: $1"
}

# 1. Reference PKGBUILD + config
fetch "$RAW/CachyOS/linux-cachyos/master/linux-cachyos/PKGBUILD" \
      "$DEST/PKGBUILD.reference"
fetch "$RAW/CachyOS/linux-cachyos/master/linux-cachyos/config" \
      "$DEST/config-cachyos"

# 2. Derive the exact source tarball name from the PKGBUILD's own variables
MAJOR=$(grep -E '^_major=' "$DEST/PKGBUILD.reference" | head -n1 | cut -d= -f2)
MINOR=$(grep -E '^_minor=' "$DEST/PKGBUILD.reference" | head -n1 | cut -d= -f2)
TAGREL=$(grep -E '^_tagrel=' "$DEST/PKGBUILD.reference" | head -n1 | cut -d= -f2)
[[ -n "$MAJOR" && -n "$MINOR" && -n "$TAGREL" ]] \
    || fail "couldn't parse _major/_minor/_tagrel from PKGBUILD.reference"

SRCNAME="cachyos-${MAJOR}.${MINOR}-${TAGREL}"
say "derived source release: $SRCNAME (kernel ${MAJOR}.${MINOR})"

# sanity: requested maj.min must match what the PKGBUILD is on
[[ "${MAJOR}.${MINOR}" == "$MAJMIN" ]] \
    || say "WARN: requested $MAJMIN but PKGBUILD is on ${MAJOR}.${MINOR}"

# 3. Download the fork tarball from the CachyOS/linux RELEASES (not tags)
TARBALL_URL="https://github.com/CachyOS/linux/releases/download/${SRCNAME}/${SRCNAME}.tar.gz"
fetch "$TARBALL_URL" "$DEST/${SRCNAME}.tar.gz"

# 4. Variant patches (default build needs none — config flags handle it)
if [[ "$ALL_PATCHES" == 1 ]]; then
    for SUBDIR in sched misc; do
        say "ALL_PATCHES=1: listing kernel-patches/master/$MAJOR/$SUBDIR"
        LIST=$(curl -fsSL "https://api.github.com/repos/cachyos/kernel-patches/contents/$MAJOR/$SUBDIR" \
                | grep -oE '"name": "[^"]+\.patch"' | cut -d'"' -f4 | sort)
        for p in $LIST; do
            fetch "$RAW/cachyos/kernel-patches/master/$MAJOR/$SUBDIR/$p" "$DEST/$p"
        done
    done
    exit 0
fi

case "$CPUSCHED" in
    cachyos|eevdf)
        say "scheduler '$CPUSCHED': no patch files — fork tarball + config flags carry it"
        ;;
    bore|bmq|hardened|rt|rt-bore)
        say "extracting patches for variant '$CPUSCHED'..."
        PATCHES=$(awk -v sched="$CPUSCHED" '
            /^[a-z0-9|]+\)/ { inarm = ($0 ~ sched) }
            inarm && /source\+=/ {
                line = $0
                sub(/.*kernel-patches\/master\/[^\"]*\//, "", line)
                gsub(/[" ;)].*/, "", line)
                print line
            }
        ' "$DEST/PKGBUILD.reference" | sort -u)
        if [[ -z "$PATCHES" ]]; then
            fail "no patches parsed for '$CPUSCHED' — inspect $DEST/PKGBUILD.reference"
        fi
        for p in $PATCHES; do
            # entries are like sched/0001-bore-cachy.patch (path under $MAJOR/)
            fetch "$RAW/cachyos/kernel-patches/master/$MAJOR/$p" "$DEST/$(basename "$p")"
        done
        ;;
    *) fail "unknown CPUSCHED '$CPUSCHED'" ;;
esac

say "done. contents of $DEST:"
ls -la "$DEST"
say "commit these; nethix-sources ebuild should SRC_URI the committed tarball + use config-cachyos."
