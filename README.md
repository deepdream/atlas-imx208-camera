# Google Atlas (Pixelbook Go) — IMX208 摄像头在 Linux 下的完整修复

> 让一台跑 **Omarchy**（Arch Linux + Hyprland + coreboot 固件）的 **Pixelbook Go** 的内置摄像头（Sony IMX208, Intel IPU3 管线）完全可用。

在这个平台上，摄像头默认**无法工作**，因为刷了自定义 coreboot UEFI 固件后，ACPI 表里**缺少摄像头传感器的描述**。本仓库提供了从固件、内核到用户态的**三层补丁**，让摄像头完整工作起来。

---

## 背景

**硬件**：Google Atlas（Pixelbook Go），Intel 平台，摄像头为 **Sony IMX208**，走 **Intel IPU3**（cio2 + imgu）图像管线。

**症状**：
- `v4l2-ctl --list-devices` 只能看到 `ipu3-imgu` / `ipu3-cio2`，没有传感器节点
- `dmesg` 显示 `INT3472 seems to have no dependents`
- 没有可用的摄像头输出节点

**根因**：这台 Chromebook 刷了 coreboot UEFI 固件（非原厂 ChromeOS 固件），此固件生成的 ACPI 表只定义了 IPU3 硬件（`INT3472` 电源控制器 `\_.SB.PCI0.I2C3.DSC0`），而**没有定义摄像头传感器设备本身**。Linux 的 `ipu_bridge` 靠扫描 ACPI 中的传感器设备来建立管线，找不到就什么都不做。

**诊断关键**：在驱动上电窗口内做 I2C 采样，读传感器寄存器 `0x0000` 得 `0x0208` —— 确认为 **Sony IMX208**（而非常见 Chromebook 的 OV2740）。

---

## 三层解决方案

```
用户态    libcamera + PipeWire + 浏览器 (Chromium --enable-features=WebRtcPipeWireCamera)
    ↑
内核      imx208 驱动补丁 (电源管理 + 运行时PM + 元数据控件)
    ↑
固件      ACPI SSDT overlay (补充传感器设备定义, 经 EFI 变量注入)
```

### 1. 固件层：ACPI SSDT overlay（`ssdt-cam0.asl`）

在 `\_SB.PCI0.I2C3` 下定义传感器设备 `CAM0`：

| 项目 | 值 | 原因 |
|---|---|---|
| `_HID` | `INT33F0` | ipu_bridge 认识且无驱动认领，避免被其他驱动抢绑 |
| `_CID` | `INT3478` | imx208 驱动的 ACPI 匹配 ID（驱动借此绑定） |
| `_CRS` 地址 | `0x36` | IMX208 实测 I2C 地址 |
| `SSDB` | 108 字节 | 对齐内核 `include/media/ipu-bridge.h`（lanes=2, mclk=19.2MHz）|
| `_DEP` | 依赖 `\_SB.PCI0.I2C3.DSC0` | int3472 通过 `_DEP` 依赖找到传感器 |

**注入方式**：编译成 `ssdt-cam0.aml`，写入 NVRAM 一个 EFI 变量，通过内核参数 `efivar_ssdt=` 加载（与引导器无关，内核更新后仍保留）。

### 2. 内核层：imx208 驱动补丁（`kernel/`）

上游 `imx208.c` **完全没有电源管理**（不使能时钟、不处理复位脚、不管理供电），导致在 int3472 平台上传感器无法响应。补丁增加：

- `avdd` 供电调节器（`devm_regulator_get` + `regulator_enable/disable`）
- `reset` GPIO 的取得与释放
- 时钟使能（`clk_prepare_enable`）
- **运行时电源管理**：空闲 3 秒自动断电（`runtime_suspend`），抓流时自动上电 —— 同时让模块的绿色隐私灯正确工作（**不用时灭、使用时亮**）
- 新增 `V4L2_CID_CAMERA_ORIENTATION` / `V4L2_CID_CAMERA_SENSOR_ROTATION` 元数据控件（消除 libcamera 警告）

