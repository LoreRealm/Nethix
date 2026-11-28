# wm.sh — cleric spell: compositor/window-manager crash loop detection (universal)

NAME="wm"
DESCRIPTION="compositor (niri/kwin/sway/weston/...) crash-restart patterns in logs"

run_check() {
    local restarts=0
    if command -v journalctl >/dev/null 2>&1; then
        # count segfaults/coredumps mentioning common compositor binaries this boot
        restarts=$(journalctl -b --no-pager 2>/dev/null \
            | grep -ciE 'segfault.*(niri|kwin_wayland|plasmashell|sway|weston|hyprland|mutter|labwc)' || true)
    elif [[ -r /var/log/syslog || -r /var/log/messages ]]; then
        # syslog fallback for non-journald systems
        local log=/var/log/syslog
        [[ -r /var/log/messages ]] && log=/var/log/messages
        restarts=$(grep -ciE 'segfault.*(niri|kwin_wayland|plasmashell|sway|weston|hyprland|mutter|labwc)' "$log" 2>/dev/null || true)
    else
        SEVERITY="warn"
        FINDINGS="no readable system log (journald or /var/log) — cannot check compositor health"
        return
    fi
    if (( restarts >= 3 )); then
        SEVERITY="fail"
        FINDINGS="$restarts compositor segfault(s) detected — likely crash loop; check your system log for 'segfault|coredump'"
        return
    elif (( restarts > 0 )); then
        SEVERITY="warn"
        FINDINGS="$restarts compositor segfault(s) detected (not yet a loop)"
        return
    fi
    SEVERITY="ok"; FINDINGS="no compositor crash patterns detected"
}

# no try_fix: restarting a compositor kills the user's session — never auto.
