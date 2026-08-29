#!/bin/bash
set -e
KVER=$(uname -r)
echo "=== 1. 检查 depmod 覆盖顺序 ==="
ls /etc/depmod.d/ 2>/dev/null || echo "无 depmod.d, 使用默认搜索顺序"
echo "=== 2. 安装补丁模块到 updates/ ==="
mkdir -p /lib/modules/$KVER/updates
zstd -q -f /home/tjm/Work/acpi-camera/imx208-fix/imx208.ko -o /lib/modules/$KVER/updates/imx208.ko.zst
echo "=== 3. depmod ==="
depmod -a $KVER
echo "=== 4. 解析验证 (应指向 updates/) ==="
modinfo -n imx208
echo "=== 5. 热重载模块 ==="
modprobe -r imx208 2>/dev/null || true
modprobe imx208
sleep 1
echo "=== 6. 探测结果 ==="
journalctl -k -b --since "-30s" | grep -iE "imx208|Connected.*camera" | grep -v "Modules linked" | head -8
D=$(ls -d /sys/bus/i2c/devices/i2c-INT33F0* 2>/dev/null | head -1)
echo "设备: $D"
[ -n "$D" ] && readlink $D/driver | awk -F/ '{print "绑定驱动: "$NF}'
