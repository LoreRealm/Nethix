# Nethix TODO

Living tracker. The scheduled watchdog reviews this each run and
implements the top item if it's small/safe; big items get broken down.
Move done items to the bottom section, don't delete (history matters).

## Open

- [ ] Rework fetch-cachy-patches.sh: parse CachyOS PKGBUILD source=() array for patch URLs (they use EEVDF/sched_ext now, not a fixed bore patch), and pull their `config` file as the kernel config base
- [ ] USE flag UI: graphical interface in cantrip-install (or a `cantrip-use` command) for viewing/deciding USE flags per package with descriptions and presets (desktop/gaming/minimal)
- [ ] Implement `cantrip-update` (emerge -uDN @world wrapper + report)
- [ ] Implement `cantrip-kernel` (rebuild nethix-sources + reinstall)
- [ ] Live ISO pipeline: catalyst config or squashfs script, Plasma autostart of cantrip-install
- [ ] Binhost workflow: confirm it produces usable Packages index, publish as release asset
- [ ] hwdetect: real pci.ids database instead of coarse vendor guesses
- [ ] First boot test in a VM (needs ISO)
- [ ] Wire CredentialBundle/argon2 password hashing end-to-end (GUI currently stages plaintext via pkexec path — document + harden)
- [ ] Stream exec output into the GUI Running step
- [ ] scri: download + scan actual PKGBUILD build()/package() bodies in risk.rs (currently metadata-only)
- [ ] scri: interactive TTY review confirm (install currently requires --yes)
- [ ] scri: real Arch→Gentoo dep mapping database (fallback_map is a stub)
- [ ] License decision before public release (GPL-3 recommended, Gentoo-derived)

## Done

- [x] Scaffold repo: overlay, installer workspace, binhost, CI (2026-11-24)
- [x] cantrip-hwdetect: PCI scan + VIDEO_CARDS output (2026-11-24)
- [x] cantrip-install GUI: multi-step, plan serialization, iced 0.13 green (2026-11-24)
- [x] Fix CI compile errors x3 rounds (2026-11-24)
- [x] unpack_stage3: real download + sha512 verify + untar (2026-11-24)
- [x] User provisioning in populate(): useradd + chpasswd + groups (2026-11-24)
- [x] Stage profiles+overlay for exec backend (cantrip-stage, 2026-11-24)
- [x] Hourly ci-watchdog workflow filing issues on failure (2026-11-24)
- [x] scri: AUR bridge skeleton — RPC client, risk scanner, PKGBUILD→ebuild converter (2026-11-24)
- [x] README rewrite: feature/status tables (2026-11-24)
