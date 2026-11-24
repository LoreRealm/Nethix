EAPI=8
inherit kernel-2

DESCRIPTION="Linux kernel with CachyOS/BORE patches"
HOMEPAGE="https://github.com/CachyOS/linux-cachyos"
SRC_URI="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${PV}.tar.xz
         https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/patches/6.12/0001-bore.patch"
LICENSE="GPL-2"
KEYWORDS="~amd64"
SLOT="${PV}"

src_prepare() {
	default
	eapply "${DISTDIR}"/0001-bore.patch
}
