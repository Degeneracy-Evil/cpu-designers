# AMBA APB 协议规范总结

> 来源：ARM IHI 0024E (ID022823)，AMBA APB Protocol Specification，Issue E，2023  
> 用途：开发参考，中文摘要

---

## 1. 协议概述

APB（Advanced Peripheral Bus）是 AMBA 总线架构中的**低成本外设接口**协议，具有以下核心特征：

- **非流水线**、简单的**同步协议**
- 每次传输至少需要 **2 个时钟周期**完成
- 优化目标：**最小功耗**、**接口复杂度最低**
- 典型用途：访问外设的**可编程控制寄存器**
- APB 外设通过 **APB 桥**（Bridge）连接到主存储系统（如 AXI-to-APB 桥）

### 术语

| 术语 | 含义 |
|------|------|
| **Requester** | 发起 APB 传输的桥/主设备 |
| **Completer** | 响应请求的外设/从设备 |

---

## 2. APB 版本演进

| 版本 | Issue | 新增功能 | 新增信号 |
|------|-------|----------|----------|
| APB2 | A | 基础协议 | — |
| APB3 | B | 等待状态、错误报告 | `PREADY`, `PSLVERR` |
| APB4 | C | 事务保护、稀疏数据传输 | `PPROT`, `PSTRB` |
| APB5 | D | 唤醒信号、用户信号、奇偶校验保护 | `PWAKEUP`, `PAUSER/PWUSER/PRUSER/PBUSER`, 校验信号 |
| APB5 | E | RME（Realm Management Extension）支持 | `PNSE` |

---

## 3. 信号描述

### 3.1 核心信号一览

| 信号 | 方向 | 宽度 | 描述 |
|------|------|------|------|
| `PCLK` | Clock | 1 | 时钟，所有信号在 **PCLK 上升沿**采样 |
| `PRESETn` | System | 1 | 复位，**低电平有效**，通常直连系统总线复位 |
| `PADDR` | Requester | ADDR_WIDTH (最大32) | 地址总线，字节寻址 |
| `PPROT` | Requester | 3 | 保护类型（正常/特权/安全/指令/数据） |
| `PNSE` | Requester | 1 | RME 扩展保护信号 |
| `PSELx` | Requester | 1 | 选择信号，每个 Completer 一个，表示被选中 |
| `PENABLE` | Requester | 1 | 使能信号，表示传输的第二个及后续周期 |
| `PWRITE` | Requester | 1 | 方向：HIGH=写，LOW=读 |
| `PWDATA` | Requester | DATA_WIDTH (8/16/32) | 写数据总线 |
| `PSTRB` | Requester | DATA_WIDTH/8 | 写选通，每字节一个，`PSTRB[n]` 对应 `PWDATA[(8n+7):(8n)]` |
| `PREADY` | Completer | 1 | 就绪信号，用于插入等待状态 |
| `PRDATA` | Completer | DATA_WIDTH (8/16/32) | 读数据总线 |
| `PSLVERR` | Completer | 1 | 传输错误（可选），HIGH 表示错误 |
| `PWAKEUP` | Requester | 1 | 唤醒信号（APB5），无毛刺 |
| `PAUSER` | Requester | USER_REQ_WIDTH (建议≤128) | 用户请求属性 |
| `PWUSER` | Requester | USER_DATA_WIDTH (建议≤DATA_WIDTH/2) | 用户写数据属性 |
| `PRUSER` | Completer | USER_DATA_WIDTH | 用户读数据属性 |
| `PBUSER` | Completer | USER_RESP_WIDTH (建议≤16) | 用户响应属性 |

### 3.2 地址总线

- 单一地址总线 `PADDR`，读写共用
- **字节地址**寻址
- 允许非对齐地址，但结果 **UNPREDICTABLE**

### 3.3 数据总线

- 两个独立数据总线：`PRDATA`（读）和 `PWDATA`（写）
- 宽度可为 **8/16/32 位**，读写宽度必须相同
- 读写**不能并发**（无独立握手信号）

