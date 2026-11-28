# fs.sh — cleric spell: filesystem + btrfs health (universal)

NAME="fs"
DESCRIPTION="mount sanity, btrfs device stats, disk space"

run_check() {
    # disk space: warn at >=90% full on any real fs
    local mnt pct
    while read -r mnt; do
        [[ "$mnt" == /proc* || "$mnt" == /sys* || "$mnt" == /dev* || "$mnt" == /run* ]] && continue
        pct=$(df --output=pcent "$mnt" 2>/dev/null | tail -1 | tr -dc '0-9')
        if [[ -n "$pct" && "$pct" -ge 90 ]]; then
            SEVERITY="warn"
            FINDINGS="$mnt is ${pct}% full"
        fi
    done < <(df --output=target -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2 | sort -u)

    # btrfs: errors in device stats (cheap and read-only) — only on btrfs roots
    if command -v btrfs >/dev/null 2>&1 \
       && grep -q ' btrfs ' /proc/mounts 2>/dev/null; then
        local btrfs_root errs
        btrfs_root=$(awk '$3=="btrfs"{print $2; exit}' /proc/mounts)
        if [[ -n "$btrfs_root" ]]; then
            errs=$(btrfs device stats "$btrfs_root" 2>/dev/null | grep -v ' 0$' || true)
            if [[ -n "$errs" ]]; then
                SEVERITY="fail"
                FINDINGS="btrfs device errors on $btrfs_root: $(echo "$errs" | tr '\n' ';')"
                return
            fi
        fi
    fi
    [[ "$SEVERITY" == "ok" ]] && FINDINGS="filesystems healthy"
    return 0
}

# no try_fix: fs failures need human judgment (scrub/balance are too heavy
# to auto-fire); cleric files an issue instead.
