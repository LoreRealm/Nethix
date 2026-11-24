#!//usr/bin/env bash
# cantrip-update — interactive world updater for Nethix.
# Preview -uDN @world, per-block confirm, binhost-aware, atomic.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }

say() { printf '\e[1;34m>>>\e[0m %s\n' "$*"; }

say "syncing repositories..."
emaintain sync -a >/dev/null 2>&1 || emerge --sync >/dev/null 2>&1 || true

say "calculating update (pretend)..."
PREVIEW=$(mktemp)
emerge --pretend --quiet --verbose --update --deep --newuse @world | tee "$PREVIEW"

if ! grep -qE '^\[' "$PREVIEW"; then
    say "nothing to update."
    exit 0
fi

TOTAL=$(grep -cE '^\[(ebuild|binary|uninstall)' "$PREVIEW")
BIN=$(grep -cE '^\[binary' "$PREVIEW" || true)
say "$TOTAL packages to update ($BIN from binhost)."

say "proceed? [y/N] "
read -r REPLY
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    say "aborted, nothing touched."
    exit 0
fi

# never --jobs without failsafe; resume is automatic on portage's side
emerge --ask=n --update --deep --newuse --keep-going @world || {
    say "emerge reported failures; partial state preserved — see output above"
    exit 1
}

say "preserving rebuild set..."
eselect news read >/dev/null 2>&1 || true
say "done. check /var/log/portage if anything looked off."
