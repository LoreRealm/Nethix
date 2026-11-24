#!/usr/bin/env bash
# Build the curated Nethix binhost set (Plasma desktop). Run in a container/CI.
set -euo pipefail
emerge --buildpkg --usepkg --jobs "$(nproc)" \
    $(sed 's/#.*//' sets/plasma-desktop.set)
mkdir -p out && cp -r /var/cache/binpkgs/packages/* out/
