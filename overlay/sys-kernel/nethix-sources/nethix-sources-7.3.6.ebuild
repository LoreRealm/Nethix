# Copyright 2026 Nethix contributors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

K_NOUSEATOMICAKFS=1
inherit kernel-build

MY_P="cachyos-${PV}"
DESCRIPTION="Nethix kernel: CachyOS fork (EEVDF + Cachy Sauce), hermetically pinned"
HOMEPAGE="https://github.com/CachyOS/linux"
SRC_URI="${CATEGORY}/${PN}/files/${PV}/cachyos-${PV}-${PR/-/_}.tar.gz -> ${MY_P}.tar.gz"
S="${WORKDIR}/${MY_P}"

KEYWORDS="~amd64"
IUSE="debug"

# The shipped CachyOS config, committed alongside the tarball
CONFIG_URI=""

depend() {
    :
}

depend_rdepend() {
    :
}

pkg_setup() {
    ewarn "Building nethix-sources uses the CachyOS shipped config from"
    ewarn "files/${PV}/config-cachyos. Overrides not yet supported."
}
