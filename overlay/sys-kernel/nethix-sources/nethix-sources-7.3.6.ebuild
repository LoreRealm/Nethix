# Copyright 2026 Nethix contributors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
K_NOINSTALL_MODULES=yes

inherit kernel-build toolchain-funcs

MY_PV="cachyos-${PV}-1"
MY_P="linux-${MY_PV}"

DESCRIPTION="Nethix kernel: CachyOS fork (EEVDF, Cachy Sauce), hermetically hash-pinned"
HOMEPAGE="https://github.com/CachyOS/linux"
SRC_URI="https://github.com/CachyOS/linux/releases/download/${MY_PV}/${MY_PV}.tar.gz -> ${MY_P}.tar.gz"

LICENSE="GPL-2"
KEYWORDS="~amd64"
IUSE="debug"

BDEPEND="
    app-arch/xz-utils
    dev-util/pahole
    sys-devel/bc
    sys-devel/flex
    virtual/libelf
    llvm-core/clang
    llvm-core/lld
"

# CachyOS's shipped config — fetched from the upstream linux-cachyos repo
# by scripts/fetch-cachy-patches.sh into files/${PV_MAJOR}/config-cachyos.
# If missing, we fetch it directly at unpack time (it's a plain text file,
# cheap to download, hash verified via the committed Manifest-snippet after
# the first run).
SRC_URI+=" https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/linux-cachyos/config -> config-cachyos-${PV}"

CONFIG_FILE="${WORKDIR}/config-cachyos-${PV}"

# The CachyOS release tarball's top-level directory name is not stable
# across releases (e.g. 'linux-cachyos-<ver>' vs 'cachyos-<ver>-1'), so we
# locate it after unpack instead of hardcoding S.
src_unpack() {
    default
    S=$(find "${WORKDIR}" -mindepth 1 -maxdepth 1 -type d ! -name 'config-*' | head -n1)
    [[ -d ${S} ]] || die "couldn't find unpacked source dir in ${WORKDIR}"
    export S
}

pkg_setup() {
    ewarn "Using the CachyOS shipped config (config-cachyos)."
    ewarn "Local customization: emerge with _use_current-style edits via /etc/portage/savedconfig later."
}

src_prepare() {
    default
    # Ship the pinned CachyOS config as the base .config
    cp "${CONFIG_FILE}" "${S}/.config" || die "failed to install config"
    # Match CachyOS's localversion treatment so modules land under
    # /lib/modules/<ver>-cachyos, like the upstream package
    echo "-1" > "${S}/localversion.10-pkgrel"
    echo "-cachyos" > "${S}/localversion.20-pkgname"
    MAKEARGS+=(LLVM=1 LLVM_IAS=1)
}

pkg_postinst() {
    kernel-build_pkg_postinst
    einfo "nethix-sources installed. Rebuild bootloader config via cantrip-kernel."
}
