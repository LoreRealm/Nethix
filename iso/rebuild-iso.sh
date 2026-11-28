#!/usr/bin/env bash
# Rebuild the bootable ISO from a prepared .iso-build working tree.
#
# Learned the hard way during the 28 Nov boot-debugging session:
#  - The hand-made mtools esp.img (dd + mformat + mcopy + grub-mkimage) is
#    BROKEN: grub can't find its config (prefix mismatch) and lands in a
#    rescue shell. Do not hand-build the ESP.
#  - The GOOD images are the originals produced by grub-mkstandalone in the
#    full build: bios-boot.img (152K, i386-pc) and efi-boot.img (16M,
#    x86_64-efi). If the ISO won't boot, copy efi-boot.img over esp.img —
#    a half-baked esp.img in iso-root is the usual culprit.
#  - Regenerating grub-mkstandalone in a reused chroot fails with
#    'core image is too big (0xNNNN > 0x78000)'. Only regenerate boot images
#    in a FRESH chroot produced by iso/build.sh.
#
set -euo pipefail

BASE=/home/$SUDO_USER/Downloads/Nethix/.iso-build
ROOT=$BASE/root
ISO=$BASE/iso-root
OUT=/home/$SUDO_USER/Downloads/Nethix/nethix-live-alpha.iso

[[ $EUID -eq 0 ]] || { echo 'run as root: sudo ./iso/rebuild-iso.sh'; exit 1; }
[[ -d $ISO ]] || { echo "no iso-root at $ISO — run iso/build.sh first"; exit 1; }

if [[ -f $ISO/efi-boot.img && -f $ISO/bios-boot.img ]]; then
    cp -f $ISO/efi-boot.img $ISO/esp.img
    echo ':: restored known-good efi-boot.img -> esp.img'
else
    echo '!! efi-boot.img/bios-boot.img missing from iso-root' >&2
    echo '!! regenerate via a full iso/build.sh run (mkstandalone needs a fresh chroot)' >&2
    exit 1
fi

xorriso -as mkisofs -iso-level 3 -r -volid NETHIX_LIVE -o "$OUT" \
    -b bios-boot.img -no-emul-boot -boot-info-table -boot-load-size 4 \
    -eltorito-alt-boot -e esp.img -no-emul-boot \
    "$ISO"

echo ":: done: $OUT"

# Serial-boot test with timestamped log:
#   pkill qemu-system; sleep 2; qemu-system-x86_64 -enable-kvm -machine q35 -m 8192 \
#     -drive if=pflash,format=raw,readonly=on,file=/tmp/OVMF_CODE.fd \
#     -drive if=pflash,format=raw,file=/tmp/OVMF_VARS.fd \
#     -drive file=$OUT,format=raw,if=virtio,readonly=on \
#     -serial "file:/tmp/nethix-serial-$(date +%Y%m%d-%H%M%S).log" &
# Readable tail (ANSI-free, kernel timestamps only):
#   LOG=$(command ls -t /tmp/nethix-serial-*.log | head -1) && grep -a '^[[]' "$LOG" | tail -40
