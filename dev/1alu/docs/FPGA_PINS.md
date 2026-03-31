# FPGA引脚命名对应表

## 拨码开关引脚

| 名字     | 引脚 | 说明 |
| -------- | ---- | ---- |
| FPGA_SW0 | AC21 | 拨码开关0 |
| FPGA_SW1 | AD24 | 拨码开关1 |
| FPGA_SW2 | AC22 | 拨码开关2 |
| FPGA_SW3 | AC23 | 拨码开关3 |
| FPGA_SW4 | AB6  | 拨码开关4 |
| FPGA_SW5 | W6   | 拨码开关5 |
| FPGA_SW6 | AA7  | 拨码开关6 |
| FPGA_SW7 | Y6   | 拨码开关7 |

## 时钟和复位引脚

| 名字   | 引脚 | 说明 |
| ------ | ---- | ---- |
| clk    | AC19 | 时钟信号 (100MHz) |
| resetn | Y3   | 复位信号 (低电平有效) |

## 触摸屏引脚

| 名字           | 引脚 | 说明 |
| -------------- | ---- | ---- |
| lcd_rst        | J25  | LCD复位 |
| lcd_cs         | H18  | LCD片选 |
| lcd_rs         | K16  | LCD寄存器选择 |
| lcd_wr         | L8   | LCD写信号 |
| lcd_rd         | K8   | LCD读信号 |
| lcd_bl_ctr     | J15  | LCD背光控制 |
| lcd_data_io[0] | H9   | LCD数据位0 |
| lcd_data_io[1] | K17  | LCD数据位1 |
| lcd_data_io[2] | J20  | LCD数据位2 |
| lcd_data_io[3] | M17  | LCD数据位3 |
| lcd_data_io[4] | L17  | LCD数据位4 |
| lcd_data_io[5] | L18  | LCD数据位5 |
| lcd_data_io[6] | L15  | LCD数据位6 |
| lcd_data_io[7] | M15  | LCD数据位7 |
| lcd_data_io[8] | M16  | LCD数据位8 |
| lcd_data_io[9] | L14  | LCD数据位9 |
| lcd_data_io[10]| M14  | LCD数据位10 |
| lcd_data_io[11]| F22  | LCD数据位11 |
| lcd_data_io[12]| G22  | LCD数据位12 |
| lcd_data_io[13]| G21  | LCD数据位13 |
| lcd_data_io[14]| H24  | LCD数据位14 |
| lcd_data_io[15]| J16  | LCD数据位15 |
| ct_int         | L19  | 触摸中断 |
| ct_sda         | J24  | 触摸I2C数据 |
| ct_scl         | H21  | 触摸I2C时钟 |
| ct_rstn        | G24  | 触摸复位 |

## 使用说明

1. **复位信号**: 本项目使用低电平复位(`resetn`)，与FPGA板一致
2. **时钟频率**: 100MHz
3. **IO标准**: LVCMOS33
4. **拨码开关**: 用于选择输入数据类型
   - `input_sel[1:0]` = 00: 输入控制信号
   - `input_sel[1:0]` = 10: 输入源操作数1
   - `input_sel[1:0]` = 11: 输入源操作数2