<div align="center">

```
██   ██           ██    ██         ██
███  ██▒          ██▒   ██▒         ▒▒
████ ██▒ █████  ███████ ██████   ████   ███ ███
██▒████▒██▒▒▒██  ▒██▒▒▒▒██▒▒▒██   ▒██▒   █████▒▒
██▒ ███▒███████▒  ██▒   ██▒  ██▒   ██▒    ███▒▒
██▒  ██▒██▒▒▒▒▒▒  ██▒   ██▒  ██▒   ██▒   █████
██▒  ██▒ █████    █████ ██▒  ██▒███████ ███▒███
 ▒▒   ▒▒  ▒▒▒▒▒    ▒▒▒▒▒ ▒▒   ▒▒ ▒▒▒▒▒▒▒ ▒▒▒ ▒▒▒
```

**A Gentoo distribution with CachyOS ergonomics — forged, not forked.**

Performance-tuned kernel · prebuilt Plasma binhost · graphical installer · automatic hardware detection

[![build](https://img.shields.io/badge/CI-build--installer-informational)](https://github.com/LoreRealm/nethix/actions)
[![status](https://imgields.io/badge/status-pre--alpha-orange)](TODO.md)
[![init](https://img.shields.io/badge/init-systemd-blue)](TODO.md)
[![bootloader](https://img.shields.io/badge/bootloader-limine%20%7C%20sd--boot-blueviolet)](TODO.md)
[![base](https://img.shields.io/badge/base-Gentoo-5c5cff)](https://www.gentoo.org)

</div>

---

## Overview

Nethix is **not** a package fork. Everything resolves against `::gentoo` + GURU. Nethix adds the ergonomics layer Gentoo lacks out of the box: a tuned kernel, prebuilt binaries for common desktops, a real graphical installer, and tools that respect the source-based heritage.

## Components

| Component | Path | Role |
|---|---|---|
| **Summon** | `installer/summon` | Graphical installer (iced 0.14). Partition → stage3 → chroot → Plasma 6 → bootloader. Ships `summon-exec` for the privileged half. |
| **Forge** | `installer/forge` | Hardware detection (chwd-style). Scans sysfs PCI devices, emits `VIDEO_CARDS`/`INPUT_DEVICES` make.conf. |
| **Scri** | `installer/scri` | AUR bridge. RPC search, risk report, PKGBUILD→ebuild conversion, read-only review, builds through portage's sandbox. Also Spire's engine library. |
| **Spire** | `installer/spire` *(planned)* | App store GUI: flatpaks + AUR in one interface. |
| Overlay | `overlay/` | `nethix-sources` kernel ebuild — EEVDF/Cachy patchset, hermetic (patches committed). |
| Binhost | `binhost/` | Curated Plasma desktop set, built nightly in CI, consumed via `binrepos.conf`. |
| Utilities | `scripts/cantrip-*` | `cantrip-update` (interactive world update), `cantrip-kernel` (rebuild + reinstall), staging + bootstrap helpers. |
| Theming | `configs/fastfetch/` | Default fastfetch configuration. |

## Status

Pre-alpha. The code compiles and CI is green; nothing has booted on real hardware yet. Per-feature status:

| Feature | State |
|---|---|
| Tuned kernel (EEVDF/Cachy patchset) | patch URLs unverified |
| x86-64-v3/v4 profiles | ready |
| Curated Plasma binhost | untested end-to-end |
| Summon (GUI installer) | logic complete, untested on disk |
| Forge (hardware detection) | prototype, coarse mapping (pci.ids TODO) |
| Scri (AUR bridge) | engine complete; PKGBUILD-body scanning TODO |
| Live ISO | planned — the current milestone |

Full breakdown and history in [TODO.md](TODO.md).

## Build & Development

```bash
cd installer
cargo build --release
cargo test
```

CI: `build-installer` (push), `ci-watchdog` (hourly, files an issue on failure), `build-binhost` (nightly), Dependabot (cargo + actions, weekly).

## System Layout (installed)

```
summon                # graphical installer (Plasma live session)
summon-exec           # privileged install executor
forge                 # hardware detection → /etc/portage/make.conf
scri search|review|install <pkg>
cantrip-update        # interactive world update
score // TODO cantrip-kernel          # rebuild + reinstall nethix-sources
cantrip-stage         # stage profiles/overlay pre-install
```

## Roadmap

- **Now:** live ISO → first VM boot test
- **Next:** Spire app store · USE-flag chooser · Limine bootloader default
- **Later:** PKGBUILD-body risk scanning · pci.ids-driven Forge · hardened credential staging

## License

Unchosen (repo is private). GPL-3 foreseen before any public release — Gentoo- and kernel-derived lineage.
