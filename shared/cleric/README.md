# cleric

A universal system doctor for any Linux distro. It examines logs, services,
filesystems, package managers and session health; diagnoses problems;
applies safe fixes (opt-in per category); and files a GitHub issue for
anything it can't fix, with logs scrubbed of usernames/hostnames.

## Usage

    cleric                     full scan of EVERYTHING (diagnose only)
    cleric --fix               apply safe fixes (asks first)
    cleric --fix --yes         non-interactive auto-fix (cron/scheduled)
    cleric --report            diagnose only + print issue drafts
    cleric --category <name>   run a single category (boot, fs, keyring, ...)
    cleric --list              list available check categories

## Install

    sudo ./install.sh          # cleric -> /usr/local/bin, spells -> /usr/local/lib/cleric.d

Or run in place: `./cleric` from the repo root.

## Spells

Spells are pluggable: drop a new `*.sh` into `cleric.d/` and it's
automatically part of "everything" — no registration. Each spell declares:

    NAME="category"
    DESCRIPTION="one line"
    REQUIRES="tool1 tool2"     # optional: spell skipped if a tool is missing
    run_check()                # sets SEVERITY=ok|warn|fail and FINDINGS
    try_fix()                  # optional, safe fixes only
### Built-in spells

Universal (run on any distro, degrading gracefully when a tool is absent):
- `boot` — failed units (systemd + OpenRC fallback), kernel image/modules,
  boot-time journal errors
- `fs` — disk space (>=90% full), btrfs device stats (btrfs roots only)
- `keyring` — keyring/wallet daemon presence + secret-tool round-trip
- `wm` — compositor crash-loop detection (journald or /var/log fallback)
- `update` — reboot-required hints, running vs newest kernel staleness
- `storage` — SMART health, degraded mdraid, inactive LVM volumes

Package-manager families (auto-skip on other distros via `REQUIRES`):
- `portage` — Gentoo/Nethix: make.conf syntax, @world resolution, binhost index
- `pacman` — Arch/CachyOS/EndeavourOS/Manjaro: db lock, db sanity, keyring
- `apt` — Debian/Ubuntu/Mint/Pop!_OS: dpkg audit, stale locks, broken deps
- `dnf` — Fedora/RHEL (plus zypper fallback): rpm db, stale lock, dep check

On a given machine only the spells matching that distro actually run; the
rest are skipped with a notice. A bare `cleric` scan covers every family
without erroring anywhere.

## Safety rules

- `run_check()` is read-only — no side effects.
- `try_fix()` must be safe unattended under `cleric --fix --yes`.
  Anything that kills a session or destroys data belongs in no spell.
- Per-category opt-out: set `SAFE_FIXES` in `/etc/cleric.conf`.

## Configuration

Copy `cleric.conf.example` to `/etc/cleric.conf`:

    GITHUB_REPO="LoreRealm/Nethix"   # where unfixable issues get filed
    SCRUB_USERNAMES="yes"
    SAFE_FIXES=""                     # empty = all spells may fix

Root is recommended for a full scan (journal access, smartctl, package dbs);
non-root runs a reduced read-only scan.

## License

MIT
