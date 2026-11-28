# keyring.sh — cleric spell: secrets service health (a known Nethix nemesis)

NAME="keyring"
DESCRIPTION="gnome-keyring/kwallet daemon, secret-tool round-trip"

run_check() {
    # daemon registered on the session bus?
    if command -v busctl >/dev/null 2>&1; then
        if ! busctl --user list 2>/dev/null | grep -qi 'keyring\|kwallet'; then
            SEVERITY="warn"
            FINDINGS="no keyring/wallet service visible on user session bus — browser/app logins will not persist"
            return
        fi
    fi
    # functional round-trip if secret-tool exists
    if command -v secret-tool >/dev/null 2>&1; then
        local probe="cleric-probe-$$"
        if secret-tool store --label="cleric probe" cleric "$probe" "x" 2>/dev/null \
           && secret-tool lookup cleric "$probe" 2>/dev/null | grep -q x; then
            secret-tool clear cleric "$probe" 2>/dev/null
            SEVERITY="ok"; FINDINGS="keyring store/lookup round-trip works"
            return
        else
            secret-tool clear cleric "$probe" 2>/dev/null
            SEVERITY="fail"
            FINDINGS="secret-tool round-trip failed — keyring is present but not functional (logins will be lost on reboot)"
            return
        fi
    fi
    SEVERITY="warn"
    FINDINGS="secret-tool not installed — cannot verify keyring functionality"
}

try_fix() {
    # safe-ish: restart the user keyring daemon via systemd user units
    systemctl --user restart gnome-keyring-daemon.service 2>/dev/null \
        || systemctl --user restart gnome-keyring.service 2>/dev/null \
        || return 1
    sleep 1
    command -v secret-tool >/dev/null 2>&1 || return 0
    local probe="cleric-probe-$$"
    secret-tool store --label="cleric probe" cleric "$probe" "x" 2>/dev/null \
        && secret-tool lookup cleric "$probe" 2>/dev/null | grep -q x \
        && secret-tool clear cleric "$probe" 2>/dev/null
}
