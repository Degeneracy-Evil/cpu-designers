# 02 - 架构选型

## 1. ISA

- **基础指令集**：RISC-V RV32I
- **CSR 扩展**：Zicsr
- **指令缓存扩展**：Zifencei（FENCE.I 作为 NOP）
- 普通指令行为参考 RISC-V 非特权手册
- 异常、中断、trap 机制参考 RISC-V 特权手册（精简子集）

## 2. 微结构

- **结构**：哈佛结构，指令存储与数据存储分离
- **控制方式**：多周期 FSM
- **数据位宽**：32 bit
- **特权模式**：M-mode + U-mode（不实现 S-mode）

## 3. 存储结构

- 采用 L1 存储分离结构（哈佛）：
  - `iCache`：指令侧 L1（由 `instr_mem` + `icache` IP 实现）
  - `dCache`：数据侧 L1（由 `data_mem` + `dcache` IP 实现）
- 当前阶段不接主存（不实现 L2/DDR/AXI 总线），CPU 访存全部落在 L1
- `iCache` / `dCache` 均按 32 bit 字寻址（地址低 2 位用于字内字节选择）
- dCache 地址空间后续通过地址译码区分缓存空间与 MMIO 外设空间

> 说明：`dcache` 模块名来自 IP 工程命名，实际按当前工程配置使用 32-bit × 2048 深度。

### 3.1 BRAM 接口约定

底层采用双端口 BRAM IP 接口：

```verilog
module dcache4(
    input         clka,
    input         ena,
    input  [0:0]  wea,
    input  [10:0] addra,
    input  [31:0] dina,
    output [31:0] douta,
    input         clkb,
    input         enb,
    input  [0:0]  web,
    input  [10:0] addrb,
    input  [31:0] dinb,
    output [31:0] doutb
);
```

- `wea/web` 为单 bit 端口写使能
- `addra/addrb` 为 11 bit 字地址（对应 CPU 地址 `[12:2]`）
- `dout*` 为读数据端口

## 4. ALU

- 复用 `dev/1-alu` 中 32 bit ALU
- ALU 控制信号为 16 bit one-hot 编码（详见 `dev/1-alu/AGENTS.md`）
- ALU接口详见`dev/1-alu/docs/ALU_INTERFACE.md`
- 通过 `alu_wrapper` 模块对接 ALU 接口与 CPU 数据通路

## 5. 外设与中断

- 外设：GPIO + UART
- 中断：一级外部中断，优先 UART RX 中断
- 外设接入方式：Memory-Mapped I/O（MMIO）
