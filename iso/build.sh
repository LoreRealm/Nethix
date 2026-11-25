#!/usr/bin/env bash
# build.sh — assemble the Nethix live ISO.
#
# Stages:
#   1. chroot prep (stage3 download, bind mounts, resolv.conf, locale)
#   2. overlay + profile injection
#   3. emerge live set (+ linux-firmware for hardware compatibility)
#   4. installer binaries — pulled from nethix-artifacts repo (public)
#   5. liveuser
#   6. kernel + initramfs via portage (kernel-build eclass + installkernel/dracut)
#   7. squashfs + xorriso into ISO
#   8. binhost export — collect built .tbz2 packages for reuse
#
# Requirements: ~35 GB free (firmware is chunky). Run from anywhere —
# needs root, relaunches itself via sudo or pkexec (pkexec survives
# broken /dev/pty states that break sudo password prompts).
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

# self-heal the executable bit (git checkouts from zip/other hosts can lose it)
chmod +x "$0" iso/charm-bar.sh 2>/dev/null || true

# Themed progress: pass PROGRESS=0 to disable the rune bar.
PROGRESS=${PROGRESS:-1}
CHARM_BAR="$REPO_ROOT/iso/charm-bar.sh"

# run_charm LABEL CMD... — wrap a chroot command's stderr in the rune bar
# when progress is enabled, else run it plainly.
run_charm() {
    local label=$1; shift
    if [[ $PROGRESS -eq 1 && -x $CHARM_BAR ]]; then
        "$@" 2>&1 | "$CHARM_BAR" "$label"
    else
        "$@" 2>&1
    fi
}

# Relaunch as root if invoked as a user: prefer sudo, fall back to pkexec
# (polkit GUI prompt — works even when /dev/pts is broken and sudo can't
# allocate a pty for its password prompt).
if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
        exec sudo "$0" "$@"
    elif command -v pkexec >/dev/null; then
        exec pkexec env HOME="$HOME" USER="$USER" DISPLAY="${DISPLAY:-}" \
             WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
             bash "$0" "$@"
    elif command -v sudo >/dev/null; then
        exec sudo "$0" "$@"   # interactive sudo; may fail on broken pty
    else
        printf '!! run as root (needs mounts for chroot); no sudo or pkexec found\n' >&2
        exit 1
    fi
fi

WORK="$REPO_ROOT/.iso-build"
STAGE3_URL=${STAGE3_URL:-https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/}
OUT_ISO=${OUT_ISO:-nethix-live-alpha.iso}
ARTIFACTS_REPO=${ARTIFACTS_REPO:-LoreRealm/nethix-artifacts}
ARTIFACTS_ASSET=${ARTIFACTS_ASSET:-nethix-installer-binaries.zip}
KERNEL_PV=${KERNEL_PV:-7.3.6}

say() { printf '\e[1;36m::\e[0m %s\n' "$*"; }
die() { printf '\e[1;31m!!\e[0m %s\n' "$*" >&2; exit 1; }

mkdir -p "$WORK"/root

# Hardware-adapted parallelism: prefer total cores, but leave room so a
# memory-hungry compile (LLVM-linked kernel) doesn't OOM the build host.
# Rough heuristic: 2 GiB RAM per compile job for this kernel config.
detect_makeopts() {
    local cores ram_gb jobs
    cores=$(nproc)
    if [[ -r /proc/meminfo ]]; then
        ram_gb=$(awk '/^MemTotal:/ {printf "%d", $2/1048576}' /proc/meminfo)
    else
        ram_gb=16
    fi
    # cap by RAM at ~1 job per 2 GiB, never exceed cores, minimum 2
    jobs=$(( ram_gb / 2 ))
    (( jobs > cores )) && jobs=$cores
    (( jobs < 2 )) && jobs=2
    printf '%s' "$jobs"
}
JOBS=$(detect_makeopts)
say "detected hardware: $(nproc) cores, using -j$JOBS for portage/kernel builds"

# Peel any stale mounts left by a previous crashed/killed build, deepest-first.
# Lazy+loop because stacked rbinds (dev/pts under dev) resist a single -R pass.
cleanup_mounts() {
    local tries=0 m
    while grep -q " $WORK/root" /proc/mounts; do
        while read -r m; do
            umount -l "$m" 2>/dev/null || true
        done < <(grep " $WORK/root" /proc/mounts | awk '{print $2}' | sort -r)
        tries=$((tries + 1))
        [[ $tries -gt 10 ]] && { say "WARN: mounts still present under $WORK/root:"; grep " $WORK/root" /proc/mounts; return 1; }
    done
    return 0
}
trap cleanup_mounts EXIT

if grep -q " $WORK/root" /proc/mounts; then
    say "cleaning stale mounts from a previous build..."
    cleanup_mounts || die "could not clear stale mounts — check 'grep iso-build /proc/mounts'"
fi

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
# Hardware-adapted + quiet build settings appended to the chroot make.conf:
# MAKEOPTS from detection above, quiet portage output (progress/errors only),
# and buildpkg so every emerged package also produces a reusable .tbz2 in
# /var/cache/binpkgs — harvested in stage 8 into binhost/.
cat >> "$WORK/root/etc/portage/make.conf" <<EOF

