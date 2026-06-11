# FPGA约束文件 - System Top (CPU + AXI4 Bus + DDR3 MIG)
# Target: xc7a200t-fbg676-2 (龙芯杯开发板)

# 时钟信号连接 (100MHz external crystal)
set_property PACKAGE_PIN AC19 [get_ports clk]

# 复位信号，低电平有效
set_property PACKAGE_PIN Y3 [get_ports resetn]

# 单步调试按键，低电平有效
# set_property PACKAGE_PIN Y5 [get_ports btn_clk]

# 拨码开关 SW0-SW7
set_property PACKAGE_PIN AC21 [get_ports {sw[0]}]
set_property PACKAGE_PIN AD24 [get_ports {sw[1]}]
set_property PACKAGE_PIN AC22 [get_ports {sw[2]}]
set_property PACKAGE_PIN AC23 [get_ports {sw[3]}]
set_property PACKAGE_PIN AB6  [get_ports {sw[4]}]
set_property PACKAGE_PIN W6   [get_ports {sw[5]}]
set_property PACKAGE_PIN AA7  [get_ports {sw[6]}]
set_property PACKAGE_PIN Y6   [get_ports {sw[7]}]

# IO标准设置
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports resetn]
# set_property IOSTANDARD LVCMOS33 [get_ports btn_clk]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[7]}]

# 触摸屏引脚连接
set_property PACKAGE_PIN J25 [get_ports lcd_rst]
set_property PACKAGE_PIN H18 [get_ports lcd_cs]
set_property PACKAGE_PIN K16 [get_ports lcd_rs]
set_property PACKAGE_PIN L8  [get_ports lcd_wr]
set_property PACKAGE_PIN K8  [get_ports lcd_rd]
set_property PACKAGE_PIN J15 [get_ports lcd_bl_ctr]
set_property PACKAGE_PIN H9  [get_ports {lcd_data_io[0]}]
set_property PACKAGE_PIN K17 [get_ports {lcd_data_io[1]}]
set_property PACKAGE_PIN J20 [get_ports {lcd_data_io[2]}]
set_property PACKAGE_PIN M17 [get_ports {lcd_data_io[3]}]
set_property PACKAGE_PIN L17 [get_ports {lcd_data_io[4]}]
set_property PACKAGE_PIN L18 [get_ports {lcd_data_io[5]}]
set_property PACKAGE_PIN L15 [get_ports {lcd_data_io[6]}]
set_property PACKAGE_PIN M15 [get_ports {lcd_data_io[7]}]
set_property PACKAGE_PIN M16 [get_ports {lcd_data_io[8]}]
set_property PACKAGE_PIN L14 [get_ports {lcd_data_io[9]}]
set_property PACKAGE_PIN M14 [get_ports {lcd_data_io[10]}]
set_property PACKAGE_PIN F22 [get_ports {lcd_data_io[11]}]
set_property PACKAGE_PIN G22 [get_ports {lcd_data_io[12]}]
set_property PACKAGE_PIN G21 [get_ports {lcd_data_io[13]}]
set_property PACKAGE_PIN H24 [get_ports {lcd_data_io[14]}]
set_property PACKAGE_PIN J16 [get_ports {lcd_data_io[15]}]
set_property PACKAGE_PIN L19 [get_ports ct_int]
set_property PACKAGE_PIN J24 [get_ports ct_sda]
set_property PACKAGE_PIN H21 [get_ports ct_scl]
set_property PACKAGE_PIN G24 [get_ports ct_rstn]

# 触摸屏IO标准设置
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rst]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_cs]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rs]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_wr]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rd]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_bl_ctr]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data_io[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports ct_int]
set_property IOSTANDARD LVCMOS33 [get_ports ct_sda]
set_property IOSTANDARD LVCMOS33 [get_ports ct_scl]
set_property IOSTANDARD LVCMOS33 [get_ports ct_rstn]

# UART引脚连接
set_property PACKAGE_PIN F23 [get_ports uart_rx]
set_property PACKAGE_PIN H19 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# SPI引脚连接 (SPI Flash)
set_property PACKAGE_PIN N18 [get_ports spi_miso]
set_property PACKAGE_PIN P19 [get_ports spi_mosi]
set_property PACKAGE_PIN R20 [get_ports spi_ss]
set_property PACKAGE_PIN P20 [get_ports spi_clk]
set_property IOSTANDARD LVCMOS33 [get_ports spi_miso]
set_property IOSTANDARD LVCMOS33 [get_ports spi_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports spi_ss]
set_property IOSTANDARD LVCMOS33 [get_ports spi_clk]