### 3. 用户态：libcamera 补丁（`patches/libcamera-imx208.patch`）

基于 libcamera **v0.7.2**，三处修改：

- `src/ipa/libipa/camera_sensor_helper.cpp`：新增 `CameraSensorHelperImx208`（曝光/增益寄存器语义），让 IPU3 的 3A 算法能识别 imx208
- `src/libcamera/pipeline/ipu3/ipu3.cpp`：容忍"传感器无测试图案"，不再因此阻断启动
- `src/libcamera/sensor/camera_sensor_properties.cpp`：新增 imx208 静态属性（像素单元 1.12µm、传感器延迟）

---

## 安装

> 以下均在目标机器上执行（需要 root）。假定内核版本与补丁一致（本仓库针对 Linux 7.1.x / libcamera 0.7.2）。

### 准备工具

```bash
sudo pacman -S --needed acpica i2c-tools libcamera libcamera-tools pipewire-libcamera libgpiod meson ninja git
```

### 1. 固件层（ACPI SSDT）

```bash
# 编译 SSDT
iasl ssdt-cam0.asl          # 生成 ssdt-cam0.aml

# 写入 EFI 变量 (NVRAM)
GUID=9e21a83f-3c4d-4b7a-a5e8-6f0d1c2b3a4e
python3 - "$GUID" << 'EOF'
import os,sys
GUID=sys.argv[1]
aml=open('ssdt-cam0.aml','rb').read()
attrs=(1|2|4).to_bytes(4,'little')
with open(f'/sys/firmware/efi/efivars/CAM0SSD2-{GUID}','wb') as f:
    f.write(attrs+aml)
EOF

# 加入内核启动参数 (本例用 limine, 修改 /etc/default/limine)
sudo sed -i 's|KERNEL_CMDLINE\[default\]+="\(.*\)"|KERNEL_CMDLINE[default]+="\1 efivar_ssdt=CAM0SSD2"|' /etc/default/limine
sudo limine-update
```

> 注：EFI 变量名 `CAM0SSD2` 与内核参数 `efivar_ssdt=` 必须一致。加载过的变量会被内核标记只读（immutable），迭代修改时需 `chattr -i` 解锁。

### 2. 内核层（imx208 补丁模块）

```bash
cd kernel
make -C /lib/modules/$(uname -r)/build M=$PWD modules
sudo zstd -q -f imx208.ko -o /lib/modules/$(uname -r)/updates/imx208.ko.zst
sudo depmod -a $(uname -r)
```

> 放在 `/lib/modules/.../updates/` 可覆盖发行版自带版本。**内核更新后需重新执行**。

### 3. 用户态（libcamera）

```bash
# 浅克隆对应版本
git clone --depth 1 --branch v0.7.2 https://github.com/libcamera-org/libcamera.git libcamera
cd libcamera
git apply ../patches/libcamera-imx208.patch

# 构建 (仅 IPU3 管线)
meson setup build -Dpipelines=ipu3 -Dipas=ipu3 -Dtest=false \
  -Ddocumentation=disabled -Dqcam=disabled -Dcam=disabled \
  -Dgstreamer=disabled -Dv4l2=disabled -Dlc-compliance=disabled \
  -Dpycamera=disabled -Dtracing=disabled -Dandroid=disabled
ninja -C build
sudo cp build/src/libcamera/libcamera.so.0.7.2 /usr/lib/libcamera.so.0.7.2
sudo cp build/src/ipa/ipu3/ipa_ipu3.so /usr/lib/libcamera/ipa/ipa_ipu3.so

# 去除 RUNPATH, 让 libcamera 认为已安装 (见 README 详细说明)
sudo patchelf --remove-rpath /usr/lib/libcamera.so.0.7.2 /usr/lib/libcamera/ipa/ipa_ipu3.so

# 代理 worker (无签名 IPA 以隔离模式运行)
sudo mkdir -p /usr/libexec/libcamera
sudo cp build/src/libcamera/proxy/worker/ipu3_ipa_proxy /usr/libexec/libcamera/ipu3_ipa_proxy

# IPA 调优配置
sudo cp /usr/share/libcamera/ipa/ipu3/uncalibrated.yaml /usr/share/libcamera/ipa/ipu3/imx208.yaml
```

