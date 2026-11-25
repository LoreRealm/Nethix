#!/usr/bin/env bash
# recommend.sh — pattern-match a portage/ISO build log and print likely
# causes + fixes for known failure modes. Advisory only; exit 0 always.
LOG=${1:-/tmp/iso-build.log}
[[ -r "$LOG" ]] || { echo "recommend: log '$LOG' not readable"; exit 0; }

hit=0
note() {
    hit=1
    {
        echo ""
        echo "### Likely issue: $1"
        echo "**Fix:** $2"
    } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
}

grep -q "masked by" "$LOG" && \
    note "Masked package (keyword/license/mask)" \
         "Check which mask in the log above; iso/portage-seed.sh already sets */* ~amd64 and ACCEPT_LICENSE='* -@EULA' — if a NEW package type appeared, extend the seeder, don't patch build.sh."

grep -qi "required USE flag\|autounmask" "$LOG" && \
    note "Missing USE flag" \
         "Add the flag to iso/portage-seed.sh (package.use section) so both local and CI resolve identically."

grep -qi "no rule to make target\|cpufeaturemasks" "$LOG" && \
    note "Manual kernel make on installed tree" \
         "build.sh must not run make on /usr/src — kernel builds exclusively via emerge (kernel-build eclass). Check no manual make snuck back in."

grep -qi "digest\|verify.*failed\|Manifest.*fail" "$LOG" && \
    note "Manifest/checksum mismatch" \
         "Regenerate: ebuild nethix-sources-<pv>.ebuild manifest (build.sh already attempts this). If the distfile URL changed, update SRC_URI."

grep -qi "Out of memory\|oom-kill\|Cannot allocate memory\|Killed signal" "$LOG" && \
    note "OOM during compile" \
         "Lower MAKEOPTS: the -j heuristic caps at ~2GiB/job but LLVM links spike higher. Drop detect_makeopts divisor or set MAKEOPTS explicitly."

grep -qi "dracut.*failed\|dracut\[E\]" "$LOG" && \
    note "initramfs generation failed" \
         "Check installkernel[dracut] USE seeding; run dracut --regenerate-all manually in the chroot to see the real error."

grep -qi "grub-mkstandalone.*failed\|grub not found\|sys-boot/grub" "$LOG" && \
    note "grub missing from live set" \
         "Add sys-boot/grub to the chroot emerge list in build.sh stage 3."

grep -qi "space left\|No space left" "$LOG" && \
    note "Disk full" \
         "Runner disk exceeded (~35GB needed with firmware). Free space or prune .iso-build."

grep -qi "Permission denied" "$LOG" && \
    note "Permission error" \
         "Likely distfiles perms or running non-root; build.sh self-relaunches as root, check the relaunch path didn't fall through."

(( hit == 0 )) && {
    {
        echo "### No known failure pattern matched"
        echo "If it failed, review the log manually — new failure mode worth adding to recommend.sh."
    } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
}
exit 0
