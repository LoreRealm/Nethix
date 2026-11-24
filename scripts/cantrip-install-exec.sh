#!/usr/bin/env bash
# cantrip-install-exec — privileged installer entry point.
# Consumes the plan written by the GUI, runs the full install.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }

PLAN=${1:-/var/lib/nethix/cantrip-install-plan.toml}
MNT=${2:-/mnt/nethix}

[[ -f "$PLAN" ]] || { echo "no plan at $PLAN" >&2; exit 1; }

mkdir -p "$MNT"
echo ">>> cantrip-install-exec: plan=$PLAN mount=$MNT"
echo "WARNING: this erases the target disk. Aborting in 5s (Ctrl-C)."
sleep 5

# The GUI binary exposes an --exec mode that drives the Executor from the plan.
exec cantrip-install --exec "$PLAN" "$MNT"