---

## 4. 传输机制

### 4.1 写传输

#### 无等待状态

```
T0    T1        T2          T3    T4
      SETUP     ACCESS
      PSEL=1    PENABLE=1
      PADDR有效  PREADY=1 → 完成
```

- **SETUP 阶段**（T1）：`PSEL` 置 1，`PADDR`/`PWRITE`/`PWDATA` 必须有效
- **ACCESS 阶段**（T2）：`PENABLE` 置 1，Completer 在 PCLK 上升沿通过 `PREADY=1` 表示接受
- 传输结束：`PENABLE` 拉低，`PSEL` 也拉低（除非连续传输到同一外设）

#### 有等待状态

- ACCESS 阶段中 Completer 驱动 `PREADY=LOW` 延长传输
- 等待期间以下信号**保持不变**：`PADDR`, `PWRITE`, `PSELx`, `PENABLE`, `PWDATA`, `PSTRB`, `PPROT`, `PAUSER`, `PWUSER`
- `PENABLE=LOW` 时 `PREADY` 可为任意值（固定两周期访问的外设可将 `PREADY` 接 HIGH）

### 4.2 写选通（PSTRB）

- 使能稀疏数据传输，每个 `PSTRB` 对应 1 字节
- `PSTRB[n]` 对应 `PWDATA[(8n+7):(8n)]`
- 32 位数据总线的映射：`PSTRB[3]→PWDATA[31:24]`, `PSTRB[2]→PWDATA[23:16]`, `PSTRB[1]→PWDATA[15:8]`, `PSTRB[0]→PWDATA[7:0]`
- **读传输时 Requester 必须将 PSTRB 全部驱动为 LOW**
- PSTRB 为可选信号

### 4.3 读传输

- 时序与写传输相同（地址、选择、使能信号一致）
- Completer 必须在传输结束前提供数据
- 同样支持通过 `PREADY` 插入等待状态

### 4.4 错误响应（PSLVERR）

- 仅在传输**最后一个周期**（`PSEL=1 && PENABLE=1 && PREADY=1`）有效
- 建议在 `PSEL`/`PENABLE`/`PREADY` 为 LOW 时驱动 `PSLVERR=LOW`（非强制）
- 写错误**不保证**外设寄存器未被更新
- 读错误返回的数据**无效**，但不保证全 0
- Completer 不支持 `PSLVERR` 时，Requester 侧输入接 LOW

**桥接错误映射：**

- AXI → APB：`PSLVERR` 映射为读 `RRESP` / 写 `BRESP`
- AHB → APB：`PSLVERR` 映射为 `HRESP`

---

## 5. 保护单元支持（PPROT）

`PPROT[2:0]` 提供事务保护：

| 位 | 含义 | LOW | HIGH |
|----|------|-----|------|
| `PPROT[0]` | 正常/特权 | 正常访问 | 特权访问 |
| `PPROT[1]` | 安全/非安全 | 安全访问 | 非安全访问 |
| `PPROT[2]` | 数据/指令 | 数据访问 | 指令访问（提示，可能不准确） |

> 主要用途：标识安全/非安全事务。`PPROT[0]` 和 `PPROT[2]` 的解释可不同。

---

## 6. RME 支持（PNSE）

APB5 Issue E 新增 `PNSE` 信号，与 `PPROT[1]` 组合确定物理地址空间：

| `PNSE` | `PPROT[1]` | 物理地址空间 |
|--------|------------|-------------|
| 0 | 0 | Secure |
| 0 | 1 | Non-secure |
| 1 | 0 | Root |
| 1 | 1 | Realm |

- `PNSE` 存在时，`PPROT` 必须也存在
- `PNSE` 由 `PCTRLCHK` 信号进行奇偶校验保护

---

## 7. 唤醒信号（PWAKEUP）

- 指示 APB 接口上的任何活动，**无毛刺**
- 可路由到时钟控制器以启用电源/时钟
- 仅 APB5 支持

