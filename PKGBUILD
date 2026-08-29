# Maintainer: deepdream <deepdream399@sohu.com>
# 让 Google Atlas (Pixelbook Go) 的 IMX208 摄像头在 Omarchy/Arch 上可用。
#
# 本包包含方案 C 的"可干净打包"两层:
#   1. 内核模块 imx208 (电源 + 运行时PM + 元数据控件补丁) -> /lib/modules/<kver>/updates/
#   2. ACPI SSDT (固件层) + 开机注入 EFI 变量的 systemd 服务
# libcamera 补丁是覆盖系统库的侵入式操作, 不打包, 由随附 setup_libcamera.sh 处理。
#
# 构建: 在仓库根目录运行  makepkg -f
# 重要: 内核模块与构建时内核强绑定, 升级内核后需重新构建。
pkgname=atlas-imx208-camera
pkgver=1.0
pkgrel=1
pkgdesc="Make the Sony IMX208 camera work on Google Atlas (Pixelbook Go) under Omarchy/Arch"
arch=('x86_64')
url="https://github.com/deepdream/atlas-imx208-camera"
license=('GPL-2.0')
depends=('linux' 'zstd')
makedepends=('linux-headers' 'python')
optdepends=('libcamera: user-space side, run setup_libcamera.sh'
            'acpica: to rebuild the SSDT if needed')
install=atlas-imx208-camera.install
source=(
    "imx208.c"
    "Makefile"
    "ssdt-cam0.asl"
    "ssdt-cam0.aml"
    "atlas-camera-ssdt.service"
    "inject_ssdt.sh"
    "setup_libcamera.sh"
    "README.md"
)
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP')

_kver=$(uname -r)

build() {
    echo "==> 编译内核模块 (目标内核 $_kver)"
    make -C "/lib/modules/$_kver/build" M="$srcdir" modules
}

package() {
    # ---- 内核模块 -> updates/ (覆盖发行版自带) ----
    echo "==> 安装内核模块"
    install -dm755 "$pkgdir/usr/lib/modules/$_kver/updates"
    zstd -q -f "$srcdir/imx208.ko" -o "$pkgdir/usr/lib/modules/$_kver/updates/imx208.ko.zst"

    # ---- SSDT (固件层) ----
    echo "==> 安装 ACPI SSDT"
    install -Dm644 "$srcdir/ssdt-cam0.aml" "$pkgdir/usr/share/atlas-imx208-camera/ssdt-cam0.aml"
    install -Dm644 "$srcdir/ssdt-cam0.asl" "$pkgdir/usr/share/atlas-imx208-camera/ssdt-cam0.asl"

    # ---- 注入脚本与服务 ----
    install -Dm755 "$srcdir/inject_ssdt.sh" "$pkgdir/usr/share/atlas-imx208-camera/inject_ssdt.sh"
    install -Dm644 "$srcdir/atlas-camera-ssdt.service" "$pkgdir/usr/lib/systemd/system/atlas-camera-ssdt.service"

    # ---- libcamera 脚本 (不覆盖系统, 供用户运行) ----
    install -Dm755 "$srcdir/setup_libcamera.sh" "$pkgdir/usr/share/atlas-imx208-camera/setup_libcamera.sh"

    # ---- 文档 ----
    install -Dm644 "$srcdir/README.md" "$pkgdir/usr/share/doc/$pkgname/README.md"
}
