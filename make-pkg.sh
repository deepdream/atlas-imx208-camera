#!/usr/bin/env bash
# make-pkg.sh — 一键构建 atlas-imx208-camera 安装包
#
# 会在仓库根的 build-src/ 里平铺收集构建所需源码, 然后运行 makepkg 生成
# atlas-imx208-camera-<ver>-<rel>-x86_64.pkg.tar.zst
#
# 用法: ./make-pkg.sh
# 前提: 已安装 linux-headers (匹配当前内核), zstd, python
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILDDIR="$SCRIPT_DIR/build-src"

echo "==> 准备构建源目录 $BUILDDIR"
mkdir -p "$BUILDDIR"
# 从仓库其它位置收集平铺源
cp "$SCRIPT_DIR/kernel/imx208.c"        "$BUILDDIR/imx208.c"
cp "$SCRIPT_DIR/kernel/Makefile"        "$BUILDDIR/Makefile"
cp "$SCRIPT_DIR/ssdt-cam0.asl"          "$BUILDDIR/ssdt-cam0.asl"
cp "$SCRIPT_DIR/ssdt-cam0.aml"          "$BUILDDIR/ssdt-cam0.aml"
cp "$SCRIPT_DIR/packaging/atlas-camera-ssdt.service" "$BUILDDIR/atlas-camera-ssdt.service"
cp "$SCRIPT_DIR/packaging/inject_ssdt.sh"            "$BUILDDIR/inject_ssdt.sh"
cp "$SCRIPT_DIR/userspace/setup_libcamera.sh"        "$BUILDDIR/setup_libcamera.sh"
cp "$SCRIPT_DIR/README.md"              "$BUILDDIR/README.md"

# 把 PKGBUILD 与 install 脚本也放进去 (makepkg 要求它们在构建目录)
cp "$SCRIPT_DIR/PKGBUILD"               "$BUILDDIR/PKGBUILD"
cp "$SCRIPT_DIR/atlas-imx208-camera.install" "$BUILDDIR/atlas-imx208-camera.install"

echo "==> 检查依赖"
command -v makepkg >/dev/null || { echo "缺少 makepkg (pacman)"; exit 1; }
[[ -d "/lib/modules/$(uname -r)/build" ]] || { echo "缺少 linux-headers (匹配 $(uname -r))"; exit 1; }

echo "==> 开始 makepkg (生成 $($SCRIPT_DIR)/atlas-imx208-camera-*.pkg.tar.zst)"
cd "$BUILDDIR"
makepkg -f --noconfirm

echo ""
echo "==> 构建完成: $BUILDDIR/atlas-imx208-camera-*.pkg.tar.zst"
echo "    安装: sudo pacman -U $BUILDDIR/atlas-imx208-camera-*.pkg.tar.zst"
