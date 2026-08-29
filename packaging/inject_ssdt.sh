#!/usr/bin/env bash
# inject_ssdt.sh — 将 ssdt-cam0.aml 写入 EFI 变量 (由 systemd 服务在开机时调用)
#
# 说明:
#  - 固件层补丁通过 EFI 变量注入 ACPI SSDT, 再由内核参数 efivar_ssdt=CAM0SSD2 加载。
#  - pacman 事务环境不适合写 EFI, 故由本 oneshot 服务处理。
#  - 若变量已存在且是 immutable(已加载过), 本脚本尝试解锁并更新。
#  - 若变量已存在且内容一致, 跳过。
set -euo pipefail

GUID="9e21a83f-3c4d-4b7a-a5e8-6f0d1c2b3a4e"
VARNAME="CAM0SSD2"
AML="/usr/share/atlas-imx208-camera/ssdt-cam0.aml"
VAR="/sys/firmware/efi/efivars/$VARNAME-$GUID"

if [[ ! -f "$AML" ]]; then
	echo "找不到 $AML, 跳过" >&2
	exit 1
fi

# 若已存在且内容一致, 跳过
if [[ -e "$VAR" ]]; then
	# 检查已有的 aml 部分是否与我们的一致 (跳过前4字节 attributes)
	existing_size=$(stat -c%s "$VAR" 2>/dev/null || echo 0)
	aml_size=$(stat -c%s "$AML")
	if [[ $existing_size -eq $((aml_size + 4)) ]]; then
		if cmp -s <(tail -c +5 "$VAR") "$AML"; then
			echo "SSDT 变量已存在且一致, 无需更新"
			exit 0
		fi
	fi
	echo "更新已有 SSDT 变量 (先尝试解锁 immutable)"
	chattr -i "$VAR" 2>/dev/null || true
fi

echo "写入/更新 EFI 变量 $VARNAME (GUID $GUID)"
python3 - "$GUID" "$VARNAME" "$AML" "$VAR" << 'EOF'
import os, sys
GUID, VARNAME, AML, VAR = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
aml = open(AML, 'rb').read()
attrs = (0x1 | 0x2 | 0x4).to_bytes(4, 'little')  # NonVolatile | BootService | Runtime
try:
    with open(VAR, 'wb') as f:
        f.write(attrs + aml)
except PermissionError:
    print(f"无法写入 {VAR}, 请检查权限 (efivarfs 可能需 root)", file=sys.stderr)
    sys.exit(1)
print(f"写入完成: {len(aml)} 字节")
EOF

# 重新上锁 (若之前解锁了)
chattr +i "$VAR" 2>/dev/null || true

echo ""
echo "注意: 还需在内核启动参数中添加 efivar_ssdt=$VARNAME (见 README)"
echo "若已添加, 重启后 SSDT 即可生效。"