# GPIO引脚连接 (LED1-LED12, LED21-LED24, 低电平有效)
set_property PACKAGE_PIN H7  [get_ports {gpio_io[0]}]
set_property PACKAGE_PIN D5  [get_ports {gpio_io[1]}]
set_property PACKAGE_PIN A3  [get_ports {gpio_io[2]}]
set_property PACKAGE_PIN A5  [get_ports {gpio_io[3]}]
set_property PACKAGE_PIN A4  [get_ports {gpio_io[4]}]
set_property PACKAGE_PIN F7  [get_ports {gpio_io[5]}]
set_property PACKAGE_PIN G8  [get_ports {gpio_io[6]}]
set_property PACKAGE_PIN H8  [get_ports {gpio_io[7]}]
set_property PACKAGE_PIN J8  [get_ports {gpio_io[8]}]
set_property PACKAGE_PIN J23 [get_ports {gpio_io[9]}]
set_property PACKAGE_PIN J26 [get_ports {gpio_io[10]}]
set_property PACKAGE_PIN G9  [get_ports {gpio_io[11]}]
set_property PACKAGE_PIN J19 [get_ports {gpio_io[12]}]
set_property PACKAGE_PIN H23 [get_ports {gpio_io[13]}]
set_property PACKAGE_PIN J21 [get_ports {gpio_io[14]}]
set_property PACKAGE_PIN K23 [get_ports {gpio_io[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[15]}]

# GPIO控制寄存器输出引脚连接 (扩展IO EXT0_IO0-15)
set_property PACKAGE_PIN AD26 [get_ports {gpio_ctrl_out[0]}]
set_property PACKAGE_PIN T19  [get_ports {gpio_ctrl_out[1]}]
set_property PACKAGE_PIN T20  [get_ports {gpio_ctrl_out[2]}]
set_property PACKAGE_PIN AD25 [get_ports {gpio_ctrl_out[3]}]
set_property PACKAGE_PIN AE25 [get_ports {gpio_ctrl_out[4]}]
set_property PACKAGE_PIN AF25 [get_ports {gpio_ctrl_out[5]}]
set_property PACKAGE_PIN U22  [get_ports {gpio_ctrl_out[6]}]
set_property PACKAGE_PIN AF24 [get_ports {gpio_ctrl_out[7]}]
set_property PACKAGE_PIN U21  [get_ports {gpio_ctrl_out[8]}]
set_property PACKAGE_PIN V24  [get_ports {gpio_ctrl_out[9]}]
set_property PACKAGE_PIN V23  [get_ports {gpio_ctrl_out[10]}]
set_property PACKAGE_PIN W23  [get_ports {gpio_ctrl_out[11]}]
set_property PACKAGE_PIN AE23 [get_ports {gpio_ctrl_out[12]}]
set_property PACKAGE_PIN V22  [get_ports {gpio_ctrl_out[13]}]
set_property PACKAGE_PIN U25  [get_ports {gpio_ctrl_out[14]}]
set_property PACKAGE_PIN U26  [get_ports {gpio_ctrl_out[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_ctrl_out[15]}]

# GPIO数据寄存器输出引脚连接 (扩展IO EXT0_IO16-31)
set_property PACKAGE_PIN V26  [get_ports {gpio_data_out[0]}]
set_property PACKAGE_PIN U24  [get_ports {gpio_data_out[1]}]
set_property PACKAGE_PIN W25  [get_ports {gpio_data_out[2]}]
set_property PACKAGE_PIN W26  [get_ports {gpio_data_out[3]}]
set_property PACKAGE_PIN Y25  [get_ports {gpio_data_out[4]}]
set_property PACKAGE_PIN Y26  [get_ports {gpio_data_out[5]}]
set_property PACKAGE_PIN AB25 [get_ports {gpio_data_out[6]}]
set_property PACKAGE_PIN AB26 [get_ports {gpio_data_out[7]}]
set_property PACKAGE_PIN Y23  [get_ports {gpio_data_out[8]}]
set_property PACKAGE_PIN AC26 [get_ports {gpio_data_out[9]}]
set_property PACKAGE_PIN Y22  [get_ports {gpio_data_out[10]}]
set_property PACKAGE_PIN V21  [get_ports {gpio_data_out[11]}]
set_property PACKAGE_PIN V16  [get_ports {gpio_data_out[12]}]
set_property PACKAGE_PIN AA23 [get_ports {gpio_data_out[13]}]
set_property PACKAGE_PIN V14  [get_ports {gpio_data_out[14]}]
set_property PACKAGE_PIN U15  [get_ports {gpio_data_out[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_data_out[15]}]

# ============================================================
# DDR3 SDRAM constraints (MIG 7 Series)
# ============================================================
# Pin assignments from MIG IP config (Reference/mig/mig_a.prj)
# Verified against board schematic (Reference/pins.csv)
# MIG IP: MT41J64M16XX-125G, 16-bit, 800Mbps, 128MB
# The MIG IP generates its own internal timing constraints via XDC.

# --- DDR3 Address ---
set_property PACKAGE_PIN E18  [get_ports {ddr3_addr[0]}]
set_property PACKAGE_PIN H14  [get_ports {ddr3_addr[1]}]
set_property PACKAGE_PIN H15  [get_ports {ddr3_addr[2]}]
set_property PACKAGE_PIN G17  [get_ports {ddr3_addr[3]}]
set_property PACKAGE_PIN F17  [get_ports {ddr3_addr[4]}]
set_property PACKAGE_PIN F18  [get_ports {ddr3_addr[5]}]
set_property PACKAGE_PIN F19  [get_ports {ddr3_addr[6]}]
set_property PACKAGE_PIN G15  [get_ports {ddr3_addr[7]}]
set_property PACKAGE_PIN F15  [get_ports {ddr3_addr[8]}]
set_property PACKAGE_PIN G19  [get_ports {ddr3_addr[9]}]
set_property PACKAGE_PIN F20  [get_ports {ddr3_addr[10]}]
set_property PACKAGE_PIN H16  [get_ports {ddr3_addr[11]}]
set_property PACKAGE_PIN G16  [get_ports {ddr3_addr[12]}]

# --- DDR3 Bank Address ---
set_property PACKAGE_PIN C17  [get_ports {ddr3_ba[0]}]
set_property PACKAGE_PIN B17  [get_ports {ddr3_ba[1]}]
set_property PACKAGE_PIN E16  [get_ports {ddr3_ba[2]}]

# --- DDR3 Control ---
set_property PACKAGE_PIN A17  [get_ports ddr3_ras_n]
set_property PACKAGE_PIN A18  [get_ports ddr3_cas_n]
set_property PACKAGE_PIN B19  [get_ports ddr3_we_n]
set_property PACKAGE_PIN A19  [get_ports ddr3_reset_n]

# --- DDR3 Clock (differential) ---
set_property PACKAGE_PIN D18  [get_ports {ddr3_ck_p[0]}]
set_property PACKAGE_PIN C18  [get_ports {ddr3_ck_n[0]}]

# --- DDR3 CKE, ODT ---
set_property PACKAGE_PIN D16  [get_ports {ddr3_cke[0]}]
set_property PACKAGE_PIN E17  [get_ports {ddr3_odt[0]}]

# --- DDR3 Data Mask ---
set_property PACKAGE_PIN E21  [get_ports {ddr3_dm[0]}]
set_property PACKAGE_PIN D23  [get_ports {ddr3_dm[1]}]

# --- DDR3 Data (DQ) ---
set_property PACKAGE_PIN E20  [get_ports {ddr3_dq[0]}]
set_property PACKAGE_PIN C21  [get_ports {ddr3_dq[1]}]
set_property PACKAGE_PIN D19  [get_ports {ddr3_dq[2]}]
set_property PACKAGE_PIN A22  [get_ports {ddr3_dq[3]}]
set_property PACKAGE_PIN D20  [get_ports {ddr3_dq[4]}]
set_property PACKAGE_PIN B21  [get_ports {ddr3_dq[5]}]
set_property PACKAGE_PIN C19  [get_ports {ddr3_dq[6]}]
set_property PACKAGE_PIN B22  [get_ports {ddr3_dq[7]}]
set_property PACKAGE_PIN C22  [get_ports {ddr3_dq[8]}]
set_property PACKAGE_PIN B24  [get_ports {ddr3_dq[9]}]
set_property PACKAGE_PIN C23  [get_ports {ddr3_dq[10]}]
set_property PACKAGE_PIN B26  [get_ports {ddr3_dq[11]}]
set_property PACKAGE_PIN A25  [get_ports {ddr3_dq[12]}]
set_property PACKAGE_PIN C26  [get_ports {ddr3_dq[13]}]
set_property PACKAGE_PIN C24  [get_ports {ddr3_dq[14]}]
set_property PACKAGE_PIN B25  [get_ports {ddr3_dq[15]}]

# --- DDR3 Data Strobe (DQS, differential) ---
set_property PACKAGE_PIN B20  [get_ports {ddr3_dqs_p[0]}]
set_property PACKAGE_PIN A20  [get_ports {ddr3_dqs_n[0]}]
set_property PACKAGE_PIN A23  [get_ports {ddr3_dqs_p[1]}]
set_property PACKAGE_PIN A24  [get_ports {ddr3_dqs_n[1]}]

# --- DDR3 IOSTANDARD ---
set_property IOSTANDARD SSTL15       [get_ports {ddr3_addr[*]}]
set_property IOSTANDARD SSTL15       [get_ports {ddr3_ba[*]}]
set_property IOSTANDARD SSTL15       [get_ports ddr3_ras_n]
set_property IOSTANDARD SSTL15       [get_ports ddr3_cas_n]
set_property IOSTANDARD SSTL15       [get_ports ddr3_we_n]
set_property IOSTANDARD LVCMOS15     [get_ports ddr3_reset_n]
set_property IOSTANDARD DIFF_SSTL15  [get_ports {ddr3_ck_p[*]}]
set_property IOSTANDARD DIFF_SSTL15  [get_ports {ddr3_ck_n[*]}]
set_property IOSTANDARD SSTL15       [get_ports {ddr3_cke[*]}]
set_property IOSTANDARD SSTL15       [get_ports {ddr3_dm[*]}]
set_property IOSTANDARD SSTL15       [get_ports {ddr3_dq[*]}]
set_property IOSTANDARD DIFF_SSTL15  [get_ports {ddr3_dqs_p[*]}]
set_property IOSTANDARD DIFF_SSTL15  [get_ports {ddr3_dqs_n[*]}]
set_property IOSTANDARD SSTL15       [get_ports {ddr3_odt[*]}]

# --- DDR3 SLEW/IN_TERM (from MIG config) ---
set_property SLEW FAST [get_ports {ddr3_addr[*]}]
set_property SLEW FAST [get_ports {ddr3_ba[*]}]
set_property SLEW FAST [get_ports ddr3_ras_n]
set_property SLEW FAST [get_ports ddr3_cas_n]
set_property SLEW FAST [get_ports ddr3_we_n]
set_property SLEW FAST [get_ports ddr3_reset_n]
set_property SLEW FAST [get_ports {ddr3_ck_p[*]}]
set_property SLEW FAST [get_ports {ddr3_ck_n[*]}]
set_property SLEW FAST [get_ports {ddr3_cke[*]}]
set_property SLEW FAST [get_ports {ddr3_dm[*]}]
set_property SLEW FAST [get_ports {ddr3_dq[*]}]
set_property SLEW FAST [get_ports {ddr3_dqs_p[*]}]
set_property SLEW FAST [get_ports {ddr3_dqs_n[*]}]
set_property SLEW FAST [get_ports {ddr3_odt[*]}]

set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[*]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dqs_p[*]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dqs_n[*]}]

# ============================================================
# Clock constraints
# ============================================================
# Main clock: 100MHz external crystal (BACKBONE route for MIG sys_clk_i)
create_clock -period 10.000 -name clk [get_ports clk]
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clk]

# Asynchronous clock groups
# clk (100MHz external) is asynchronous to:
#   - cpu_clk (from clk_wiz_0 clk_out1, 50MHz)
#   - sys_clk (from clk_wiz_0 clk_out2, 100MHz)
#   - ddr_clk_ref (from clk_wiz_0 clk_out3, 200MHz)
#   - MIG ui_clk (from MIG internal MMCM, 100MHz)
# MIG generates its own clock constraints internally.
set_clock_groups -asynchronous \
  -group [get_clocks clk] \
  -group [get_clocks -include_generated_clocks clk_wiz_0/clk_out1] \
  -group [get_clocks -include_generated_clocks clk_wiz_0/clk_out2] \
  -group [get_clocks -include_generated_clocks clk_wiz_0/clk_out3] \
  -group [get_clocks -include_generated_clocks -of_objects [get_pins -hierarchical -filter {name =~ */u_ddr3_infrastructure/u_mmcm_i/CLKOUT*}]]

# Bitstream configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLDOWN [current_design]
