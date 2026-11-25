# Nethix

Nethix is a **Gentoo-based Linux distribution** pairing Gentoo's source flexibility with CachyOS-style ergonomics: a performance-tuned EEVDF kernel, prebuilt binhost packages, a real graphical installer, and a coherent set of first-party tools.

**Status: pre-alpha.** Rust workspace compiles green; nothing has booted on real hardware yet. See [TODO.md](TODO.md).

> *Built artifacts (installer binaries, ISO builds, binhost output) live in [nethix-artifacts](https://github.com/LoreRealm/nethix-artifacts).*

---

## Components

| Name | Role | State |
|---|---|---|
| **Summon** (`installer/summon`) | GUI installer (Plasma 6 default) — partitions, stage3, chroot, kernel, user | ⚠️ logic complete, untested on disk |
| **Forge** (`installer/forge`) | Hardware detection (chwd-style) — PCI scan → VIDEO_CARDS/drivers/firmware | ⚠️ working prototype, coarse mapping |
| **Scri** (`installer/scri`) | AUR bridge — search/review/build PKGBUILDs via ephemeral ebuilds | ⚠️ skeleton, PKGBUILD-body scan pending |
| **Spire** (`installer/spire`) | GUI app store — Flatpak + Scri backends in one storefront | 🚧 skeleton |
| `cantrip-*` (`scripts/`) | First-party CLI utilities — stage, exec wrappers, update helpers | 🚧 growing |

### Support pieces

| Piece | What it does | State |
|---|---|---|
| `overlay/` — `nethix-sources` | Kernel ebuild w/ CachyOS EEVDF patchset + config | ⚠️ patches fetched, unverified build |
| `profiles.d/` | x86-64-v3/v4 tuned make.conf + binrepos.conf | ✅ ready |
| `binhost/` | Curated Plasma desktop binary set, nightly CI build | ⚠️ untested end-to-end |
| `iso/` | Live ISO builder (Plasma + Summon autostart) + QEMU test script | 🚧 first bring-up |
| `configs/fastfetch/` | Themed fastfetch config | ✅ shipped |

Legend: ✅ works · ⚠️ written but unvalidated · 🚧 planned/in-progress

## Fastfetch

The live ISO ships a themed fastfetch config (in `configs/fastfetch/`), so a fresh boot greets you with system info in Nethix styling. Out of the box it displays the usual Linux fetch fields, themed to match the distro:

```
        uwu@VIctory        OS: Nethix x86_64 (pre-alpha)
      ┌──────────────┐     Kernel: Linux 7.3.6-cachyos (EEVDF, Cachy Sauce)
      │   ◢ Nethix   │     Uptime: 3 mins
      │   ascii art  │     Packages: 412 (portage)
      │   goes here  │     Shell: bash 5.3
      └──────────────┘     WM: niri (Wayland)
                           Terminal: ghostty
                           CPU: AMD Ryzen 9 7950X (32) @ 4.5GHz
                           GPU: AMD Radeon RX 7900 XTX
                           Memory: 2.1 GiB / 32 GiB
```

The config is a plain `neofetch`-style jsonc — colors, separator, and module list are all standard fastfetch options, so it's trivially portable to a normal fastfetch install:

```bash
fastfetch --config configs/fastfetch/nethix.jsonc
```

## Quickstart

```bash
# rust workspace
cd installer && cargo build --release && cargo test

# pin cachyos kernel patches (pick the version they currently ship)
./scripts/fetch-cachy-patches.sh 7.3

# build the live ISO (root, takes hours first run)
sudo ./iso/build.sh

# boot-test it in QEMU
./iso/test-local.sh nethix-live-alpha.iso
```

## Design decisions

- **Init: systemd.** CachyOS parity, Plasma 6 upstream default, stage3 is systemd-flavored. Gentoo-ness is preserved via portage/USE flags/overlays.
- **Bootloader: Limine** (default, init-agnostic, themeable) with systemd-boot as an install-time option.
- **Packages: not a fork.** Everything resolves against `::gentoo` + GURU. Scri adds AUR reach without redistribution (read-only review, local builds through portage's sandbox).
- **Hardware detection: automatic.** Forge runs on first boot and before install, emitting USE-relevant make.conf snippets.

## CI

- `build-installer` — tests + builds all crates on push, publishes binaries to nethix-artifacts
- `ci-watchdog` — hourly build; files an issue on failure (permissions: issues: write)
- `build-binhost` — nightly binhost attempt in a stage3 container
- Dependabot — weekly cargo + actions updates

## License

Nethix is licensed under [GPL-3.0](LICENSE) — the same copyleft family as Gentoo's portage tooling and the kernel sources it builds on. Anyone is free to use, modify, and redistribute Nethix and its tools, provided derivative works stay under GPL-3.0 with sources shared.
