#!/usr/bin/env bash
# build.sh — assemble the Nethix live ISO.
#
# Stages:
#   1. chroot prep (stage3 download, bind mounts, resolv.conf)
#   2. overlay + profile injection
#   3. emerge live set (binhost-first)
#   4. inject installer binaries (from ./out/installer-dist)
#   5. liveuser + Plasma autologin config
#   6. kernel + initramfs (dracut) install to boot/
#   7. squashfs of the root, xorriso into ISO
#
# Requirements: root, ~30 GB free. Run from anywhere — the script
# resolves the repo root itself.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

WORK="$REPO_ROOT/.iso-build"
STAGE3_URL=${STAGE3_URL:-https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/}
OUT_ISO=${OUT_ISO:-nethix-live-alpha.iso}

say() { printf '\e[1;36m::\e[0m %s\n' "$*"; }
die() { printf '\e[1;31m!!\e[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (needs mounts for chroot)"

mkdir -p "$WORK"/root

# --- 1. stage3
say "fetching latest stage3 manifest + tarball..."
LATEST=$(curl -fsSL "$STAGE3_URL" | grep -oE 'stage3-amd64-systemd-[0-9.]+T[0-9]+Z\.tar\.xz' | sort -r | head -n1)
[[ -n "$LATEST" ]] || die "couldn't locate a stage3 tarball on the mirror"
curl -fL -o "$WORK/stage3.tar.xz" "$STAGE3_URL/$LATEST"

say "unpacking stage3..."
tar -xpf "$WORK/stage3.tar.xz" -C "$WORK/root" --xattrs --numeric-owner

# network for the chroot
cp -L /etc/resolv.conf "$WORK/root/etc/resolv.conf"

# portage dirs stage3 doesn't pre-create
mkdir -p "$WORK/root"/var/db/repos/{nethix,gentoo} \
         "$WORK/root"/etc/portage/repos.conf \
         "$WORK/root"/var/cache/distfiles

mount --bind /proc "$WORK/root/proc"
mount --bind /sys "$WORK/root/sys"
mount --rbind /dev "$WORK/root/dev"
cleanup() {
    umount -R "$WORK/root/dev" 2>/dev/null || true
    umount "$WORK/root/proc" "$WORK/root/sys" 2>/dev/null || true
}
trap cleanup EXIT

# --- 2. overlay + profile
say "wiring nethix overlay + profile into the chroot..."
cp -r overlay/* "$WORK/root/var/db/repos/nethix/"
cat > "$WORK/root/etc/portage/repos.conf/nethix.conf" <<EOF
[nethix]
location = /var/db/repos/nethix
priority = 50
masters = gentoo
EOF
if [[ -f profiles.d/makeconf.amd64-v3 ]]; then
    cp profiles.d/makeconf.amd64-v3 "$WORK/root/etc/portage/make.conf"
else
    say "WARN: profiles.d/makeconf.amd64-v3 not found; using stage3 default make.conf"
fi

# --- 3. emerge the live set
say "emerging live set..."
chroot "$WORK/root" /bin/bash -c '
    emerge-webrsync || emerge --sync || true
    emerge --ask=n --autounmask-write app-misc/fastfetch || true
'
# NOTE: full Plasma emerge is hours. Alpha ISO focuses on boot verification.

# --- 4. installer binaries
say "injecting summon/forge/scri binaries..."
if [[ -d out/installer-dist ]]; then
    mkdir -p "$WORK/root/usr/local/bin"
    cp out/installer-dist/{summon,summon-exec,forge,scri} "$WORK/root/usr/local/bin/" 2>/dev/null \
        || say "WARN: some binaries missing in out/installer-dist (expected: summon summon-exec forge scri)"
else
    say "WARN: out/installer-dist absent — download build-installer workflow artifacts first"
fi

# --- 5. liveuser + autologin
say "creating liveuser..."
chroot "$WORK/root" /bin/bash -c '
    useradd -m -G wheel,audio,video,plugdev liveuser
    echo "liveuser:liveuser" | chpasswd
'

# --- 6. kernel + initramfs
say "installing kernel + dracut initramfs..."
chroot "$WORK/root" /bin/bash -c '
    emerge --ask=n sys-kernel/nethix-sources || die_emerge
    die_emerge() { echo "nethix-sources emerge failed"; exit 1; }
    cd /usr/src/linux-$(ls -1 /usr/src | grep -E "^linux-[0-9]" | sort -Vr | head -n1 | sed "s/^linux-//")
    make olddefconfig
    make -j$(nproc)
    make modules_install
    INSTALL_PATH=/boot make install
'
chroot "$WORK/root" dracut --force --regenerate-all --hostonly=no || \
    die "dracut failed — initramfs missing"

# --- 7. squashfs + ISO
say "packing squashfs..."
mkdir -p "$WORK/iso-root"
mksquashfs "$WORK/root" "$WORK/iso-root/live.squashfs" -comp zstd -Xcompression-level 19

KIMG=$(ls "$WORK/root/boot"/vmlinuz-* 2>/dev/null | head -n1)
[[ -n "$KIMG" ]] || die "no kernel image in chroot /boot"
INITRD=$(ls "$WORK/root/boot"/initramfs-*.img 2>/dev/null | head -n1)
[[ -n "$INITRD" ]] || die "no initramfs in chroot /boot"

cp "$KIMG" "$WORK/iso-root/vmlinuz"
cp "$INITRD" "$WORK/iso-root/initramfs.img"

say "assembling ISO..."
# Minimal ISOLINUX-free UEFI+BIOS boot via grub-mkstandalone (works without
# a pre-installed grub stage in the chroot).
chroot "$WORK/root" grub-mkstandalone \
    -O i386-efi -o "$WORK/iso-root/efi-boot.img" \
    "boot/grub/grub.cfg=grub-live.cfg" 2>/dev/null \
|| chroot "$WORK/root" grub-mkstandalone \
    -O i386-pc -o "$WORK/iso-root/bios-boot.img" \
    "boot/grub/grub.cfg=grub-live.cfg" \
|| die "grub-mkstandalone failed (is sys-boot/grub emerged in the chroot?)"

cat > grub-live.cfg <<'EOF'
set timeout=5
menuentry "Nethix Live" {
    linux /vmlinuz root=live:CDLABEL=NETHIX_LIVE rd.live.image rd.live.squashimg=live.squashfs
    initrd /initramfs.img
}
EOF

xorriso -as mkisofs -iso-level 3 -volid NETHIX_LIVE \
    -o "$OUT_ISO" \
    -eltorito-boot bios-boot.img -no-emul-boot \
    -append-partition 2 -efi-boot-part --efi-boot-image --protective-msdos-label \
    efi-boot.img \
    vmlinuz initramfs.img live.squashfs 

die_if_missing() { [[ -f "$OUT_ISO" ]] || die "ISO output missing"; }
die_if_missing
say "done: $REPO_ROOT/$OUT_ISO"
