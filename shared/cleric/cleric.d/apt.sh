# apt.sh — cleric spell: Debian-family package health
# Debian/Ubuntu/Mint/Pop!_OS etc.; auto-skips elsewhere via REQUIRES.

NAME="apt"
DESCRIPTION="dpkg interruptions, held-broken packages, apt sources sanity"
REQUIRES="dpkg-query"

run_check() {
    # interrupted/unfinished dpkg transactions
    if dpkg-query --show -f='${Status}\n' 'dpkg:*' 2>/dev/null | grep -q 'install-info'; then :; fi
    local audit
    audit=$(dpkg --audit 2>/dev/null)
    if [[ -n "$audit" ]]; then
        SEVERITY="fail"
        FINDINGS="dpkg reports unfinished/corrupted packages: $(echo "$audit" | head -n 5 | tr '\n' ' ') — run: sudo dpkg --configure -a"
        return
    fi
    if [[ -f /var/lib/dpkg/lock-frontend ]]; then
        if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
           && ! fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
            SEVERITY="fail"
            FINDINGS="stale dpkg locks present (/var/lib/dpkg/lock*) — likely a crashed apt/dpkg run"
            return
        fi
    fi
    # sources parse check
    if command -v apt-get >/dev/null 2>&1; then
        if ! apt-get check >/dev/null 2>&1; then
            SEVERITY="fail"
            FINDINGS="apt-get check failed — broken dependencies: run apt --fix-broken install"
            return
        fi
        # --no-download prevents any network fetch during --simulate
        if ! apt-get --simulate --no-download upgrade >/dev/null 2>&1; then
            SEVERITY="warn"
            FINDINGS="apt upgrade simulation failed — check sources.list entries for errors"
            return
        fi
    fi
    SEVERITY="ok"
    FINDINGS="dpkg database clean, no held-broken packages"
}

try_fix() {
    # safe-ish: finish half-configured packages; does not install/remove anything new
    dpkg --configure -a >/dev/null 2>&1 || return 1
    [[ -z "$(dpkg --audit 2>/dev/null)" ]]
}
