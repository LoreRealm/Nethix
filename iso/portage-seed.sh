#!/usr/bin/env bash
# portage-seed.sh — the ONE place chroot portage config is defined.
#
# Writes make.conf extras, accept_keywords, USE flags, and license
# acceptance into a target root. Used by BOTH iso/build.sh (real chroot)
# and CI preflight (.github/workflows/portage-preflight.yml) so the two
# can never drift — a mask failure caught in CI is guaranteed fixed
# locally too, and vice versa.
#
# Usage: portage-seed.sh TARGET_ROOT JOBS [BINHOST_DIR]
#   BINHOST_DIR (optional): path to a directory of previously built
#   .tbz2 packages + Packages index (the binhost/ output of a previous
#   iso/build.sh run). When provided, portage installs from these
#   instead of recompiling — LLVM/clang/kernel toolchain that took 40+
#   minutes to compile land as prebuilts in seconds. Portage falls back
#   to source compilation for anything missing or mismatched.
set -euo pipefail

ROOT=${1:?usage: portage-seed.sh TARGET_ROOT JOBS [BINHOST_DIR]}
JOBS=${2:-$(nproc)}
BINHOST_DIR=${3:-}

LICENSE_POLICY="* -@EULA"   # all licenses accepted incl. redistributable; EULAs still explicit
KEYWORD_POLICY="*/* ~amd64" # whole-tree testing keywords (distro pins ~amd64 by design)

mkdir -p "$ROOT"/etc/portage/{package.accept_keywords,package.use,package.license,repos.conf}

# --- make.conf additions (appended; caller owns the base make.conf) ---
{
cat >> "$ROOT/etc/portage/make.conf" <<EOF

# --- injected by portage-seed.sh (shared by iso/build.sh and CI preflight) ---
ACCEPT_LICENSE="$LICENSE_POLICY"
MAKEOPTS="-j$JOBS -l$JOBS"
EMERGE_DEFAULT_OPTS="--quiet-build=y --quiet-fail=y --verbose=n --ask=n"
FEATURES="buildpkg binpkg-multi-instance"
EOF

# --- binhost reuse: point portage at previously built packages ---
if [[ -n "$BINHOST_DIR" && -d "$BINHOST_DIR" ]]; then
    cat >> "$ROOT/etc/portage/make.conf" <<EOF

# --- binhost reuse (seeded from $BINHOST_DIR) ---
# Reuse packages from a previous build instead of recompiling; portage
# still verifies USE/ABI compatibility and falls back to source builds
# for mismatches.
PORTAGE_BINHOST="$BINHOST_DIR"
FEATURES="\${FEATURES} getbinpkg"
EMERGE_DEFAULT_OPTS="\${EMERGE_DEFAULT_OPTS} --usepkg --binpkg-respect-use=y"
EOF
    echo ":: binhost reuse enabled from $BINHOST_DIR"
else
    echo ":: no binhost dir provided (or missing) — full source build"
fi
}

# --- keywords ---
cat > "$ROOT/etc/portage/package.accept_keywords/nethix.conf" <<'EOF'
# whole-tree testing keywords: Nethix builds track ~amd64 by design
*/* ~amd64
# explicit for clarity / survives any future policy narrowing
sys-kernel/nethix-sources ~amd64
sys-kernel/linux-firmware ~amd64
EOF

# --- USE flags ---
cat > "$ROOT/etc/portage/package.use/nethix.conf" <<'EOF'
# nethix-sources[initramfs] requires dracut-capable installkernel
>=sys-kernel/installkernel-70-r1 dracut
# dracut is systemd-based on our live image
sys-kernel/dracut systemd
# linux-firmware: redistributable blob set only; live image carries it all
sys-kernel/linux-firmware redistributable
EOF

# --- licenses ---
cat > "$ROOT/etc/portage/package.license/nethix.conf" <<'EOF'
# belt-and-braces on top of ACCEPT_LICENSE: firmware blobs ship on the ISO
sys-kernel/linux-firmware linux-fw-redistributable no-source-code
EOF

# --- overlay repo wiring (idempotent; only when an overlay dir exists) ---
OVERLAY_SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/../overlay" 2>/dev/null && pwd)
if [[ -n "$OVERLAY_SRC" && -d "$OVERLAY_SRC" ]]; then
    mkdir -p "$ROOT"/var/db/repos/nethix
    cp -r "$OVERLAY_SRC"/* "$ROOT/var/db/repos/nethix/"
    cat > "$ROOT/etc/portage/repos.conf/nethix.conf" <<'EOF'
[nethix]
location = /var/db/repos/nethix
priority = 50
masters = gentoo
EOF
fi

# sanity: a broken make.conf should fail HERE, not mid-build
bash -n "$ROOT/etc/portage/make.conf" \
    || { echo "!! seeded make.conf has a shell syntax error" >&2; exit 1; }

echo ":: portage seed complete in $ROOT (licenses=$LICENSE_POLICY keywords=$KEYWORD_POLICY)"
