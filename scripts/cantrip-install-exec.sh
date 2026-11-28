#!/usr/bin/env bash
# cantrip-install-exec — privileged installer entry point.
# Consumes the plan written by the GUI, runs the full install.
# Uses the runebar library (LoreRealm/cleric) for staged progress display.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }

PLAN=${1:-/var/lib/nethix/cantrip-install-plan.toml}
MNT=${2:-/mnt/nethix}

[[ -f "$PLAN" ]] || { echo "no plan at $PLAN" >&2; exit 1; }

# --- runebar: locate and source the shared progress library ---
RB=""
for cand in /usr/local/lib/cleric/runebar.sh \
            "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/runebar.sh" \
            "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../cleric/runebar.sh"; do
    [[ -f "$cand" ]] && { RB="$cand"; break; }
done
[[ -n "$RB" ]] && source "$RB"
rb() { [[ -n "${RB:-}" ]] && "$@"; }

# 5 installer stages the executor runs through; we display as it reports.
STAGES=("partition target disk" "mount filesystems" "unpack stage + binhost packages"
        "configure system (fstab, users, boot)" "install bootloader + finish")

mkdir -p "$MNT"
rb rb_begin 5 "cantrip-install"

printf '>>> cantrip-install-exec: plan=%s mount=%s\n' "$PLAN" "$MNT"
rb rb_set 0 "waiting for operator confirmation"
printf 'WARNING: this erases the target disk. Aborting in 5s (Ctrl-C).\n'
sleep 5

# The GUI binary exposes an --exec mode that drives the Executor from the plan.
# Stages are announced on stdout; step the rune bar each time one passes.
exec_replace() {
    local stage_idx=0
    cantrip-install --exec "$PLAN" "$MNT" | while read -r line; do
        printf '%s\n' "$line"
        local i
        for i in "${!STAGES[@]}"; do
            if printf '%s' "$line" | grep -qiF "${STAGES[$i]}"; then
                stage_idx=$(( i + 1 > 5 ? 5 : i + 1 ))
                rb rb_set "$stage_idx" "${STAGES[$i]}"
                break
            fi
        done
    done
}
exec_replace

# if exec reached here without matching all stages, drive the bar home
rb rb_set 5 "installation complete"
rb rb_done "ᛝ cantrip-install finished — the ritual is sealed"
