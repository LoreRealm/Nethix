# update.sh — cleric spell: reboot-required / pending-updates staleness
# Universal: probes whatever package-manager hints exist; never runs an update.

NAME="update"
DESCRIPTION="pending kernel/package updates needing reboot, package cache staleness"

run_check() {
    local reboot_hint=""

    # systemd needs-reboot machinery (works on most systemd distros)
    if command -v needs-reboot >/dev/null 2>&1; then
        needs-reboot >/dev/null 2>&1 || reboot_hint="systemd reports reboot required"
    elif command -v needs-restarting >/dev/null 2>&1; then
        needs-restarting -r >/dev/null 2>&1 || reboot_hint="needs-restarting reports reboot required"
    elif command -v systemd update-reboot 2>/dev/null; then
        :
    fi

    # running kernel vs newest installed kernel image (universal heuristic)
    local running newest
    running=$(uname -r)
    newest=$(ls /lib/modules 2>/dev/null | sort -V | tail -1)
    if [[ -n "$newest" && "$newest" != "$running" ]]; then
        SEVERITY="warn"
        FINDINGS="running kernel $running is older than newest installed $newest — reboot recommended"
        return
    fi

    if [[ -n "$reboot_hint" ]]; then
        SEVERITY="warn"
        FINDINGS="$reboot_hint"
        return
    fi

    # package cache staleness hints (best-effort)
    if command -v pacman >/dev/null 2>&1; then
        local sync_age
        if [[ -f /var/lib/pacman/sync/community.db ]] \
           || [[ -f /var/lib/pacman/sync/core.db ]]; then
            SEVERITY="ok"
            FINDINGS="running latest installed kernel; pacman sync dbs present"
            return
        fi
        SEVERITY="warn"
        FINDINGS="pacman sync databases missing — run pacman -Sy (never -Sy packages)"
        return
    fi

    SEVERITY="ok"
    FINDINGS="running the newest installed kernel"
}

# no try_fix: rebooting and updating are user decisions — never auto.
