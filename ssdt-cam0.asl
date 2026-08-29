/*
 * SSDT overlay: 摄像头传感器 for Google Atlas (Pixelbook Go)
 *
 * 固件 (coreboot) 的 ACPI 表中缺少摄像头传感器设备定义,
 * 本 SSDT 补充之, 使内核 ipu_bridge 能发现并实例化传感器。
 *
 * 传感器实测为 Sony IMX208 (上电后 reg 0x0000 读回 0x0208, 确定性应答):
 *   - imx208 驱动的 ACPI ID 是 INT3478, 但 v7.1 内核 ipu-bridge 不认识 INT3478
 *   - ipu-bridge 认识 INT3479 (配置为 1 lane-freq), 但无任何驱动绑定 INT3479
 *   - 解决: _HID=INT3479 让 bridge 建管线, _CID=INT3478 让 imx208 绑定
 *   - imx208 不解析端点 link-frequencies 属性, cio2 的 D-PHY 时序取自
 *     传感器 V4L2_CID_LINK_FREQ 控制 (384MHz), 故 422MHz 属性值无实际影响
 *
 * 依据:
 *  - 固件 SSDT 中 \_SB.PCI0.I2C3.DSC0 (INT3472) 已定义电源/时钟/reset GPIO
 *  - INT3472 通过 _DEP 依赖关系找到传感器 (acpi_dev_get_next_consumer_dev)
 *  - SSDB 结构对齐内核 include/media/ipu-bridge.h (108 字节 packed)
 *  - imx208 要求 mclk 恰为 19.2MHz (来自 int3472 时钟, 频率读自本 SSDB)
 */
DefinitionBlock ("ssdt-cam0.aml", "SSDT", 2, "OMARCH", "CAM0IMX2", 0x00001000)
{
    External (\_SB.PCI0.I2C3, DeviceObj)
    External (\_SB.PCI0.I2C3.DSC0, DeviceObj)

    Scope (\_SB.PCI0.I2C3)
    {
        Device (CAM0)
        {
            Name (_HID, "INT33F0")  /* bridge 支持且无驱动认领, 避免被 ov5670 抢绑 */
            Name (_CID, "INT3478")  /* imx208 驱动的 ACPI 匹配 ID */
            Name (_UID, Zero)
            Name (_DDN, "IMX208 Camera")

            Method (_STA, 0, NotSerialized)  /* 存在且启用 */
            {
                Return (0x0F)
            }

            Method (_DEP, 0, NotSerialized)  /* 依赖 INT3472 电源控制器 */
            {
                Return (Package (One) { \_SB.PCI0.I2C3.DSC0 })
            }

            Name (_CRS, ResourceTemplate ()  /* I2C3 总线, 地址 0x36 */
            {
                I2cSerialBusV2 (0x0036, ControllerInitiated, 0x00061A80,
                    AddressingMode7Bit, "\\_SB.PCI0.I2C3",
                    0x00, ResourceConsumer, , Exclusive,
                    )
            })

            /* 传感器描述块 (SSDB), 内核 ipu-bridge/int3472 解析:
             *   link=0 (CIO2 port 0), lanes=2, degree=0, vcmtype=0,
             *   mclkspeed@0x56 = 19.2MHz */
            Name (SSDB, Buffer (0x6C)
            {
                /* 0x0000 */  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                /* 0x0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                /* 0x0010 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                /* 0x0018 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00,
                /* 0x0020 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                /* 0x0028 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                /* 0x0030 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                /* 0x0038 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                /* 0x0040 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08,
                /* 0x0048 */  0xAF, 0x2F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                /* 0x0050 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xF8,
                /* 0x0058 */  0x24, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                /* 0x0060 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                /* 0x0068 */  0x00, 0x00, 0x00, 0x00
            })
        }
    }
}
