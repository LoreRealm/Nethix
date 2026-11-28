# pacman.sh — cleric spell: Arch-family package database + keyring health
# Arch/CachyOS/EndeavourOS/Manjaro etc.; auto-skips elsewhere via REQUIRES.

NAME="pacman"
DESCRIPTION="pacman db integrity, db lock leftovers, arch keyring freshness"
REQUIRES="pacman"

run_check() {
    # leftover database lock (common after a crashed -Syu)
    if [[ -f /var/lib/pacman/db.lck ]]; then
        if pgrep -x pacman >/dev/null 2>&1; then
            SEVERITY="warn"
            FINDINGS="/var/lib/pacman/db.lck exists but pacman is running — likely a normal transaction"
            return
        fi
        SEVERITY="fail"
        FINDINGS="stale pacman db lock /var/lib/pacman/db.lck (no pacman process) — remove it after checking"
        return
    fi
    # database consistency: local db readable and non-empty
    if [[ ! -s /var/lib/pacman/local/desc ]]; then
        SEVERITY="fail"
        FINDINGS="pacman local db at /var/lib/pacman/local looks empty/corrupt — avoid upgrades until checked (pacman -Qk, rebuild db)"
        return
    fi
    # keyring package present and parseable
    if ! pacman -Q archlinux-keyring >/dev/null 2>&1 \
       && ! pacman -Q cachyos-keyring >/dev/null 2>&1; then
        SEVERITY="warn"
        FINDINGS="no keyring package installed (archlinux-keyring) — signature errors likely"
        return
    fi
    SEVERITY="ok"
    FINDINGS="pacman database and lock state healthy"
}

try_fix() {
    # safe: remove a stale lock when no pacman process exists
    [[ -f /var/lib/pacman/db.lck ]] || return 1
    pgrep -x pacman >/dev/null 2>&1 && return 1
    rm -f /var/lib/pacman/db.lck
}
