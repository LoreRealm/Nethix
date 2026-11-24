# Nethix

Nethix is a **Gentoo-based Linux distribution** pairing Gentoo's source flexibility with CachyOS-style ergonomics: a performance-tuned EEVDF kernel, prebuilt binhost packages, a real graphical installer, and a tool suite that feels like a small adventuring party.

**Status: pre-alpha.** Rust workspace compiles green; nothing has booted on real hardware yet. See [TODO.md](TODO.md).

> *Built artifacts (installer binaries, ISO builds, binhost output) live in [nethix-artifacts](https://github.com/LoreRealm/nethix-artifacts).*

---

## The Party

| Name | Role | State |
|---|---|---|
| **Summon** (`installer/summon`) | GUI installer (Plasma 6 default) — partitions, stage3, chroot, kernel, user | ⚠️ logic complete, untested on disk |
| **Forge** (`installer/forge`) | Hardware detection (chwd-style) — PCI scan → VIDEO_CARDS/drivers/firmware | ⚠️ working prototype, coarse mapping |
| **Scri** (`installer/scri`) | AUR bridge — search/review/build PKGBUILDs via ephemeral ebuilds | ⚠️ skeleton, PKGBUILD-body scan pending |
| **Spire** (`installer/spire`) | GUI app store — Flatpak + Scri backends in one storefront | 🚧 skeleton |
| `cantrip-*` (`scripts/`) | Utility spells — stage, exec wrappers, update helpers | 🚧 growing |

### Supporting cast

| Piece | What it does | State |
|---|---|---|
| `overlay/` — `nethix-sources` | Kernel ebuild w/ CachyOS EEVDF patchset + config | ⚠️ patches fetched, unverified build |
| `profiles.d/` | x86-64-v3/v4 tuned make.conf + binrepos.conf | ✅ ready |
| `binhost/` | Curated Plasma desktop binary set, nightly CI build | ⚠️ untested end-to-end |
| `iso/` | Live ISO builder (Plasma + Summon autostart) + QEMU test script | 🚧 first bring-up |
| `configs/fastfetch/` | Pathfinder-themed fastfetch config | ✅ shipped |

Legend: ✅ works · ⚠️ written but unvalidated · 🚧 planned/in-progress

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

Undecided (GPL-3 recommended before public release — Gentoo/kernel-derived). Private until then.
