EAPI=8
inherit kernel-2 toolchain-funcs

# Pin the real CachyOS patchset for this kernel version.
# Files are fetched by scripts/fetch-cachy-patches.sh and committed here,
# so the ebuild is hermetic and reproducible (no live network dependency).
DESCRIPTION="Nethix kernel — mainline with CachyOS/BORE patchset"
HOMEPAGE="https://github.com/CachyOS/linux-cachyos"
SRC_URI="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${PV}.tar.xz"

LICENSE="GPL-2"
KEYWORDS="~amd64"
SLOT="${PV}"
IUSE="bore"

FILESDIR="${FILESDIR}/${PV}"
PATCHES=(
	"${FILESDIR}/0001-bore.patch"
	"${FILESDIR}/0002-cachy-default-config.patch"
)

src_unpack() {
	default
	# kernel-2 will unpack linux-${PV} into ${WORKDIR}
}

src_prepare() {
	default
	[[ -f ${FILESDIR}/0001-bore.patch ]] && eapply "${FILESDIR}/0001-bore.patch"
	[[ -f ${FILESDIR}/0002-cachy-default-config.patch ]] && eapply "${FILESDIR}/0002-cachy-default-config.patch"
}