**规则：**

- 同步于 `PCLK`，必须适合跨时钟域异步采样
- 可在 `PSELx` 之前、期间或之后置位
- Completer 可等待 `PWAKEUP` 置位后才置位 `PREADY`（若 `PWAKEUP` 存在但从不置位会导致死锁）
- 若 `PWAKEUP` 和 `PSELx` 在同一周期为 HIGH，`PWAKEUP` 必须保持到 `PREADY` 置位
- 建议在 `PSELx` 置位前至少一个周期置位 `PWAKEUP`
- 建议无后续传输时解除断言 `PWAKEUP`

---

## 8. 用户信号

- 仅 APB5 支持，均为可选
- `PAUSER`：PSELx 置位时有效，SETUP 和 ACCESS 阶段值不变
- `PWUSER`：PSEL && PWRITE 置位时有效，SETUP 和 ACCESS 阶段值不变
- `PRUSER`：PSEL && PENABLE && PREADY 置位且 PWRITE=0 时有效
- `PBUSER`：PSEL && PENABLE && PREADY 置位时有效
- 建议不在一般设计中使用（互操作性问题）

---

## 9. 操作状态机

APB 接口有三个操作状态：

```
         PSELx=1
  IDLE ──────────> SETUP
   ↑                 │
   │                 │ (下一时钟沿，始终转移)
   │                 ↓
   │             ACCESS
   │            PENABLE=1
   │                 │
   │    PREADY=1     │ PREADY=0 (保持)
   └─────────────────┘
```

| 状态 | 条件 | 说明 |
|------|------|------|
| **IDLE** | `PSELx=0` | 默认空闲状态 |
| **SETUP** | `PSELx=1, PENABLE=0` | 仅持续 1 个时钟周期，下一周期必定进入 ACCESS |
| **ACCESS** | `PSELx=1, PENABLE=1` | `PREADY=0` 保持；`PREADY=1` 退出至 IDLE 或下一 SETUP |

**ACCESS 阶段信号保持不变：**
`PADDR`, `PPROT`, `PWRITE`, `PWDATA`（写时）, `PSTRB`, `PAUSER`, `PWUSER`

---

## 10. 接口奇偶校验保护（APB5）

### 10.1 配置

由 `Check_Type` 属性定义：

- `False`：无校验信号（默认）
- `Odd_Parity_Byte_All`：对所有信号使用奇校验，每个校验位最多覆盖 8 位

### 10.2 校验规则

- 使用**奇校验**（接口信号 + 校验信号中 1 的总数为奇数）
- 每个校验位最多覆盖 8 位负载
- 关键控制信号使用**单比特校验**（校验位 = 原信号取反）
- 校验位 `n` 对应负载 `[(8n+7):8n]`
- 校验信号在 Check Enable 为 True 的每个周期必须正确驱动

### 10.3 校验信号列表

| 校验信号 | 覆盖信号 | 宽度 | Check Enable |
|----------|----------|------|-------------|
| `PADDRCHK` | PADDR | ceil(ADDR_WIDTH/8) | PSEL |
| `PCTRLCHK` | PPROT, PWRITE, PNSE | 1 | PSEL |
| `PSELxCHK` | PSELx | 1 | PRESETn |
| `PENABLECHK` | PENABLE | 1 | PSEL |
| `PWDATACHK` | PWDATA | DATA_WIDTH/8 | PSEL & PWRITE |
| `PSTRBCHK` | PSTRB | 1 | PSEL & PWRITE |
| `PREADYCHK` | PREADY | 1 | PSEL & PENABLE |
| `PRDATACHK` | PRDATA | DATA_WIDTH/8 | PSEL & PENABLE & PREADY & !PWRITE |
| `PSLVERRCHK` | PSLVERR | 1 | PSEL & PENABLE & PREADY |
| `PWAKEUPCHK` | PWAKEUP | 1 | PRESETn |
| `PAUSERCHK` | PAUSER | ceil(USER_REQ_WIDTH/8) | PSEL |
| `PWUSERCHK` | PWUSER | ceil(USER_DATA_WIDTH/8) | PSEL & PWRITE |
| `PRUSERCHK` | PRUSER | ceil(USER_DATA_WIDTH/8) | PSEL & PENABLE & PREADY & !PWRITE |
| `PBUSERCHK` | PBUSER | ceil(USER_RESP_WIDTH/8) | PSEL & PENABLE & PREADY |

