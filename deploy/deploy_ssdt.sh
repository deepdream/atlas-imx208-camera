#!/usr/bin/env bash
# deploy_ssdt.sh — 部署 ACPI SSDT overlay (固件层)
# 用法: sudo ./deploy_ssdt.sh [--remove]
# 前提: 已用 iasl 编译出 ssdt-cam0.aml
set -euo pipefail

GUID="9e21a83f-3c4d-4b7a-a5e8-6f0d1c2b3a4e"
VARNAME="CAM0SSD2"
AML="ssdt-cam0.aml"
LIMINE_CONF="/etc/default/limine"

if [[ $EUID -ne 0 ]]; then
	echo "请用 sudo 运行本脚本" >&2
	exit 1
fi

# ---------- 移除 ----------
if [[ "${1:-}" == "--remove" ]]; then
	echo "==> 移除 efivar_ssdt 内核参数"
	if grep -q "efivar_ssdt=$VARNAME" "$LIMINE_CONF"; then
		sed -i "s| efivar_ssdt=$VARNAME||" "$LIMINE_CONF"
		echo "   已从 $LIMINE_CONF 移除"
	else
		echo "   未找到参数 (可能已移除)"
	fi
	echo "==> 以下命令请手动执行以重新生成引导: "
	echo "    sudo limine-update   # 或你的引导器"
	echo "==> 可选: 若非要用 chattr 技术删除 EFI 变量, 见 README"
	exit 0
fi

# ---------- 部署 ----------
if [[ ! -f "$AML" ]]; then
	echo "错误: 找不到 $AML (请先 iasl $AML.asl 编译)" >&2
	exit 1
fi

echo "==> 写入 EFI 变量 $VARNAME (NVRAM)"
python3 - "$GUID" "$VARNAME" << 'EOF'
import os, sys
GUID, VARNAME = sys.argv[1], sys.argv[2]
aml = open('ssdt-cam0.aml', 'rb').read()
attrs = (0x1 | 0x2 | 0x4).to_bytes(4, 'little')  # NonVolatile | BootService | Runtime
path = f'/sys/firmware/efi/efivars/{VARNAME}-{GUID}'
with open(path, 'wb') as f:
    f.write(attrs + aml)
print(f'    {VARNAME} 写入成功, AML {len(aml)} 字节')
EOF

echo "==> 添加内核参数 efivar_ssdt=$VARNAME (到 $LIMINE_CONF)"
if grep -q "efivar_ssdt=$VARNAME" "$LIMINE_CONF"; then
	echo "   参数已存在, 跳过"
else
	sed -i "s|KERNEL_CMDLINE\[default\]+=\"\(.*\)\"|KERNEL_CMDLINE[default]+=\"\1 efivar_ssdt=$VARNAME\"|" "$LIMINE_CONF"
	echo "   已添加"
fi

echo "==> 下一步 (手动):"
echo "    sudo limine-update      # 重新生成引导项"
echo "    reboot                  # 重启让 SSDT 生效"
echo ""
echo "==> 验证:"
echo "    journalctl -k -b | grep -i 'loading SSDT'"
echo "    cam -l"
