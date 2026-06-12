# AHB-Lite 系统总线

系统总线负责连接CPU核心和主存/外设，基于 AMBA 3 AHB-Lite 协议 (ARM IHI 0033A) 实现。

## 模块结构

```
AHB-lite/
├── ahb_def.svh            # AHB-Lite 参数与常量定义
├── ahb_lite_bus.sv        # AHB 外设总线顶层（集成decoder+mux+sram_slave+bridge）
├── ahb_decoder.sv         # 地址译码器（HADDR→HSELx）
├── ahb_mux.sv             # 读数据/响应多路选择器
├── ahb_rom_slave.sv       # ROM 从设备（存储器）
└── AHB-lite.md           # 本文档
```

## 协议关键特性

- 单主设备、流水线操作（地址/数据阶段重叠）
- 单时钟沿（HCLK上升沿采样）、非三态实现
- 支持突发传输（SINGLE/INCR/WRAP4/INCR4等）
- 支持宽数据总线（32位默认，可扩展）
- ERROR响应2周期（HRESP=ERROR, HREADY=LOW→HIGH）
- HRESETn 低电平有效（唯一低有效信号）

## 与APB的连接

通过 `rtl/ABP/ahb_lite_to_apb.sv` 桥接模块实现 AHB-Lite→APB 转换，连接低速外设。
