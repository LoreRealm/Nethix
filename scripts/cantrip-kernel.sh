#!/usr/bin/env bash
# cantrip-kernel — rebuild + reinstall nethix-sources.
# Regenerates limine.conf after kernel updates (see TODO: Limine default).
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }

say() { printf '\e[1;35m>>>\e[0m %s\n' "$*"; }

say "emerging nethix-sources..."
emerge --ask=n --oneshot sys-kernel/nethix-sources

KVER=$(ls -1 /usr/src | grep -E '^linux-[0-9]' | sort -Vr | head -n1 | sed 's/^linux-//')
[[ -n "$KVER" ]] || { echo "no kernel tree found in /usr/src" >&2; exit 1; }
say "latest tree: $KVER"

say "building kernel (olddefconfig + allmodconfig-ish pragmatism)..."
cd "/usr/src/linux-$KVER"
[[ -f .config ]] || cp /var/lib/nethix/kernel-config .config 2>/dev/null || make defconfig
make -j"$(nproc)" olddefconfig
make -j"$(nproc)"

say "installing modules + kernel..."
make modules_install
INSTALL_PATH=/boot make install

say "regenerating limine.conf (TODO when limine lands; grub-mkconfig for now)..."
grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || say "manual bootloader update needed"

say "kernel $KVER installed. Reboot to switch."
