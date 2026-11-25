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
S="${WORKDIR}/${MY_P}"

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

# CachyOS's shipped config, hash-pinned in files/ via Manifest
CONFIG_FILE="${FILESDIR}/config-cachynos"

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