> **为什么需要 `patchelf --remove-rpath`**：libcamera 通过 `DT_RUNPATH` 判断"是否已安装"。构建产物带 RUNPATH，会被误判为未安装而使用错误的资源路径，导致 ICP/IPA 查找失败。去掉后视为已安装。

### 4. 重新生成 initramfs（如引导用 UKI）+ 重启

```bash
sudo mkinitcpio -P   # 或 limine-update (见你的引导器)
reboot
```

---

## 验证

```bash
# 1. libcamera 列出摄像头 — 应只有 INFO, 0 个 ERROR/WARN
cam -l
# 期望: Available cameras:\n1: Internal front camera (\_SB_.PCI0.I2C3.CAM0)

# 2. 抓流 — 约 60fps
cam -c1 --stream role=viewfinder,width=1920,height=1080 --capture=30

# 3. 浏览器 (Chromium 需 --enable-features=WebRtcPipeWireCamera)
chromium --enable-features=WebRtcPipeWireCamera --new-window https://webcamtests.com
```

**电源管理 / 隐私灯行为**：

```bash
# 空闲时应为 suspended, GPIO-80(avdd) 为 out lo (灯灭)
cat /sys/bus/i2c/devices/i2c-INT33F0:00/power/runtime_status   # suspended
grep "gpio-80" /sys/kernel/debug/gpio                          # out lo
# 抓流时变为 active / out hi (灯亮)
```

---

## 维护与更新

| 场景 | 操作 |
|---|---|
| **内核更新后** | 重跑 `kernel/` 的 make + 安装 |
| **libcamera 更新后** | 重新 git clone v0.7.2 → `git apply` 补丁 → 重建 → 替换 |
| **完全回退** | 移掉 `efivar_ssdt` 内核参数；还原 `/usr/lib/libcamera*` 与 `/usr/lib/libcamera/ipa/*`；删除 `/lib/modules/*/updates/imx208.ko.zst` |

---

## 诊断过程中的关键点

本项目能搞定，得益于几个关键发现（对排查类似问题有参考价值）：

1. **i2cdetect 的局限**：IPU3 传感器对"裸读"不响应，必须"先写寄存器地址再读"。用 `i2ctransfer w2@ADDR 0x00 0x00 r4` 才能在**上电窗口**内读到芯片 ID。
2. **传感器真实型号**：寄存器 `0x0000` 读回 `0x0208` = IMX208（不是常见的 OV2740），且其驱动 ACPI ID 是 `INT3478`。
3. **`_HID`/`_CID` 双 ID 技巧**：ipu_bridge 不认识 imx208 的 HID，但认识 `INT33F0`（无驱动认领）；让 `_HID=INT33F0` 驱动 bridge、`_CID=INT3478` 驱动 imx208 绑定。
4. **int3472 的 `_DSM` 极性**：`sensor_on_val=0x01`（非 0）→ 不翻转极性，avdd 为 ACTIVE_HIGH。LED 接在 avdd 线上，故"供电=灯亮"。
5. **libcamera 签名隔离**：无签名 IPA 模块不会被拒绝，而是降级为隔离进程（`isSignatureValid` 失败 → Isolated 代理），因此自建模块可用。

---

## 硬件与软件版本

| 组件 | 版本 |
|---|---|
| 主板 | Google Atlas (Pixelbook Go) |
| 固件 | coreboot UEFI (Omarchy 自刷) |
| 内核 | Linux 7.1.x |
| libcamera | 0.7.2 |
| 摄像头 | Sony IMX208 (via Intel IPU3) |

---

## License

本仓库的补丁与脚本以 GPL-2.0 发布（与内核/libcamera 一致）。
