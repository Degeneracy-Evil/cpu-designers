# FPGA Kernel UART Earlycon 不输出问题总结

## 现象

FPGA 上 OpenSBI 串口输出正常，但 Linux kernel 阶段长期只看到 console handover 附近的几行日志，例如：

- `printk: legacy console [ttyS0] enabled`
- `printk: legacy bootconsole [uart8250] disabled`

这曾被误判为 real 8250 console、FIFO、UART IRQ、PLIC 或 SEIP 链路问题。

## 根因

`bootargs` 中显式 earlycon 参数原先为：

```text
earlycon=uart8250,mmio32,0x10008000,230400n8
```

Linux 的显式 `earlycon=uart8250,...` 不会从 DTS 的 UART `clock-frequency` 自动读取时钟。若参数未携带 UART clock，earlycon 会使用默认 `BASE_BAUD * 16 = 1843200 Hz`。

因此 earlycon 会按错误时钟计算 divisor：

```text
1843200 / (16 * 230400) ~= 0.5 -> divisor = 1
```

而 FPGA UART 实际挂在 100MHz `sys_clk` 上，正确 divisor 应为：

```text
100000000 / (16 * 230400) ~= 27
```

结果是 Linux earlycon 阶段把 UART 分频器改坏，导致早期 kernel 日志以错误 baud 发出，PC 端看不到有效输出。

## 为什么只看到四行

OpenSBI 自己配置 UART，所以 OpenSBI 输出正常。

Linux earlycon 进入后重新配置 divisor，但因为缺少 clock 参数而设置错误，早期 kernel 日志不可见。

等 real 8250 console 注册时，driver 会根据 DTS 中的：

```dts
clock-frequency = <100000000>;
```

重新配置 UART divisor，所以 console handover 附近的少量日志能够被正确输出。这造成了“前面没有日志，只有中后段四行”的假象。

## 修复

在 `linux/dts/simplecpu.dts` 的 `bootargs` 中为 earlycon 显式传入 100MHz UART clock：

```text
earlycon=uart8250,mmio32,0x10008000,230400n8,100000000
```

修复后 FPGA 日志确认 Linux 能完整输出到预期的 init 缺失 panic：

```text
earlycon: uart8250 at MMIO32 0x10008000 (options '230400n8,100000000')
devtmpfs: mounted
Kernel panic - not syncing: No working init found.
```

## 结论

这不是 RTL UART、PLIC、SEIP 或 FIFO 的根因问题；核心问题是 kernel earlycon 的 UART clock 参数缺失，导致 earlycon divisor 配置错误。

