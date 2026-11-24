#!/usr/bin/env bash
# build.sh — assemble the Nethix live ISO.
#
# Stages:
#   1. chroot prep (stage3 download, bind mounts, resolv.conf)
#   2. overlay + profile injection (cantrip-stage's chroot equivalent)
#   3. emerge live set (binhost-first)
#   4. inject installer binaries (from ./out/installer-dist)
#   5. liveuser + Plasma autologin config
#   6. kernel + initramfs (dracut) install to boot/
#   7. squashfs of the root, xorriso into ISO
#
# Requirements: root, ~30 GB free, podman OR docker (for stage3 unpack)
set -euo pipefail

WORK=$(pwd)/.iso-build
STAGE3_URL=${STAGE3_URL:-https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/}
OUT_ISO=${OUT_ISO:-nethix-live-alpha.iso}

say() { printf '\e[1;36m::\e[0m %s\n' "$*"; }
die() { printf '\e[1;31m!!\e[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (needs mounts + chown for chroot)"

mkdir -p "$WORK"/root

# --- 1. stage3
say "fetching latest stage3 manifest + tarball..."
LATEST=$(curl -fsSL "$STAGE3_URL" | grep -oE 'stage3-amd64-systemd-[0-9.]+T[0-9]+Z\.tar\.xz' | sort -r | head -n1)
[[ -n "$LATEST" ]] || die "couldn't locate a stage3 tarball on the mirror"
curl -fL -o "$WORK/stage3.tar.xz" "$STAGE3_URL/$LATEST"
curl -fL -o "$WORK/stage3.DIGESTS" "$STAGE3_URL/$LATEST.DIGESTS"

say "unpacking stage3..."
tar -xpf "$WORK/stage3.tar.xz" -C "$WORK/root" --xattrs --numeric-owner

cp -L /etc/resolv.conf "$WORK/root/etc/resolv.conf"
mount --bind /proc "$WORK/root/proc"
mount --bind /sys "$WORK/root/sys"
mount --bind /dev "$WORK/root/dev"
trap 'umount "$WORK/root/proc" "$WORK/root/sys" "$WORK/root/dev" 2>/dev/null || true' EXIT

# --- 2. overlay + profile
say "wiring nethix overlay + profile into the chroot..."
mkdir -p "$WORK/root/var/db/repos/nethix"
cp -r overlay/* "$WORK/root/var/db/repos/nethix/"
cat > "$WORK/root/etc/portage/repos.conf/nethix.conf" <<'EOF'
[nethix]
location = /var/db/repos/nethix
priority = 50
masters = gentoo
EOF
cp profiles.d/makeconf.amd64-v3 "$WORK/root/etc/portage/make.conf" 2>/dev/null \
    || say "WARN: profiles.d/makeconf.amd64-v3 not found; falling back to stage3 default"

# --- 3. emerge the live set
say "emerging live set (binhost-first if configured)..."
chroot "$WORK/root" /bin/bash -c '
    emerge --ask=n --getbinpkg app-misc/fastfetch sys-apps/systemd || true
    emerge --ask=n @world
'
# NOTE: full Plasma emerge on a single runner takes hours. For alpha: use
# binhost exclusively, or split this job into a nightly with caching.

# --- 4. installer binaries
say "injecting summon/forge binaries..."
if [[ -d out/installer-dist ]]; then
    mkdir -p "$WORK/root/usr/local/bin"
    cp out/installer-dist/{summon,summon-exec,forge,scri} "$WORK/root/usr/local/bin/" || \
        say "WARN: some binaries missing in out/installer-dist"
else
    say "WARN: out/installer-dist absent — download build-installer artifacts first"
fi

# --- 5. liveuser + autologin
say "creating liveuser with Plasma autologin..."
chroot "$WORK/root" /bin/bash -c '
    useradd -m -G wheel,audio,video,plugdev liveuser
    echo "liveuser:liveuser" | chpasswd
    mkdir -p /etc/sddm.conf.d
    printf "[Autologin]\nUser=liveuser\nSession=plasma.desktop\n" > /etc/sddm.conf.d/autologin.conf
'

# --- 6. kernel + initramfs
say "installing kernel + dracut initramfs..."
chroot "$WORK/root" /bin/bash -c '
    emerge --ask=n sys-kernel/nethix-sources
    cd /usr/src/linux && make olddefconfig && make -j$(nproc)
    make modules_install
    INSTALL_PATH=/boot make install
    dracut --force --kver $(ls /lib/modules | head -n1) /boot/initramfs.img
'

# --- 7. squashfs + ISO
say "packing squashfs..."
mkdir -p "$WORK"/iso-root/{squashfs,boot}
mksquashfs "$WORK/root" "$WORK/iso-root/squashfs/live.squashfs" -comp zstd -Xcompression-level 19

cp "$WORK/root/boot/vmlinuz-*" "$WORK/iso-root/boot/" 2>/dev/null \
    || die "no kernel image found in /boot after build"
cp "$WORK/root/boot/initramfs.img" "$WORK/iso-root/boot/"

say "assembling ISO (xorriso)..."
cat > "$WORK/iso-root/boot/grub.cfg" <<'EOF'
set timeout=5
menuentry "Nethix Live (Plasma)" {
    linux /boot/vmlinuz root=live:CDLABEL=NETHIX_LIVE rd.live.squashimg=/live.squashfs
    initrd /boot/initramfs.img
}
EOF
xorriso -as mkisofs -iso-level 3 -o "$OUT_ISO" -volid NETHIX_LIVE \
    -b boot/grub/i386-pc/eltorito.img -no-emul-boot \
    "$WORK/iso-root" 

die_if_missing() { [[ -f "$OUT_ISO" ]] || die "ISO output missing"; }
die_if_missing
say "done: $OUT_ISO"
