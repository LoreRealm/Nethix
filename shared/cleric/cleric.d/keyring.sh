# keyring.sh — cleric spell: secrets service health (universal)

NAME="keyring"
DESCRIPTION="keyring/wallet daemon presence, secret-tool round-trip"

run_check() {
    # daemon registered on the session bus?
    if command -v busctl >/dev/null 2>&1; then
        if ! busctl --user list 2>/dev/null | grep -qi 'keyring\|kwallet'; then
            SEVERITY="warn"
            FINDINGS="no keyring/wallet service visible on user session bus — browser/app logins will not persist"
            return
        fi
    elif command -v dbus-send >/dev/null 2>&1; then
        # non-systemd fallback: list activatable/name-owned secrets services via D-Bus
        if ! dbus-send --session --dest=org.freedesktop.DBus --type=method_call \
             --print-reply / org.freedesktop.DBus.ListNames 2>/dev/null \
             | grep -qi 'keyring\|kwallet'; then
            SEVERITY="warn"
            FINDINGS="no keyring/wallet service on session bus — browser/app logins will not persist"
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
            FINDINGS="secret-tool round-trip failed — keyring is present but not functional (logins may be lost on reboot)"
            return
        fi
    fi
    SEVERITY="warn"
    FINDINGS="secret-tool not installed — cannot verify keyring functionality"
}

try_fix() {
    # safe-ish: restart the user keyring daemon (systemd user unit first,
    # then a bare daemon relaunch under the current session)
    if command -v systemctl >/dev/null 2>&1 \
       && systemctl --user restart gnome-keyring-daemon.service 2>/dev/null; then
        :
    elif command -v systemctl >/dev/null 2>&1 \
       && systemctl --user restart gnome-keyring.service 2>/dev/null; then
        :
    elif command -v gnome-keyring-daemon >/dev/null 2>&1; then
        # non-systemd: kill stale daemon, let the session respawn it
        pkill -u "$(id -un)" -x gnome-keyring-daemon 2>/dev/null
        sleep 1
    else
        return 1
    fi
    sleep 1
    command -v secret-tool >/dev/null 2>&1 || return 0
    local probe="cleric-probe-$$"
    secret-tool store --label="cleric probe" cleric "$probe" "x" 2>/dev/null \
        && secret-tool lookup cleric "$probe" 2>/dev/null | grep -q x \
        && secret-tool clear cleric "$probe" 2>/dev/null
}
