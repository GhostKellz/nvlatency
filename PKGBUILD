# Maintainer: GhostKellz <ghost@ghostkellz.sh>
pkgname=nvlatency
pkgver=1.0.0
pkgrel=1
pkgdesc="NVIDIA Reflex Integration for Linux - VK_NV_low_latency2 frame timing"
arch=('x86_64')
url="https://github.com/ghostkellz/nvlatency"
license=('MIT')
depends=('glibc' 'vulkan-icd-loader' 'nvvk')
makedepends=('zig>=0.14')
optdepends=(
    'nvidia-utils: NVIDIA GPU detection'
)
provides=('libnvlatency.so')
source=("$pkgname-$pkgver.tar.gz::$url/archive/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "$pkgname-$pkgver"
    zig build -Doptimize=ReleaseFast -Dlinkage=dynamic
}

package() {
    cd "$pkgname-$pkgver"

    # CLI binary
    install -Dm755 zig-out/bin/nvlatency "$pkgdir/usr/bin/nvlatency"

    # Shared library for FFI
    install -Dm755 zig-out/lib/libnvlatency.so "$pkgdir/usr/lib/libnvlatency.so"

    # C header for development
    install -Dm644 include/nvlatency.h "$pkgdir/usr/include/nvlatency.h"

    # Documentation
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
