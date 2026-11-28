# dnf.sh — cleric spell: Fedora/RPM-family package health
# Fedora/RHEL/openSUSE(dnf part) etc.; auto-skips elsewhere via REQUIRES.

NAME="dnf"
DESCRIPTION="rpm db verification, dnf check problems, stale rpm locks"
REQUIRES="rpm"

run_check() {
    # rpm database sanity
    if ! rpm -q rpm >/dev/null 2>&1; then
        SEVERITY="fail"
        FINDINGS="rpm database unreadable — 'rpm -qa' failing; may need rpm --rebuilddb"
        return
    fi
    # stale transaction lock (no lockf holder)
    if [[ -f /var/lib/rpm/.rpm.lock ]] \
       && command -v fuser >/dev/null 2>&1 \
       && ! fuser /var/lib/rpm/.rpm.lock >/dev/null 2>&1; then
        SEVERITY="fail"
        FINDINGS="stale rpm transaction lock /var/lib/rpm/.rpm.lock"
        return
    fi
    # dependency check if dnf exists
    if command -v dnf >/dev/null 2>&1; then
        if ! dnf check >/dev/null 2>&1; then
            SEVERITY="fail"
            FINDINGS="dnf check reports dependency problems: run dnf check for details"
            return
        fi
    elif command -v zypper >/dev/null 2>&1; then
        if ! zypper verify >/dev/null 2>&1; then
            SEVERITY="fail"
            FINDINGS="zypper verify reports dependency problems"
            return
        fi
    fi
    SEVERITY="ok"
    FINDINGS="rpm database and dependencies healthy"
}

try_fix() {
    # safe: drop a stale rpm lock when nothing holds it
    if [[ -f /var/lib/rpm/.rpm.lock ]] \
       && ! fuser /var/lib/rpm/.rpm.lock >/dev/null 2>&1; then
        rm -f /var/lib/rpm/.rpm.lock
        return 0
    fi
    return 1
}