# --- injected by iso/build.sh (hardware detection + quiet output + binhost) ---
MAKEOPTS="-j$JOBS -l$JOBS"
EMERGE_DEFAULT_OPTS="--quiet-build=y --quiet-fail=y --verbose=n --ask=n"
FEATURES="buildpkg binpkg-multi-instance"
EOF
# fail fast on a broken make.conf instead of letting portage spew cryptic
# "bad substitution" errors halfway through the build
bash -n "$WORK/root/etc/portage/make.conf" \
    || die "make.conf has a shell syntax error — fix it before continuing"

# accept ~amd64 for the nethix kernel so emerge doesn't die on keyword mask
mkdir -p "$WORK/root/etc/portage/package.accept_keywords"
echo "sys-kernel/nethix-sources ~amd64" \
    > "$WORK/root/etc/portage/package.accept_keywords/nethix.conf"

# Pre-seed required USE flags so dependencies resolve without manual
# autounmask intervention. Necessary-for-the-build flags belong here, not
# in a human's hands at 4am.
mkdir -p "$WORK/root/etc/portage/package.use"
cat > "$WORK/root/etc/portage/package.use/nethix.conf" <<'EOF'
# nethix-sources[initramfs] requires dracut-capable installkernel
>=sys-kernel/installkernel-70-r1 dracut
# dracut is systemd-based on our live image
sys-kernel/dracut systemd
# linux-firmware: skip the redistributable-restricted blob splitting; the
# live image carries everything so hardware Just Works out of the box
sys-kernel/linux-firmware redistributable
EOF

# Distfiles cache: stage3 root's /var/cache may come out with odd perms
# (the __portage_test_write__ denial we saw). Ensure portage can write.
chmod 755 "$WORK/root/var/cache" "$WORK/root/var/cache/distfiles" 2>/dev/null || true

# --- 3. emerge live set (fastfetch + firmware for hardware compat)
say "emerging minimal live set + linux-firmware..."
run_charm "conjuring live set" chroot "$WORK/root" env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 /bin/bash -c '
    set -e
    emerge-webrsync || emerge --sync || true
    emerge --autounmask-write app-misc/fastfetch sys-kernel/linux-firmware
'
say "live set installed (firmware adds ~700MB to the squashfs — expected)"

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

# --- 6. kernel + initramfs — entirely via portage.
# nethix-sources inherits kernel-build; with USE=initramfs and
# installkernel[dracut] (pre-seeded in package.use above), the emerge
# itself compiles the kernel, installs vmlinuz + modules to /boot and
# /lib/modules, and generates the initramfs. The OLD manual `make` pass
# is GONE: running make on the installed /usr/src tree breaks because
# the installed tree is not a full build tree (missing generated awk
# tooling like cpufeaturemasks.awk — hence the previous
# "No rule to make target 'arch/x86/tools/cpufeaturemasks.awk'" failure).
say "installing kernel + initramfs via portage (kernel-build + dracut)..."

# The Manifest shipped in the repo is generated from a known-good download;
# refresh it inside the chroot so checksums always match reality before emerging.
chroot "$WORK/root" env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 bash -ec "
    cd /var/db/repos/nethix/sys-kernel/nethix-sources
    ebuild nethix-sources-$KERNEL_PV.ebuild manifest || true
"

run_charm "forging kernel" chroot "$WORK/root" env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    emerge --autounmask-write --autounmask-continue sys-kernel/nethix-sources

# initramfs: kernel-build + installkernel[dracut] should have generated it
# already; regenerate all as a belt-and-braces measure so /boot always has
# an initramfs matching the installed kernel even if the USE plumbing lags.
chroot "$WORK/root" env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 dracut --force --regenerate-all --hostonly=no \
    || die "dracut failed — initramfs missing"

# --- 7. squashfs + ISO
say "packing squashfs..."
mkdir -p "$WORK/iso-root"
mksquashfs "$WORK/root" "$WORK/iso-root/live.squashfs" -comp zstd -Xcompression-level 19 -processors "$JOBS"

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

# --- 8. binhost export
# buildpkg (set in make.conf) made portage drop a .tbz2 for every package
# it emerged into the chroot's /var/cache/binpkgs. Harvest those into a
# persistent, git-ignorable directory OUTSIDE .iso-build so the next build
# (or an installed Nethix system via PORTAGE_BINHOST) can reuse them without
# recompiling. Mirroring these to the nethix-artifacts repo as release
# assets turns it into a full binhost — see binhost/README there.
BINPKGS="$REPO_ROOT/binhost"
if compgen -G "$WORK/root/var/cache/binpkgs/**/*.tbz2" >/dev/null 2>&1; then
    say "exporting built packages to binhost/..."
    mkdir -p "$BINPKGS"
    cp -a "$WORK/root/var/cache/binpkgs/." "$BINPKGS/"
    say "binhost: $(find "$BINPKGS" -name '*.tbz2' | wc -l) packages in $BINPKGS"
else
    say "WARN: no binary packages were produced (FEATURES=buildpkg didn't fire?)"
fi

say "done: $REPO_ROOT/$OUT_ISO"
