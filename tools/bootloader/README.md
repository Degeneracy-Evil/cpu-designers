# Bootloader - FPGA 串口烧录工具

通过串口将指令和数据二进制文件烧录至 FPGA 的工具，基于 YMODEM-like 协议实现可靠传输。

## 功能概述

- **二进制文件烧录**：将 `.inst.bin`（指令）和 `.data.bin`（数据）文件通过串口烧录到 FPGA
- **CRC16 校验**：每个数据包附带 CRC16 校验码，确保传输完整性
- **ACK/NACK 握手**：每包发送后等待设备 ACK 确认，失败时自动报告
- **字节序转换**：自动对每 4 字节进行大小端交换，适配 FPGA 端数据格式
- **RSA 加密通信**：`rsa.py` 支持向 FPGA 发送 RSA 待加密数据并接收结果
- **优雅退出**：支持 `Ctrl+C` 安全退出，自动关闭串口

## 环境要求

- Python 3.6+
- pyserial

```bash
pip install pyserial
```

## 硬件连接

1. 使用串口转换线（FT232，龙芯实验箱自带）将实验箱串口与电脑 USB 端口连接
2. 从设备管理器中查看串口编号（如 `COM3`、`/dev/ttyUSB0`）

## 使用方法

### 烧录二进制文件

```bash
python main.py <串口> <文件名前缀>
```

示例：

```bash
python main.py COM3 comprehensive_test
```

程序将自动读取以下两个文件：
- `comprehensive_test.inst.bin` — 指令存储器数据（`.text` 段）
- `comprehensive_test.data.bin` — 数据存储器数据（`.data`+`.rodata`+`.sdata` 段）

### 生成烧录文件

使用 `rv2coe.py` 从汇编/C 源码生成分离的指令/数据二进制文件：

```bash
python3 ../rv2coe.py -i app.S --inst-bin app.inst.bin --data-bin app.data.bin
```

也可同时生成 COE/hex 格式（用于仿真初始化）：

```bash
python3 ../rv2coe.py -i app.S \
  --inst-bin app.inst.bin --inst-coe app.inst.coe \
  --data-bin app.data.bin --data-coe app.data.coe
```

> **注意**：每次烧录前请按下 FPGA 的复位按钮，确保 FPGA 处于复位状态。

烧录完成后，程序进入串口监听模式，实时显示 FPGA 输出。按 `Ctrl+C` 可安全退出。

### RSA 加密通信

```bash
python rsa.py <串口> <rsa_file_name>
```

从 `rsa_data.txt` 读取待加密数据，发送至 FPGA 并接收 RSA 运算结果。

### 串口测试

```bash
python test.py <串口> <file_name>
```

## 传输协议

| 字段 | 偏移 | 长度 | 说明 |
|------|------|------|------|
| 序号 | 0 | 1 字节 | 首包为类型标识（`0x00`=指令, `0xFF`=数据），后续为包序号 |
| 数据 | 1 | 128 字节 | 有效载荷（不足部分填零） |
| CRC16 低字节 | 129 | 1 字节 | CRC16-Modbus 校验低字节 |
| CRC16 高字节 | 130 | 1 字节 | CRC16-Modbus 校验高字节 |

- **包长度**：131 字节
- **CRC 算法**：CRC16-Modbus（多项式 `0xA001`，初始值 `0xFFFF`）
- **首包特殊字段**：偏移 1 处存放总包数（而非数据）

## 项目结构

```
bootloader/
├── main.py              # 主烧录程序
├── rsa.py               # RSA 加密通信程序
├── test.py              # 串口测试程序
├── back-up/             # 备份的二进制文件
│   ├── *.inst.bin
│   └── *.data.bin
├── comprehensive_test.inst.bin
├── comprehensive_test.data.bin
└── 烧录过程.md           # 烧录操作说明
```

## 退出方式

程序运行中按 `Ctrl+C` 即可安全退出，串口会自动关闭。烧录过程中按 `Ctrl+C` 也会中断传输并安全退出。
