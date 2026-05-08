# APB 总线实现进度

## 协议版本

APB4（支持 PPROT、PSTRB、PREADY、PSLVERR）

## 实现文件

### 总线基础设施

| 文件 | 描述 | 状态 |
|------|------|------|
| `apb_def.vh` | 公共宏定义：地址/数据/选通/保护位宽，FSM 状态编码 | ✅ 完成 |
| `apb_master.v` | APB 主设备（Requester）：三态 FSM（IDLE→SETUP→ACCESS），驱动 APB 总线信号 | ✅ 完成 |
| `apb_slave.v` | APB 通用从设备（Completer）：寄存器阵列，支持 PSTRB 字节写、PREADY 等待、PSLVERR 错误 | ✅ 完成 |
| `apb_decoder.v` | 地址译码器：根据地址高位生成 PSELx 选择信号，支持 1/2/4/8 从设备 | ✅ 完成 |
| `apb_bus.v` | 顶层 APB 总线：集成 master + decoder + N×slave，多路选择 PREADY/PRDATA/PSLVERR | ✅ 完成 |

### APB 外设（perips/）

| 文件 | 描述 | 状态 |
|------|------|------|
| `perips/gpio.v` | GPIO 外设：APB 接口，16 位可编程 IO，CTRL/DATA 双寄存器 | ✅ 完成 |
| `perips/timer.v` | 定时器外设：APB 接口，单次/周期模式，IRQ 中断 | ✅ 完成 |
| `perips/uart_top.v` | UART 外设：APB 接口，TX/RX 子模块，可配置波特率 | ✅ 完成 |
| `perips/spi.v` | SPI 外设：APB 接口，CPOL/CPHA 可配，可编程分频 | ✅ 完成 |
| `perips/apb_perips.v` | 外设集成模块：4 外设统一接入，地址译码 PSELx 分配 | ✅ 完成 |

### AHB-Lite 桥接

| 文件 | 描述 | 状态 |
|------|------|------|
| `ahb_lite_to_apb.v` | AHB-Lite → APB 桥：流水线→非流水线转换，HSIZE→PSTRB 映射，HPROT→PPROT 映射，ERROR 两周期响应 | ✅ 完成 |

## 模块架构

### APB 总线内部

```
          req_valid / req_write / req_addr / req_wdata / req_strb / req_prot
                                      │
                                      ▼
                               ┌─────────────┐
                               │  apb_master  │
                               │  (Requester) │
                               └──────┬───────┘
                                      │ PADDR/PWRITE/PWDATA/PSTRB/PPROT/PENABLE/PSEL
                                      ▼
                               ┌─────────────┐
                               │  apb_decoder │
                               └──────┬───────┘
                                      │ PSELx[SLAVE_NUM-1:0]
                                      ▼
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                 ▼
              ┌──────────┐     ┌──────────┐       ┌──────────┐
              │apb_slave0│     │apb_slave1│  ...  │apb_slaveN│
              │(Completer)│     │(Completer)│       │(Completer)│
              └────┬─────┘     └────┬─────┘       └────┬─────┘
                   │                │                   │
                   └────────────────┼───────────────────┘
                                    ▼
                          PREADY / PRDATA / PSLVERR (MUX)
                                    │
                                    ▼
                          resp_valid / resp_rdata / resp_error
```

### APB 外设集成（apb_perips）

```
                    PADDR / PWRITE / PWDATA / PSTRB / PPROT / PENABLE
                                      │
                                      ▼
                               ┌─────────────┐
                               │ apb_decoder  │  (地址高位译码)
                               └──────┬───────┘
                                      │ PSELx[3:0]
                                      ▼
              ┌───────────┬───────────┼───────────┐
              ▼           ▼           ▼           ▼
        ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
        │  GPIO   │ │  Timer  │ │  UART   │ │   SPI   │
        │ PSELx[0]│ │ PSELx[1]│ │ PSELx[2]│ │ PSELx[3]│
        └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘
             │           │           │           │
             └───────────┴───────────┴───────────┘
                         ▼
                PREADY / PRDATA / PSLVERR (MUX)
```

### AHB-Lite → APB 桥接

