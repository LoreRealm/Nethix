#!/usr/bin/env bash
# harvest-binhost.sh — snapshot EVERY installed package into binhost/ .tbz2s.
#
# The key insight: no recompiles. `quickpkg --include-unmodified` packs
# the FILES ALREADY INSTALLED on this system into .tbz2 packages directly
# from the live filesystem (via the vdb). Zero compile time — a full
# 400+ package desktop system harvests in ~5-15 minutes.
#
# Output: <repo>/binhost/ with a Packages index — directly servable as a
# PORTAGE_BINHOST mirror (Cloudflare R2 bucket, nginx, any static host).
#
# Requirements: root (quickpkg needs it), ~2x installed-package-size disk
# free in <repo>/binhost.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BINHOST="$REPO_ROOT/binhost"

[[ $EUID -eq 0 ]] || { printf '!! run as root (quickpkg needs it)\n' >&2; exit 1; }

printf ':: harvesting every installed package into binhost/...\n'
mkdir -p "$BINHOST"

# --include-unmodified: pack packages even when the installed files match
# the distfiles checksums (i.e. ALL of them — we want the whole system).
quickpkg --include-unmodified=y --overwrite=y "$(qlist -I -C)" 2>&1 | tail -5

# FEATURES=buildpkg in the default config drops .tbz2s into
# /var/cache/binpkgs; harvest from wherever quickpkg landed them.
# (PKGDIR default is /var/cache/binpkgs on modern portage.)
PKGDIR=$(portageq envvar PKGDIR)
mkdir -p "$PKGDIR"

say_count() { find "$BINHOST" -name '*.tbz2' | wc -l; }

printf ':: refreshing binhost copy from %s...\n' "$PKGDIR"
mkdir -p "$BINHOST"
rsync -a --delete "$PKGDIR/" "$BINHOST/"

# Refresh the Packages index — REQUIRED for PORTAGE_BINHOST consumers.
# emaint regenerates it from the .tbz2s present.
emaint binhost --fix 2>/dev/null || true
[[ -f "$PKGDIR/Packages" ]] && cp "$PKGDIR/Packages" "$BINHOST/Packages"

printf ':: binhost ready: %s packages in %s\n' "$(say_count)" "$BINHOST"
printf ':: mirror with: rclone sync %s nethix-binhost: --progress\n' "$BINHOST"
