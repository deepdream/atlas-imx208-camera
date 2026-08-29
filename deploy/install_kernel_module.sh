#!/usr/bin/env bash
# install_kernel_module.sh — 编译并安装 imx208 补丁内核模块
# 用法: sudo ./install_kernel_module.sh
# 前提: 已安装 linux-headers (匹配当前内核)
set -euo pipefail

KVER=$(uname -r)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/../kernel"

echo "==> 编译 imx208 模块 (内核 $KVER)"
make -C "/lib/modules/$KVER/build" M="$SRC" modules

echo "==> 安装到 updates/ 覆盖目录"
mkdir -p "/lib/modules/$KVER/updates"
zstd -q -f "$SRC/imx208.ko" -o "/lib/modules/$KVER/updates/imx208.ko.zst"
depmod -a "$KVER"

echo "==> 校验解析路径 (应为 updates/)"
modinfo -n imx208

echo ""
echo "==> 完成。内核更新后请重跑本脚本。"
