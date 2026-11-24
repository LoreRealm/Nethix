# Nethix TODO

Living tracker. The scheduled watchdog reviews this each run and
implements the top item if it's small/safe; big items get broken down.
Move done items to the bottom section, don't delete (history matters).

## Open

- [ ] Spire: GUI app store (iced) — flatpaks + scri/AUR backend in one interface; Bazaar-style browsing; scri becomes its CLI engine
- [ ] cantrip-update: interactive TUI updater (preview -uDN @world, per-block confirm, binhost-aware, never interrupt emerge mid-transaction)
- [ ] Rework fetch-cachy-patches.sh: parse CachyOS PKGBUILD source=() array for patch URLs (EEVDF era, no fixed bore patch), pull their `config` as kernel config base
- [ ] USE flag UI: graphical/interactive interface for viewing/deciding USE flags per package with descriptions and presets (desktop/gaming/minimal) — integrate into Spire or summon
- [ ] Implement `cantrip-kernel` (rebuild nethix-sources + reinstall)
- [ ] Live ISO pipeline: catalyst config or squashfs script, Plasma autostart of summon
- [ ] Binhost workflow: confirm it produces usable Packages index, publish as release asset
- [ ] forge: real pci.ids database instead of coarse vendor guesses
- [ ] First boot test in a VM (needs ISO)
- [ ] Wire CredentialBundle/argon2 password hashing end-to-end (GUI currently stages plaintext via pkexec path — document + harden)
- [ ] Stream exec output into the summon Running step
- [ ] scri: download + scan actual PKGBUILD build()/package() bodies in risk.rs (currently metadata-only)
- [ ] scri: interactive TTY review confirm (install currently requires --yes)
- [ ] scri: real Arch→Gentoo dep mapping database (fallback_map is a stub)
- [ ] License decision before public release (GPL-3 recommended, Gentoo-derived)

## Done

- [x] Rename: summon (GUI installer), forge (hw-detect) — taxonomy: cantrip-* utilities, summon install ritual, forge shapes hardware (2026-11-24)
- [x] scri: AUR bridge skeleton — RPC client, risk scanner, PKGBUILD→ebuild converter (2026-11-24)
- [x] README rewrite: feature/status tables (2026-11-24)
- [x] Scaffold repo: overlay, installer workspace, binhost, CI (2026-11-24)
- [x] forge (was cantrip-hwdetect): PCI scan + VIDEO_CARDS output (2026-11-24)
- [x] summon (was cantrip-install) GUI: multi-step, plan serialization, iced 0.13 green (2026-11-24)
- [x] Fix CI compile errors x3 rounds (2026-11-24)
- [x] unpack_stage3: real download + sha512 verify + untar (2026-11-24)
- [x] User provisioning in populate(): useradd + chpasswd + groups (2026-11-24)
- [x] Stage profiles+overlay for exec backend (cantrip-stage, 2026-11-24)
- [x] Hourly ci-watchdog workflow filing issues on failure (2026-11-24)
