#!/usr/bin/env bash
# forge — hardware detection for Nethix (chwd equivalent).
# Wrapper: scans PCI, emits make.conf snippet.
set -euo pipefail
BINDIR=$(dirname "$(readlink -f "$0")")
exec "$BINDIR/../installer/target/release/forge" "$@"
