#!/usr/bin/env bash
# setup_libcamera.sh — 应用 libcamera 补丁 (覆盖系统库, 需手动运行)
#
# 警告: 本脚本会覆盖官方 libcamera 包管理的文件。
# 运行前建议备份, 并在 libcamera 升级后重新运行。
# 本脚本不会 touch 已编译好的 libcamera 源码, 而是从本仓库的部署产物复制。
#
# 用法: sudo ./setup_libcamera.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "请用 sudo 运行本脚本" >&2
	exit 1
fi

echo "==> 确保 patchelf 已安装"
pacman -Q patchelf >/dev/null 2>&1 || { echo "  安装 patchelf..."; pacman -S --needed --noconfirm patchelf; }

# 这些文件是 libcamera 补丁后的产物, 需先构建 (见 README "用户态" 一节)。
# 若不存在, 提示用户先构建。
SRC_ROOT="${SRC_ROOT:-/home/tjm/Work/atlas-imx208-camera/userspace}"

echo "==> 检查补丁后的 libcamera 产物"
if [[ ! -f "$SRC_ROOT/libcamera.so.0.7.2" || ! -f "$SRC_ROOT/ipa_ipu3.so" ]]; then
	echo "  未找到已构建的 libcamera 产物 ($SRC_ROOT/)。" >&2
	echo "  请先按 README.md 的 '用户态' 一节构建, 或设置 SRC_ROOT 指向构建目录。" >&2
	echo "  跳过 libcamera 覆盖 (摄像头内核/固件层不受影响, 但无法拍照)。" >&2
	exit 2
fi

echo "==> 备份并安装 libcamera.so"
BACKUP_DIR="/usr/share/atlas-imx208-camera/backup"
mkdir -p "$BACKUP_DIR"
if [[ -f /usr/lib/libcamera.so.0.7.2 ]]; then
	cp -a /usr/lib/libcamera.so.0.7.2 "$BACKUP_DIR/libcamera.so.0.7.2.orig" 2>/dev/null || true
fi
cp "$SRC_ROOT/libcamera.so.0.7.2" /usr/lib/libcamera.so.0.7.2
patchelf --remove-rpath /usr/lib/libcamera.so.0.7.2

echo "==> 安装 IPA 模块"
if [[ -f /usr/lib/libcamera/ipa/ipa_ipu3.so ]]; then
	cp -a /usr/lib/libcamera/ipa/ipa_ipu3.so "$BACKUP_DIR/ipa_ipu3.so.orig" 2>/dev/null || true
fi
cp "$SRC_ROOT/ipa_ipu3.so" /usr/lib/libcamera/ipa/ipa_ipu3.so
patchelf --remove-rpath /usr/lib/libcamera/ipa/ipa_ipu3.so

echo "==> 安装代理 worker (无签名 IPA 需以隔离模式运行)"
mkdir -p /usr/libexec/libcamera
if [[ -f "$SRC_ROOT/ipu3_ipa_proxy" ]]; then
	cp "$SRC_ROOT/ipu3_ipa_proxy" /usr/libexec/libcamera/ipu3_ipa_proxy
	chmod +x /usr/libexec/libcamera/ipu3_ipa_proxy
	patchelf --remove-rpath /usr/libexec/libcamera/ipu3_ipa_proxy 2>/dev/null || true
else
	echo "  警告: 未找到 ipu3_ipa_proxy, 跳过 (摄像头可能无法工作)"
fi

echo "==> 安装 IPA 调优配置"
mkdir -p /usr/share/libcamera/ipa/ipu3
cp /usr/share/libcamera/ipa/ipu3/uncalibrated.yaml /usr/share/libcamera/ipa/ipu3/imx208.yaml 2>/dev/null || \
	{ echo "  uncalibrated.yaml 不存在, 跳过"; }

echo ""
echo "==> libcamera 补丁已应用。"
echo "  验证: cam -l"
echo "  回退: 从 $BACKUP_DIR 恢复, 或 pacman -S libcamera 重装"
echo "  注意: 下次 pacman 升级 libcamera 时会覆盖这些文件, 需重新运行本脚本。"
