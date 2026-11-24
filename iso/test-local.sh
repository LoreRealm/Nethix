#!/usr/bin/env bash
# test-local.sh — headless boot test for the Nethix ISO.
#
# Boots the ISO in QEMU (KVM-accelerated if available), watches the serial
# console for signs of a successful boot, and reports PASS/FAIL with a
# saved log. Dependencies (qemu, etc.) are auto-installed if missing.
#
# Usage:
#   ./test-local.sh [path-to-iso]     # default: ./nethix-live-alpha.iso
#   TIMEOUT=180 ./test-local.sh       # override wait (seconds)
set -euo pipefail

ISO=${1:-nethix-live-alpha.iso}
TIMEOUT=${TIMEOUT:-300}
LOG=${LOG:-/tmp/nethix-boot-test.log}

die() { printf '\e[1;31m!!\e[0m %s\n' "$*" >&2; exit 1; }
say() { printf '\e[1;36m::\e[0m %s\n' "$*"; }

[[ -f "$ISO" ]] || die "ISO not found: $ISO (build one first via iso/build.sh)"

deps=(qemu-system-x86_64)
have() { command -v "$1" >/dev/null 2>&1; }

missing=()
for d in "${deps[@]}"; do
    have "$d" || missing+=("$d")
done

if ((${#missing[@]})); then
    say "missing deps: ${missing[*]}"
    if have apt-get; then sudo apt-get install -y "${missing[@]}"
    elif have dnf; then sudo dnf install -y "${missing[@]}"
    elif have pacman; then sudo pacman -S --noconfirm "${missing[@]}"
    elif have zypper; then sudo zypper install -y "${missing[@]}"
    else die "install manually: ${missing[*]}"
    fi
fi

# ---- pick acceleration
ACCEL=(-accel tcg)
if [[ -w /dev/kvm ]]; then
    ACCEL=(-accel kvm)
    say "KVM available — fast boot expected"
else
    say "no KVM — TCG fallback; boot may take several minutes, consider raising TIMEOUT"
fi

# ---- RAM: half of host, clamped 2-8 GB
RAM_MB=$(( $(free -m | awk '/^Mem:/ {print $2}') / 2 ))
(( RAM_MB > 8192 )) && RAM_MB=8192
(( RAM_MB < 2048 )) && RAM_MB=2048
say "VM RAM: ${RAM_MB} MB"

: > "$LOG"

say "booting $ISO headless, watching serial for up to ${TIMEOUT}s..."
set +e
timeout "${TIMEOUT}s" qemu-system-x86_64 \
    "${ACCEL[@]}" \
    -m "$RAM_MB" \
    -cdrom "$ISO" \
    -boot d \
    -display none \
    -serial stdio \
    -no-reboot \
    2>&1 | tee "$LOG"
QEMU_RC=${PIPESTATUS[0]}
set -e

# ---- analyse serial log
PASS_PATTERNS=("login:" "sddm" "Reached target .*Graphical Interface" "Welcome to Nethix")
FAIL_PATTERNS=("Kernel panic" "not syncing" "No bootable device" "dracut.*(FATAL|emergency)" "Failed to mount")

pass_hit=""
for p in "${PASS_PATTERNS[@]}"; do
    grep -qiE "$p" "$LOG" && { pass_hit="$p"; break; }
done
fail_hit=""
for p in "${FAIL_PATTERNS[@]}"; do
    grep -qiE "$p" "$LOG" && { fail_hit="$p"; break; }
done

if [[ -n "$fail_hit" ]]; then
    say "FAIL — matched failure pattern: '$fail_hit'"
    tail -n 40 "$LOG"
    exit 1
elif [[ -n "$pass_hit" ]]; then
    say "PASS — matched success pattern: '$pass_hit'"
    tail -n 5 "$LOG"
    exit 0
else
    say "INCONCLUSIVE — no pattern matched within ${TIMEOUT}s (rc=$QEMU_RC)"
    tail -n 40 "$LOG"
    exit 2
fi
