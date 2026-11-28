# fs.sh — cleric spell: filesystem + btrfs health

NAME="fs"
DESCRIPTION="mount sanity, btrfs subvolume/scrub state, disk space"

run_check() {
    # disk space: warn under 10% free on any real fs
    local line mnt pct
    while read -r mnt; do
        [[ "$mnt" == /proc* || "$mnt" == /sys* || "$mnt" == /dev* || "$mnt" == /run* ]] && continue
        pct=$(df --output=pcent "$mnt" 2>/dev/null | tail -1 | tr -dc '0-9')
        if [[ -n "$pct" && "$pct" -ge 90 ]]; then
            SEVERITY="warn"
            FINDINGS="$mnt is ${pct}% full"
        fi
    done < <(df --output=target -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2 | sort -u)

    # btrfs: errors in device stats (btrfs device stats is cheap and read-only)
    if command -v btrfs >/dev/null 2>&1; then
        local errs
        errs=$(btrfs device stats / 2>/dev/null | grep -v ' 0$' || true)
        if [[ -n "$errs" ]]; then
            SEVERITY="fail"
            FINDINGS="btrfs device errors on /: $(echo "$errs" | tr '\n' ';')"
            return
        fi
    fi
    [[ "$SEVERITY" == "ok" ]] && FINDINGS="filesystems healthy"
    return 0
}

# no try_fix: fs failures need human judgment (scrub/balance are too heavy
# to auto-fire); cleric files an issue instead.
