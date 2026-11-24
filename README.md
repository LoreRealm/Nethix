# Nethix Artifacts

Built binaries and packages for the Nethix distro, published as release
assets so the main repo (LoreRealm/nethix) doesn't carry build outputs.

## Contents (over time)

- `nethix-installer-binaries.zip` — summon, summon-exec, forge, scri
  (published by the main repo's `build-installer` workflow on green builds)
- binhost packages (planned — `binhost/` output)
- kernel tarball mirrors (planned, if pinning here beats re-downloading)

## How binaries get here

The main repo's CI, on a successful build, uploads a zipped set of
release binaries to a `latest` release in this repo. Consumers (the ISO
builder, users) then fetch:

    https://github.com/LoreRealm/nethix-artifacts/releases/latest/download/nethix-installer-binaries.zip
