# boot.sh — cleric spell: failed units, kernel/boot sanity (universal)

NAME="boot"
DESCRIPTION="failed services, initramfs/kernel presence, boot-time errors"

run_check() {
    # failed units: systemd, then rc-status on OpenRC, else skip
    local failed=""
    if command -v systemctl >/dev/null 2>&1; then
        failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $2}')
        if [[ -n "$failed" ]]; then
            SEVERITY="fail"
            FINDINGS="failed systemd unit(s): $(echo "$failed" | tr '\n' ' ')"
            return
        fi
    elif command -v rc-status >/dev/null 2>&1; then
        failed=$(rc-status --servicelist 2>/dev/null | awk '$NF=="stopped"||$NF=="crashed"{print $2}')
        if [[ -n "$failed" ]]; then
            SEVERITY="warn"
            FINDINGS="stopped/crashed OpenRC service(s): $(echo "$failed" | tr '\n' ' ')"
            return
        fi
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
    if command -v journalctl >/dev/null 2>&1; then
        if journalctl -b -p err --no-pager 2>/dev/null | grep -q .; then
            SEVERITY="warn"
            FINDINGS="error entries in this boot's journal — inspect: journalctl -b -p err"
            return
        fi
    fi
    SEVERITY="ok"
    FINDINGS="no failed units, kernel image present"
}

try_fix() {
    # safe: attempt restart of failed units once (systemd only)
    command -v systemctl >/dev/null 2>&1 || return 1
    local failed
    failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $2}')
    [[ -z "$failed" ]] && return 1
    while read -r u; do
        systemctl reset-failed "$u" 2>/dev/null || true
        systemctl restart "$u" 2>/dev/null || return 1
    done <<<"$failed"
    return 0
}
