#!/usr/bin/env bash
# inject_ssdt.sh — 将 ssdt-cam0.aml 写入 EFI 变量 (由 systemd 服务在开机时调用)
#
# 说明:
#  - 固件层补丁通过 EFI 变量注入 ACPI SSDT, 再由内核参数 efivar_ssdt=CAM0SSD2 加载。
#  - pacman 事务环境不适合写 EFI, 故由本 oneshot 服务处理。
#  - 若变量已存在且内容一致, 跳过; 若为 immutable(已加载过), 先解锁再更新。
#
# 为什么用 python 而不是纯 bash:
#  efivarfs 的文件写入必须在一次 open 后用**单次 write 系统调用**完成
#  (EFI 变量不支持普通文件的 O_TRUNC/多次 write 语义)。
#  bash 的 `cat > file` 会先 open(O_TRUNC) 再多次 write, 对 efivarfs 会
#  报 "Operation not permitted" / 写入失败。
#  python 的 os.open(O_WRONLY|O_CREAT) + os.write(buf) 单次写入才是正确方式。
#  (已在机器上实测验证: bash cat > 失败, python os.write 成功)
#
# 依赖: python3
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
	existing_size=$(stat -c%s "$VAR" 2>/dev/null || echo 0)
	aml_size=$(stat -c%s "$AML")
	if [[ $existing_size -eq $((aml_size + 4)) ]]; then
		if cmp -s <(tail -c +5 "$VAR") "$AML"; then
			echo "SSDT 变量已存在且一致, 无需更新"
			exit 0
		fi
	fi
	echo "更新已有 SSDT 变量 (先解锁 immutable)"
	chattr -i "$VAR" 2>/dev/null || true
fi

echo "写入/更新 EFI 变量 $VARNAME (GUID $GUID)"
python3 - "$GUID" "$VARNAME" "$AML" "$VAR" << 'EOF'
import os, sys
GUID, VARNAME, AML, VAR = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
aml = open(AML, 'rb').read()
attrs = (0x1 | 0x2 | 0x4).to_bytes(4, 'little')  # NonVolatile | BootService | Runtime
try:
    fd = os.open(VAR, os.O_WRONLY | os.O_CREAT)
    os.write(fd, attrs + aml)
    os.close(fd)
except PermissionError:
    print(f"无法写入 {VAR}, 请检查权限/解锁 immutable", file=sys.stderr)
    sys.exit(1)
print(f"写入完成: {len(aml)} 字节")
EOF

# 重新上锁 (若之前解锁了)
chattr +i "$VAR" 2>/dev/null || true

echo ""
echo "注意: 还需在内核启动参数中添加 efivar_ssdt=$VARNAME (见 README)"
echo "若已添加, 重启后 SSDT 即可生效。"
