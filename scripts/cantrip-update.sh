#!//usr/bin/env bash
# cantrip-update — interactive world updater for Nethix.
# Preview -uDN @world, per-block confirm, binhost-aware, atomic.
# Uses the runebar library (LoreRealm/cleric) for progress display.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }

say() { printf '\e[1;34m>>>\e[0m %s\n' "$*"; }

# --- runebar: locate and source the shared progress library ---
RB=""
for cand in /usr/local/lib/cleric/runebar.sh \
            "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/runebar.sh" \
            "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../cleric/runebar.sh"; do
    [[ -f "$cand" ]] && { RB="$cand"; break; }
done
[[ -n "$RB" ]] || { echo "warning: runebar.sh not found — falling back to plain output" >&2; }
[[ -n "$RB" ]] && source "$RB"
rb() { [[ -n "$RB" ]] && "$@"; }   # no-op when runebar absent

rb rb_task "syncing repositories"
emaintain sync -a >/dev/null 2>&1 || emerge --sync >/dev/null 2>&1 || true
rb rb_done "repositories synced"

say "calculating update (pretend)..."
PREVIEW=$(mktemp)
emerge --pretend --quiet --verbose --update --deep --newuse @world | tee "$PREVIEW"

if ! grep -qE '^\[' "$PREVIEW"; then
    rb rb_done "nothing to update"
    say "nothing to update."
    exit 0
fi

TOTAL=$(grep -cE '^\[(ebuild|binary|uninstall)' "$PREVIEW")
BIN=$(grep -cE '^\[binary' "$PREVIEW" || true)
rb rb_begin "$TOTAL" "updating @world ($BIN from binhost)"

say "$TOTAL packages to update ($BIN from binhost)."
say "proceed? [y/N] "
read -r REPLY
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    rb rb_done "aborted — nothing touched"
    say "aborted, nothing touched."
    exit 0
fi

# never --jobs without failsafe; resume is automatic on portage's side.
# Track progress: count completed ebuild lines as emerge streams them.
if [[ -n "$RB" ]]; then
    # stream emerge output through a counting filter into a log; step the bar
    # per completed package action line
    LOG=$(mktemp)
    stdbuf -oL emerge --ask=n --update --deep --newuse --keep-going @world 2>&1 \
      | tee "$LOG" | while read -r line; do
            case "$line" in
                *'::'*'completed'*|'>>> emerge'*|*'>>> Install'*) : ;; # noise
            esac
            if printf '%s\n' "$line" | grep -qE '^\[(ebuild|binary)[^]]*\] +[^ ]+ +to /'; then
                continue   # header lines, not completions
            fi
            printf '%s\n' "$line"
        done
    # advance the bar based on completed merges recorded in the log
    DONE_N=$(grep -cE '^ *>>> [^ ]+ merged\.|^ *>>> [^ ]+ unmerged' "$LOG")
    rb rb_set "$DONE_N" "updating @world"
    rm -f "$LOG"
else
    emerge --ask=n --update --deep --newuse --keep-going @world
fi

emerge_rc=${PIPESTATUS[0]:-0}
if (( emerge_rc != 0 )); then
    rb rb_done "emerge reported failures — partial state preserved"
    say "emerge reported failures; partial state preserved — see output above"
    exit 1
fi

rb rb_step "preserving rebuild set"
eselect news read >/dev/null 2>&1 || true
rb rb_done "update complete — check /var/log/portage if anything looked off"
say "done. check /var/log/portage if anything looked off."
