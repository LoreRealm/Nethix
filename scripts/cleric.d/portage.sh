# portage.sh — cleric spell: portage config + dependency health

NAME="portage"
DESCRIPTION="broken world resolution, config syntax, binhost index freshness"

run_check() {
    # make.conf syntax
    if ! bash -n /etc/portage/make.conf 2>/dev/null; then
        SEVERITY="fail"
        FINDINGS="/etc/portage/make.conf has shell syntax errors"
        return
    fi
    # broken world set
    local out rc
    out=$(emerge --pretend --quiet @world 2>&1); rc=$?
    if [[ $rc -ne 0 ]]; then
        SEVERITY="fail"
        FINDINGS="portage cannot resolve @world: $(echo "$out" | tail -n 5)"
        return
    fi
    # binhost Packages index present when binhost is configured
    if grep -q '^PORTAGE_BINHOST' /etc/portage/make.conf 2>/dev/null; then
        local pkgdir
        pkgdir=$(portageq envvar PKGDIR 2>/dev/null)
        if [[ -n "$pkgdir" && ! -f "$pkgdir/Packages" ]]; then
            SEVERITY="warn"
            FINDINGS="binhost configured but $pkgdir/Packages index missing — run: emaint binhost --fix"
            return
        fi
    fi
    SEVERITY="ok"; FINDINGS="portage resolves @world cleanly"
}

try_fix() {
    local pkgdir
    pkgdir=$(portageq envvar PKGDIR 2>/dev/null) || return 1
    emaint binhost --fix >/dev/null 2>&1 || return 1
    [[ -f "$pkgdir/Packages" ]]
}
