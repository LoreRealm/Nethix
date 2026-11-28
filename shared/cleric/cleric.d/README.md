# cleric.d/ — spell directory for the cleric system doctor.

Each `*.sh` here is one diagnostic category, sourced by `cleric`.
A spell defines:

    NAME="category"          # single word, matches --category and SAFE_FIXES
    DESCRIPTION="..."         # one line, shown by `cleric --list`
    REQUIRES="tool ..."      # OPTIONAL. space-separated; the spell is
                             # skipped (not errored) if any tool is missing.
                             # This is how distro-specific spells go universal:
                             # REQUIRES="emerge portageq" = Gentoo-only.
    run_check()               # sets SEVERITY=ok|warn|fail and FINDINGS="..."
    try_fix()                 # OPTIONAL. returns 0 if a SAFE fix was applied.

Rules:
- try_fix() must be safe to run unattended under `cleric --fix --yes`.
  Anything that kills a session, scrubs a disk, or rewrites user data
  belongs in NO spell — report it instead.
- Read-only probing in run_check(); no side effects.
- New categories: drop a file here, no registration needed. `cleric` picks
  up every .sh automatically — bare `cleric` scans ALL of them.
- Try to make spells universal: gate on REQUIRES and fall back gracefully
  (e.g. probe journald if present, skip log scan otherwise).
