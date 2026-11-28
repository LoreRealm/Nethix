#!/usr/bin/env bash
# build.sh — assemble the Nethix live ISO.
#
# Stages:
#   1. chroot prep (stage3 download, bind mounts, resolv.conf, locale)
#   2. overlay + profile injection  (via iso/portage-seed.sh — shared with CI preflight)
#   3. emerge live set (+ linux-firmware for hardware compatibility)
#   4. installer binaries — pulled from nethix-artifacts repo (public)
#   5. liveuser
#   6. kernel + initramfs via portage (kernel-build eclass + installkernel/dracut)
#   7. squashfs + ISO assembly via grub-mkrescue
#   8. binhost export — collect built .tbz2 packages for reuse
#
# Requirements: ~35 GB free (firmware is chunky). Run from anywhere —
# needs root, relaunches itself via sudo or pkexec (pkexec survives
# broken /dev/pty states that break sudo password prompts).
#
# SPEED: if a previous build exported packages into <repo>/binhost/
# (stage 8), this build REUSES them automatically — the big compiles
# (LLVM/clang toolchain, kernel deps) install as prebuilts instead of
# recompiling. First build ~90 min, second build onward ~15-20 min.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

# self-heal the executable bit (git checkouts from zip/other hosts can lose it)
chmod +x "$0" iso/charm-bar.sh iso/portage-seed.sh scripts/*.sh 2>/dev/null || true

# Progress output: SIMPLE by default — portage's own stage banners, package
# names and errors, nothing else. The rune charm-bar (iso/charm-bar.sh) is
# OFF for ISO creation; it's reserved for the user-facing install flow
# (summon). Opt in with CHARM=1 if you want it here anyway.
CHARM=${CHARM:-0}
CHARM_BAR="$REPO_ROOT/iso/charm-bar.sh"

# run_charm LABEL CMD... — wrap a chroot command's output in the rune bar
# when CHARM is enabled, else pass output through untouched.
run_charm() {
    local label=$1; shift
    if [[ $CHARM -eq 1 && -x $CHARM_BAR ]]; then
        "$@ 2>&1 | $CHARM_BAR"'"'" "$label" 2>/dev/null && eval "$*"
    else
        "$@" 2>&1
    fi
}
