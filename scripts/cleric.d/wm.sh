# wm.sh — cleric spell: compositor/window-manager crash loop detection

NAME="wm"
DESCRIPTION="compositor (niri/plasma/kwin) crash-restart patterns in journal"

run_check() {
    local restarts=0
    # count segfaults/coredumps mentioning common compositor binaries this boot
    restarts=$(journalctl -b --no-pager 2>/dev/null \
        | grep -ciE 'segfault.*(niri|kwin_wayland|plasmashell|sway|weston)' || true)
    if (( restarts >= 3 )); then
        SEVERITY="fail"
        FINDINGS="$restarts compositor segfault(s) this boot — likely crash loop; check: journalctl -b | grep -iE 'segfault|coredump'"
        return
    elif (( restarts > 0 )); then
        SEVERITY="warn"
        FINDINGS="$restarts compositor segfault(s) this boot (not yet a loop)"
        return
    fi
    SEVERITY="ok"; FINDINGS="no compositor crash patterns detected"
}

# no try_fix: restarting a compositor kills the user's session — never auto.
