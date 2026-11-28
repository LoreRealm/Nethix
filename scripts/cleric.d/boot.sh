# boot.sh — cleric spell: failed units, kernel/boot sanity

NAME="boot"
DESCRIPTION="failed systemd units, initramfs/kernel presence, journal boot errors"

run_check() {
    local failed=""
    failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $2}')
    if [[ -n "$failed" ]]; then
        SEVERITY="fail"
        FINDINGS="failed systemd unit(s): $(echo "$failed" | tr '\n' ' ')"
        return
    fi
    if ! ls /lib/modules/$(uname -r) >/dev/null 2>&1; then
        SEVERITY="fail"
        FINDINGS="no modules directory for running kernel $(uname -r) — kernel update without reboot or missing modules package"
        return
    fi
    local kimg
    kimg=$(ls /boot/vmlinuz-* 2>/dev/null | tail -1)
    if [[ -z "$kimg" ]]; then
        SEVERITY="fail"
        FINDINGS="no kernel image in /boot — system will not survive reboot"
        return
    fi
    if ! journalctl -b -p err --no-pager 2>/dev/null | tail -n +1 | grep -q .; then
        SEVERITY="ok"; FINDINGS="no boot-time errors in journal"
    else
        SEVERITY="warn"
        FINDINGS="error entries in this boot's journal — inspect: journalctl -b -p err"
    fi
}

try_fix() {
    # safe: attempt restart of failed units once
    local failed
    failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $2}')
    [[ -z "$failed" ]] && return 1
    while read -r u; do
        systemctl reset-failed "$u" 2>/dev/null || true
        systemctl restart "$u" 2>/dev/null || return 1
    done <<<"$failed"
    return 0
}
