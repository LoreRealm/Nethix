#!/usr/bin/env bash
# build.sh — assemble the Nethix live ISO.
#
# Stages:
#   1. chroot prep (stage3 download, bind mounts, resolv.conf, locale)
#   2. overlay + profile injection
#   3. emerge live set
#   4. installer binaries — pulled from nethix-artifacts repo (public)
#   5. liveuser
#   6. kernel + initramfs (dracut) install to boot/
#   7. squashfs + xorriso into ISO
#
# Requirements: root, ~30 GB free. Run from anywhere.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

WORK="$REPO_ROOT/.iso-build"
STAGE3_URL=${STAGE3_URL:-https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/}
OUT_ISO=${OUT_ISO:-nethix-live-alpha.iso}
ARTIFACTS_REPO=${ARTIFACTS_REPO:-LoreRealm/nethix-artifacts}
ARTIFACTS_ASSET=${ARTIFACTS_ASSET:-nethix-installer-binaries.zip}
KERNEL_PV=${KERNEL_PV:-7.3.6}

say() { printf '\e[1;36m::\e[0m %s\n' "$*"; }
die() { printf '\e[1;31m!!\e[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (needs mounts for chroot)"

mkdir -p "$WORK"/root

# --- 1. stage3
say "fetching latest stage3 tarball..."
LATEST=$(curl -fsSL "$STAGE3_URL" | grep -oE 'stage3-amd64-systemd-[0-9.]+T[0-9]+Z\.tar\.xz' | sort -r | head -n1)
[[ -n "$LATEST" ]] || die "couldn't locate a stage3 tarball on the mirror"
curl -fL -o "$WORK/stage3.tar.xz" "$STAGE3_URL/$LATEST"

say "unpacking stage3..."
tar -xpf "$WORK/stage3.tar.xz" -C "$WORK/root" --xattrs --numeric-owner

cp -L /etc/resolv.conf "$WORK/root/etc/resolv.conf"
mkdir -p "$WORK/root"/var/db/repos/{nethix,gentoo} \
         "$WORK/root"/etc/portage/repos.conf \
         "$WORK/root"/var/cache/distfiles

# Bind-mount the virtual filesystems FIRST: locale-gen needs /proc/mounts,
# portage needs /proc, /sys and /dev for its builds. Everything chrooted
# below assumes they exist.
mount --bind /proc "$WORK/root/proc"
mount --bind /sys  "$WORK/root/sys"
mount --rbind /dev "$WORK/root/dev"
cleanup() {
    umount -R "$WORK/root/dev" 2>/dev/null || true
    umount "$WORK/root/proc" "$WORK/root/sys" 2>/dev/null || true
}
trap cleanup EXIT

# generate a working locale now so every later step stops whining about
# en_US.UTF-8 missing (stage3 ships with no locale compiled)
say "generating en_US.UTF-8 locale in the chroot..."
chroot "$WORK/root" /bin/bash -c '
    set -e
    grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
'

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
# fail fast on a broken make.conf instead of letting portage spew cryptic
# "bad substitution" errors halfway through the build
bash -n "$WORK/root/etc/portage/make.conf" \
    || die "make.conf has a shell syntax error — fix it before continuing"

# accept ~amd64 for the nethix kernel so emerge doesn't die on keyword mask
mkdir -p "$WORK/root/etc/portage/package.accept_keywords"
echo "sys-kernel/nethix-sources ~amd64" \
    > "$WORK/root/etc/portage/package.accept_keywords/nethix.conf"

# Distfiles cache: stage3 root's /var/cache may come out with odd perms
# (the __portage_test_write__ denial we saw). Ensure portage can write.
chmod 755 "$WORK/root/var/cache" "$WORK/root/var/cache/distfiles" 2>/dev/null || true

# --- 3. emerge minimal live set (alpha: no Plasma yet)
say "emerging minimal live set..."
chroot "$WORK/root" env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 /bin/bash -c '
    set -e
    emerge-webrsync || emerge --sync || true
    emerge --ask=n --autounmask-write app-misc/fastfetch || true
'

# --- 4. installer binaries from artifacts repo (public)
say "fetching installer binaries from $ARTIFACTS_REPO (latest release)..."
if curl -fsSL -o "$WORK/artifacts.zip" \
     "https://github.com/$ARTIFACTS_REPO/releases/latest/download/$ARTIFACTS_ASSET"; then
    mkdir -p "$WORK/root/usr/local/bin"
    if command -v unzip >/dev/null; then
        unzip -o -j "$WORK/artifacts.zip" -d "$WORK/root/usr/local/bin/" \
        || say "WARN: artifacts.zip downloaded but expected binaries not found inside"
    else
        # no unzip on the host (ubuntu runners don't ship it by default): python3 fallback
        python3 - "$WORK/artifacts.zip" "$WORK/root/usr/local/bin" <<'PY'
import os, sys, zipfile
zf, dest = sys.argv[1], sys.argv[2]
wanted = ("summon", "summon-exec", "forge", "scri")
with zipfile.ZipFile(zf) as z:
    for name in z.namelist():
        base = name.rstrip("/").rsplit("/", 1)[-1]
        if base in wanted:
            out = os.path.join(dest, base)
            with z.open(name) as src, open(out, "wb") as dst:
                dst.write(src.read())
            os.chmod(out, 0o755)
PY
    fi
else
    say "WARN: no release asset '$ARTIFACTS_ASSET' in $ARTIFACTS_REPO — ISO will lack the installer"
    say "WARN: run the publish-binaries workflow (or create the release) and rebuild"
fi

# --- 5. liveuser
say "creating liveuser..."
chroot "$WORK/root" env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 /bin/bash -c '
    set -e
    # Gentoo stage3 has no plugdev; use the groups it actually ships
    GROUPS_OK=""
    for g in wheel audio video tty usb cdrom; do
        getent group "$g" >/dev/null && GROUPS_OK+="$g,"
    done
    GROUPS_OK=${GROUPS_OK%,}
    useradd -m -G "$GROUPS_OK" -s /bin/bash liveuser
    echo "liveuser:liveuser" | chpasswd
'

# --- 6. kernel + initramfs
say "installing kernel + dracut initramfs..."

# The Manifest shipped in the repo is generated from a known-good download;
# refresh it inside the chroot so checksums always match reality before emerging.
chroot "$WORK/root" env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 bash -ec "
    cd /var/db/repos/nethix/sys-kernel/nethix-sources
    ebuild nethix-sources-$KERNEL_PV.ebuild manifest || true
"

chroot "$WORK/root" env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 /bin/bash -ec "
    emerge --ask=n sys-kernel/nethix-sources
    KDIR=\$(ls -d /usr/src/linux-* | sort -Vr | head -n1)
    echo \"building kernel in \$KDIR\"
    cd \"\$KDIR\"
    make olddefconfig
    make -j\$(nproc)
    make modules_install
    INSTALL_PATH=/boot make install
"
chroot "$WORK/root" env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 dracut --force --regenerate-all --hostonly=no \
    || die "dracut failed — initramfs missing"

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
# grub config lives INSIDE the chroot where grub-mkstandalone expects it
mkdir -p "$WORK/root/boot/grub"
cat > "$WORK/root/boot/grub/grub.cfg" <<'EOF'
set timeout=5
menuentry "Nethix Live" {
    linux /vmlinuz root=live:CDLABEL=NETHIX_LIVE rd.live.image rd.live.squashimg=live.squashfs
    initrd /initramfs.img
}
EOF
cp "$WORK/root/boot/grub/grub.cfg" "$WORK/iso-root/grub-live.cfg"

chroot "$WORK/root" grub-mkstandalone \
    -O x86_64-efi -o /tmp/nethix-efi.img \
    "boot/grub/grub.cfg=/boot/grub/grub.cfg" \
|| die "grub-mkstandalone EFI failed (is sys-boot/grub emerged in the chroot?)"
chroot "$WORK/root" grub-mkstandalone \
    -O i386-pc -o /tmp/nethix-bios.img \
    "boot/grub/grub.cfg=/boot/grub/grub.cfg" \
|| die "grub-mkstandalone BIOS failed"
cp "$WORK/root/tmp/nethix-efi.img" "$WORK/iso-root/efi-boot.img"
cp "$WORK/root/tmp/nethix-bios.img" "$WORK/iso-root/bios-boot.img"

xorriso -as mkisofs -iso-level 3 -volid NETHIX_LIVE \
    -graft-points \
    -o "$REPO_ROOT/$OUT_ISO" \
    -b bios-boot.img -no-emul-boot \
    --efi-boot efi-boot.img \
    /vmlinuz="$WORK/iso-root/vmlinuz" \
    /initramfs.img="$WORK/iso-root/initramfs.img" \
    /live.squashfs="$WORK/iso-root/live.squashfs" \
    /grub-live.cfg="$WORK/iso-root/grub-live.cfg" \
    /efi-boot.img="$WORK/iso-root/efi-boot.img" \
    /bios-boot.img="$WORK/iso-root/bios-boot.img"

[[ -f "$REPO_ROOT/$OUT_ISO" ]] || die "ISO output missing"
say "done: $REPO_ROOT/$OUT_ISO"
