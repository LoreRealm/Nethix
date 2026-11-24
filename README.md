# Nethix

Nethix is a **Gentoo-based Linux distribution** that pairs Gentoo's source-based flexibility with CachyOS-style ergonomics: a performance-tuned kernel, prebuilt binaries for common desktops, and a real graphical installer.

**Status: pre-alpha.** Compiles green, nothing has booted on real hardware yet. See [TODO.md](TODO.md) for the exact breakdown.

---

## What it is (and isn't)

Nethix is **not** a package fork. Everything resolves against `::gentoo` + GURU. What we add is:

| Feature | Component | State |
|---|---|---|
| Tuned kernel (BORE/Cachy patchset) | `overlay/sys-kernel/nethix-sources` | ⚠️ patch URLs unverified |
| x86-64-v3/v4 tuned profiles | `profiles.d/makeconf.*` | ✅ ready |
| Curated binhost (Plasma desktop set) | `binhost/` + nightly CI | ⚠️ untested end-to-end |
| GUI installer (Plasma 6 default) | `installer/cantrip-install` | ⚠️ logic complete, untested on disk |
| Automatic hardware detection (chwd-style) | `installer/cantrip-hwdetect` | ⚠️ working prototype, coarse mapping |
| AUR bridge: search/review/build PKGBUILDs | `installer/scri` | ⚠️ skeleton, no PKGBUILD-body scanning yet |
| Built-in command suite (`cantrip-*`) | `scripts/` | 🚧 growing |

Legend: ✅ works · ⚠️ written but unvalidated · 🚧 planned

## Components

### `cantrip-install`
Graphical installer (iced). Steps: welcome → disk target → account → confirm → install. Serializes an `InstallPlan` (TOML) consumed by the privileged `cantrip-install-exec` binary, which partitions (UEFI+GPT or BIOS), formats (btrfs+zstd with @/@home subvolumes, or ext4), unpacks a checksum-verified stage3, chroots into it, installs Plasma 6 + kernel + bootloader, and provisions the user.

### `cantrip-hwdetect`
Scans `/sys/bus/pci/devices`, maps vendor/class to `VIDEO_CARDS`, `INPUT_DEVICES`, suggested drivers and firmware — emitted as a make.conf snippet. Rough vendor-level mapping today; pci.ids-driven precision is on the TODO.

### `scri`
AUR bridge for Nethix. Searches the AUR RPC, generates an ephemeral ebuild from a PKGBUILD, shows a **risk report** (orphans, new packages, low votes, suspicious bash patterns), then builds through portage's sandbox in a scratch overlay. Design constraints: review is **read-only** (no user-edited ebuilds), nothing is **redistributed** (PKGBUILDs fetched locally at install time).

### `overlay/`
Nethix portage overlay: `nethix-sources` kernel ebuild, hermetic (patches fetched once and committed, no build-time network). Populate with `scripts/fetch-cachy-patches.sh <ver>`.

### `binhost/`
Curated Plasma desktop binary set built nightly in CI. Consumed via `profiles.d/binrepos.conf`.

## Scripts (`scripts/`)

| Script | Purpose |
|---|---|
| `fetch-cachy-patches.sh` | pin CachyOS kernel patches for a version into the overlay |
| `bootstrap-portage.sh` | wire overlay + tuned make.conf into a stage3 chroot |
| `cantrip-stage.sh` | stage profiles/overlay/flavor into `/var/lib/nethix` before install |
| `cantrip-install-exec.sh` | privileged entry point driving the full install |
| `build-binhost.sh` | build the curated set into `out/` (CI or local) |

## Roadmap

Tracked in [TODO.md](TODO.md). The watchdog (scheduled task + `ci-watchdog` workflow) reviews it and implements items incrementally.

Highlights:
- **Live ISO** — boots to Plasma, autostarts `cantrip-install` (the gating item for real testing)
- `cantrip-update`, `cantrip-kernel` commands
- Verify kernel patch URLs + first VM boot test
- Full AUR PKGBUILD-body risk scanning in `scri`

## Development

Rust workspace under `installer/`:

```bash
cd installer
cargo build --release
cargo test
```

CI: `build-installer` (push, tests+builds), `ci-watchdog` (hourly, files an issue on failure), `build-binhost` (nightly).

Kernel maintenance:

```bash
./scripts/fetch-cachy-patches.sh 6.12.0   # then commit the files/ dir
```

## License

Not yet chosen. Before public release, GPL-3 is the likely fit (Gentoo- and kernel-derived). Private until then.
