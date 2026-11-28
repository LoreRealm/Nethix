# storage.sh — cleric spell: SMART health + dm-crypt/LVM device state (universal)

NAME="storage"
DESCRIPTION="SMART overall health, degraded/inactive mdraid or LVM volumes"

run_check() {
    # SMART overall-health for every physical disk that supports it
    if command -v smartctl >/dev/null 2>&1; then
        local dev line health bad=""
        while read -r dev; do
            line=$(smartctl -H "$dev" 2>/dev/null | grep -i 'overall-health\|result' | tail -1)
            if [[ -n "$line" && ! "$line" =~ PASSED ]]; then
                bad+="$(basename "$dev"): $(echo "$line" | awk '{print $NF}') "
            fi
        done < <(ls /dev/sd?[a-z]* /dev/nvme[0-9]+n[0-9]+ 2>/dev/null | grep -v '[0-9]$' ; ls -d /dev/sd[a-z] /dev/nvme[0-9]n[0-9] 2>/dev/null)
        if [[ -n "$bad" ]]; then
            SEVERITY="fail"
            FINDINGS="SMART failure predicted on: $bad— back up now and check: smartctl -a <device>"
            return
        fi
    fi
    # mdadm: any degraded or recovering arrays
    if command -v mdadm >/dev/null 2>&1 && [[ -d /proc/mdstat ]] && grep -qs ':' /proc/mdstat 2>/dev/null; then
        local md_bad
        md_bad=$(grep -E '\[[^)]*_*' /proc/mdstat 2>/dev/null | grep -c '_' || true)
        if (( md_bad > 0 )); then
            SEVERITY="fail"
            FINDINGS="$md_bad mdraid device line(s) show missing/degraded members — inspect /proc/mdstat"
            return
        fi
    fi
    # LVM: inactive VGs
    if command -v lvs >/dev/null 2>&1; then
        local inactive
        inactive=$(lvs --noheadings -o lv_attr,vg_name,lv_name 2>/dev/null | awk '$1 ~ /^[-a-z]{5,}[ai-]/ && substr($1,5,1)!="a" {print $2"/"$3}' || true)
        if [[ -n "$inactive" ]]; then
            SEVERITY="warn"
            FINDINGS="inactive LVM volume(s): $(echo "$inactive" | tr '\n' ' ')"
            return
        fi
    fi
    SEVERITY="ok"
    FINDINGS="${bad:+no} SMART ${bad:+issues}; storage device state nominal"
}

# no try_fix: SMART failures and degraded arrays are hardware emergencies —
# a safe automatic action does not exist. Report, file, and let a human act.