### 10.4 错误检测行为

检测到奇偶错误时，Completer 可以：

- 终止或传播传输
- 校正校验信号或传播错误
- 更新或不更新存储器
- 通过其他方式（如中断）报告错误

---

## 11. 信号有效性规则

| 条件 | 必须有效的信号 |
|------|---------------|
| 始终 | `PSEL`, `PWAKEUP` |
| PSEL=1 | `PADDR`, `PPROT`, `PNSE`, `PENABLE`, `PWRITE`, `PAUSER`, `PSTRB`, `PWDATA`（写有效字节）, `PWUSER`（写时） |
| PSEL=1 && PENABLE=1 | `PREADY` |
| PSEL=1 && PENABLE=1 && PREADY=1 | `PRDATA`（读时）, `PSLVERR`, `PRUSER`（读时）, `PBUSER` |

> 建议将不需要有效的信号驱动为 0。

---

## 12. 各版本信号支持矩阵

| 信号 | APB2 | APB3 | APB4 | APB5 |
|------|------|------|------|------|
| PCLK | Y | Y | Y | Y |
| PRESETn | Y | Y | Y | Y |
| PADDR | Y | Y | Y | Y |
| PPROT | N | N | O | O |
| PNSE | N | N | N | C |
| PSELx | Y | Y | Y | Y |
| PENABLE | Y | Y | Y | Y |
| PWRITE | Y | Y | Y | Y |
| PWDATA | Y | Y | Y | Y |
| PSTRB | N | N | O | O |
| PREADY | N | OO | OO | OO |
| PRDATA | Y | Y | Y | Y |
| PSLVERR | N | OO | OO | OO |
| PWAKEUP | N | N | N | C |
| PAUSER | N | N | N | OC |
| PWUSER | N | N | N | OC |
| PRUSER | N | N | N | OC |
| PBUSER | N | N | N | OC |

> Y=必须, N=不存在, O=可选, OO=输出可选/输入必须, C=条件(属性为True时必须), OC=可选条件

---

## 13. 开发要点速查

### 最小 APB3 实现所需信号

`PCLK`, `PRESETn`, `PADDR`, `PSELx`, `PENABLE`, `PWRITE`, `PWDATA`, `PREADY`, `PRDATA`

### 典型写传输时序（APB3+）

```
周期1 (SETUP):  PSELx=1, PENABLE=0, PADDR/PWRITE/PWDATA 有效
周期2 (ACCESS): PENABLE=1, 等待 PREADY=1
周期3+:         PREADY=1 → 传输完成, PENABLE=0, PSELx=0
```

### 典型读传输时序（APB3+）

```
周期1 (SETUP):  PSELx=1, PENABLE=0, PADDR 有效, PWRITE=0
周期2 (ACCESS): PENABLE=1, 等待 PREADY=1, PRDATA 有效
周期3+:         PREADY=1 → 传输完成
```

### 关键设计约束

1. 所有信号在 **PCLK 上升沿**采样
2. 传输至少 **2 个周期**（SETUP + ACCESS）
3. SETUP 阶段仅 **1 个周期**，必定转入 ACCESS
4. ACCESS 阶段可通过 `PREADY=0` 任意延长
5. 等待期间地址/数据/控制信号**必须保持稳定**
6. `PSTRB` 读传输时必须全为 0
7. `PSLVERR` 仅在传输最后周期有效
8. `PRESETn` 低电平有效
