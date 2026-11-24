ARTIFACTS_REPO=${ARTIFACTS_REPO:-LoreRealm/nethix-artifacts}

# --- 4. installer binaries: fetch from the artifacts repo's latest release
say "fetching installer binaries from $ARTIFACTS_REPO (latest release)..."
if curl -fsSL -o "$WORK/artifacts.zip" \
     "https://github.com/$ARTIFACTS_REPO/releases/latest/download/nethix-installer-binaries.zip"; then
    mkdir -p "$WORK/root/usr/local/bin"
    unzip -o -j "$WORK/artifacts.zip" '*/summon' '*/summon-exec' '*/forge' '*/scri' \
        -d "$WORK/root/usr/local/bin/" \
    || say "WARN: artifact zip unpacked but expected binaries missing — check the release contents"
else
    say "WARN: no release binaries in $ARTIFACTS_REPO yet — building ISO without the installer"
    say "      (publish via the build-installer workflow's artifacts-publish job)"
fi
