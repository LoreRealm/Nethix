Bootstrap and maintenance scripts for Nethix.

- fetch-cachy-patches.sh — pin CachyOS kernel patches for a given version
- bootstrap-portage.sh — wire the nethix overlay into a stage3 chroot
- cantrip-stage.sh — stage profiles/overlay for the summon exec backend
- summon-exec.sh — privileged installer entry point (consumes summon's plan)
- forge.sh — wrapper around the forge hardware-detect binary
- build-binhost.sh — build the curated Plasma binhost set (CI or local)
