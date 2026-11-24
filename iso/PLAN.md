# Nethix Build Pipeline (ISO) — plan
#
# Goal: produce a bootable amd64 UEFI live ISO containing:
#   - Plasma 6 minimal session, autologin kiosk
#   - summon (GUI installer), summon-exec, forge
#   - the nethix overlay + cantrip-stage wiring pre-baked
#   - fastfetch + pathfinder config
#
# Approach: gentoo stage3 in a container (podman/docker), build binary
# packages for the live set via our binhost scripts, assemble squashfs,
# xorriso into an ISO with limine GRUB2 hybrid boot.
#
# Phase 1 (this directory):
#   - stage-spec: packages + services + files in the live root
#   - build.sh: orchestrates stage3 -> live root -> squashfs -> ISO
#   - runtime autologin: Plasma kiosk user "liveuser"
#
# Known gaps: kernel = our nethix-sources (needs pinned patches first),
# firmware set for broad hardware coverage, dracut initramfs config.