```
   AHB-Lite 主设备侧                         APB 从设备侧
   ───────────────                          ─────────────
   HADDR  ──┐
   HTRANS ──┤
   HWRITE ──┤    ┌───────────────────┐     PADDR   ────>
   HSIZE  ──┼───>│  ahb_lite_to_apb  │───> PWRITE  ────>
   HBURST ──┤    │     (Bridge)      │───> PSEL    ────>
   HPROT  ──┤    │                   │───> PENABLE ────>
   HWDATA ──┤    │  IDLE→SETUP→     │───> PWDATA  ────>
   HSEL   ──┤    │  ACCESS FSM      │───> PSTRB   ────>
   HREADY ──┘    │                   │───> PPROT   ────>
                 └───────────────────┘
                 <─── HREADYOUT        <─── PREADY
                 <─── HRESP            <─── PRDATA
                                           <─── PSLVERR
```

## FSM 状态机

### APB Master

```
          req_valid=1
  IDLE ──────────────> SETUP
   ↑                     │
   │                     │ (无条件，下一时钟沿)
   │                     ↓
   │                 ACCESS
   │                PENABLE=1
   │                     │
   │    PREADY=1         │ PREADY=0 (保持)
   └─────────────────────┘
```

### AHB-Lite → APB Bridge

```
          HSEL & HREADY & HTRANS!=IDLE
  IDLE ──────────────────────────────> SETUP
   ↑                                     │
   │                                     │ (无条件)
   │                                     ↓
   │                                 ACCESS (PENABLE=1)
   │                                     │
   │    PREADY=1 & !PSLVERR             │ PREADY=0 (保持)
   │    & !ahb_transfer                  │
   └─────────────────────────────────────┘
   (PREADY=1 & PSLVERR → ERROR 两周期响应)
   (PREADY=1 & ahb_transfer → 直入下一 SETUP)
```

## 关键设计决策

1. **APB4 版本**：包含 PPROT（保护类型）和 PSTRB（写选通），兼顾功能与复杂度
2. **地址译码**：使用地址高位进行等分译码，每个从设备占等大地址空间
3. **PSTRB 写逻辑**：仅更新 PSTRB[i]=1 对应的字节，读传输时 PSTRB 全零
4. **PSLVERR**：从设备默认不报错（PSLVERR=0），仅在传输最后周期有效
5. **PREADY**：从设备默认无等待状态（PREADY=1），可按需拉低插入等待

### 外设接口转换

原 bus4lzu 接口 → APB4 接口映射：

| 原信号 | APB 信号 | 说明 |
|--------|----------|------|
| `i_cs_1==0 & i_as_1==0` | `PSEL & PENABLE` | 传输有效 |
| `i_rw_1==0` (WRITE) | `PWRITE==1` | 写方向（逻辑取反） |
| `i_rw_1==1` (READ) | `PWRITE==0` | 读方向 |
| `o_rdy_1==0` (ready) | `PREADY==1` | 就绪（逻辑取反） |
| `i_addr_32` | `PADDR` | 地址 |
| `i_data_32` / `i_wrData_32` | `PWDATA` | 写数据 |
| `o_data_32` / `o_rdData_32` | `PRDATA` | 读数据 |

### AHB-Lite → APB 桥接映射

| AHB-Lite 信号 | APB 信号 | 说明 |
|---------------|----------|------|
| `HADDR` | `PADDR` | 地址直连 |
| `HWRITE` | `PWRITE` | 方向直连 |
| `HWDATA` | `PWDATA` | 写数据（ACCESS 阶段锁存） |
| `HSIZE` | `PSTRB` | 传输大小→字节选通映射 |
| `HPROT[3:0]` | `PPROT[2:0]` | 保护属性重映射 |
| `HREADYOUT` | ← `PREADY` | 就绪反压 |
| `HRESP` | ← `PSLVERR` | 错误响应（AHB 两周期→APB 单周期） |
| `HTRANS` | — | 触发桥 FSM 启动 APB 传输 |

## 待完成

- [ ] Testbench 验证
- [ ] 支持可配置从设备地址区间（非等分译码）
- [ ] AXI-to-APB 桥接
