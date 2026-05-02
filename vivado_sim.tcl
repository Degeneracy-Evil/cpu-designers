# =============================================================================
# vivado_sim.tcl — Vivado 仿真自动化脚本
# 用法:
#   1. Vivado TCL Shell 直接运行:  source vivado_sim.tcl
#   2. 通过 tcl-tunnel 远程执行:   source E:/Xprogram/FPGA/tmp/vivado_sim.tcl
# =============================================================================

# ---------------------------------------------------------------------------
# 用户可配置变量 (根据实际环境修改)
# ---------------------------------------------------------------------------

# 项目名称
set proj_name       "simplecpu_sim"

# FPGA 器件型号
set device_part     "xc7a200tfbg676-2"

# === 路径设置 ===
# 若通过 tcl-tunnel 在 Windows 端 Vivado 运行，需使用 Windows 路径格式
# 例如: set base_dir "E:/Xprogram/FPGA/tmp"
# 若在 Linux 端 Vivado 运行，使用 Linux 路径格式
# 例如: set base_dir "/home/wood/cpu-designers"
set base_dir        "E:/Xprogram/FPGA/tmp"

# 项目输出目录
set proj_dir        "${base_dir}/${proj_name}"

# RTL 源文件根目录 (指向本仓库 dev/ 目录)
set dev_dir         "${base_dir}/dev"

# ALU RTL 目录
set alu_rtl_dir     "${dev_dir}/1-alu/rtl"

# CPU RTL 目录
set cpu_core_dir    "${dev_dir}/2-simpleCPU/rtl/core"
set ahb_dir         "${dev_dir}/2-simpleCPU/rtl/AHB-lite"
set ahb_ip_dir      "${dev_dir}/2-simpleCPU/rtl/AHB-lite/ip"
set apb_dir         "${dev_dir}/2-simpleCPU/rtl/APB"
set apb_header_dir  "${dev_dir}/2-simpleCPU/rtl/APB/header"
set apb_perips_dir  "${dev_dir}/2-simpleCPU/rtl/APB/perips"
set sys_rtl_dir     "${dev_dir}/2-simpleCPU/rtl"

# Testbench 目录
set tb_dir          "${dev_dir}/2-simpleCPU/tb"

# 程序源文件目录 (COE 文件)
set prog_dir        "${dev_dir}/2-simpleCPU/program_source"

# FPGA 目录 (约束文件、DCP)
set fpga_dir        "${dev_dir}/2-simpleCPU/fpga"

# === 仿真配置 ===
# 选择 testbench: tb_simple_cpu_top / tb_csr_test / tb_align_test / tb_timer_irq_test / tb_timer_seconds / tb_ahb_bus / tb_apb_perips / tb_cpu_bus_adapter
set tb_name         "tb_simple_cpu_top"

# 仿真运行时间 (ns)
set sim_run_time    "100000ns"

# === BRAM IP 配置 ===
# ICache COE 初始化文件 (设为 "" 则不加载 COE)
set icache_coe_file "${prog_dir}/icache_init.coe"

# IP 输出目录
set ip_output_dir   "${proj_dir}/${proj_name}.srcs/sources_1/ip"

# ---------------------------------------------------------------------------
# Step 1: 创建 Vivado 工程
# ---------------------------------------------------------------------------
puts "========== Step 1: 创建工程 =========="

create_project $proj_name $proj_dir -part $device_part -force
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

puts "工程已创建: $proj_dir"

# ---------------------------------------------------------------------------
# Step 2: 添加 RTL 源文件
# ---------------------------------------------------------------------------
puts "========== Step 2: 添加 RTL 源文件 =========="

# ALU 模块 (12 个文件)
add_files [glob -directory $alu_rtl_dir *.v]

# CPU 核心模块 (18 个文件)
add_files [glob -directory $cpu_core_dir *.v]

# AHB-Lite 总线 (7 个文件)
add_files [glob -directory $ahb_dir *.v]

# AHB-Lite IP (sram_model.v)
add_files [glob -directory $ahb_ip_dir *.v]

# APB 总线 (5 个文件, 不含 perips 子目录)
add_files [glob -directory $apb_dir *.v]

# APB 外设 (7 个文件)
add_files [glob -directory $apb_perips_dir *.v]

# 系统顶层
add_files "${sys_rtl_dir}/system_top.v"

update_compile_order -fileset sources_1

puts "RTL 源文件添加完成"

# ---------------------------------------------------------------------------
# Step 3: 设置头文件搜索路径 (.vh 文件不能通过 add_files 添加)
# ---------------------------------------------------------------------------
puts "========== Step 3: 设置 include 目录 =========="

set_property include_dirs [list \
    $ahb_dir \
    $apb_dir \
    $apb_header_dir \
] [current_fileset]

puts "Include 目录: $ahb_dir, $apb_dir, $apb_header_dir"

# ---------------------------------------------------------------------------
# Step 4: 创建 ICache BRAM IP (blk_mem_gen, 带 COE 初始化)
# ---------------------------------------------------------------------------
puts "========== Step 4: 创建 ICache BRAM IP =========="

set icache_ip_dir "${ip_output_dir}/Sram_icache"
file mkdir $icache_ip_dir

create_ip -name blk_mem_gen -vendor xilinx.com -library ip \
    -module_name Sram_icache -dir $icache_ip_dir

if { $icache_coe_file ne "" } {
    set_property -dict [list \
        CONFIG.Memory_Type {Single_Port_RAM} \
        CONFIG.Read_Width_A {32} \
        CONFIG.Write_Width_A {32} \
        CONFIG.Write_Depth_A {8192} \
        CONFIG.Operating_Mode_A {READ_FIRST} \
        CONFIG.Use_Byte_Write_Enable {true} \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File $icache_coe_file \
        CONFIG.Fill_Remaining_Memory_Locations {true} \
        CONFIG.Primitive {8kx2} \
    ] [get_ips Sram_icache]
    puts "ICache IP 已配置 (COE: $icache_coe_file)"
} else {
    set_property -dict [list \
        CONFIG.Memory_Type {Single_Port_RAM} \
        CONFIG.Read_Width_A {32} \
        CONFIG.Write_Width_A {32} \
        CONFIG.Write_Depth_A {8192} \
        CONFIG.Operating_Mode_A {READ_FIRST} \
        CONFIG.Use_Byte_Write_Enable {true} \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
        CONFIG.Load_Init_File {false} \
        CONFIG.Fill_Remaining_Memory_Locations {true} \
        CONFIG.Primitive {8kx2} \
    ] [get_ips Sram_icache]
    puts "ICache IP 已配置 (无 COE 初始化)"
}

generate_target all [get_ips Sram_icache]

puts "ICache BRAM IP 生成完成"

# ---------------------------------------------------------------------------
# Step 5: 创建 DCache BRAM IP (blk_mem_gen, 无 COE 初始化)
# ---------------------------------------------------------------------------
puts "========== Step 5: 创建 DCache BRAM IP =========="

set dcache_ip_dir "${ip_output_dir}/Sram_dcache"
file mkdir $dcache_ip_dir

create_ip -name blk_mem_gen -vendor xilinx.com -library ip \
    -module_name Sram_dcache -dir $dcache_ip_dir

set_property -dict [list \
    CONFIG.Memory_Type {Single_Port_RAM} \
    CONFIG.Read_Width_A {32} \
    CONFIG.Write_Width_A {32} \
    CONFIG.Write_Depth_A {8192} \
    CONFIG.Operating_Mode_A {READ_FIRST} \
    CONFIG.Use_Byte_Write_Enable {true} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File {false} \
    CONFIG.Fill_Remaining_Memory_Locations {true} \
    CONFIG.Primitive {8kx2} \
] [get_ips Sram_dcache]

generate_target all [get_ips Sram_dcache]

puts "DCache BRAM IP 生成完成"

# ---------------------------------------------------------------------------
# Step 6: 添加 testbench
# ---------------------------------------------------------------------------
puts "========== Step 6: 添加 testbench =========="

# 添加 testbench 主文件
add_files -fileset sim_1 "${tb_dir}/${tb_name}.v"

# 添加 LCD 模块 stub (仿真用, 替代 lcd_module.dcp)
if { [file exists "${tb_dir}/lcd_module_stub.v"] } {
    add_files -fileset sim_1 "${tb_dir}/lcd_module_stub.v"
}

# 设置仿真顶层模块
set_property top $tb_name [get_filesets sim_1]

update_compile_order -fileset sim_1

puts "Testbench 已添加: $tb_name"

# ---------------------------------------------------------------------------
# Step 7: 启动行为级仿真
# ---------------------------------------------------------------------------
puts "========== Step 7: 启动仿真 =========="

launch_simulation -mode behavioral

puts "仿真已启动, 默认运行 1000ns"

# ---------------------------------------------------------------------------
# Step 8: 继续运行仿真至指定时间
# ---------------------------------------------------------------------------
puts "========== Step 8: 运行仿真 $sim_run_time =========="

run $sim_run_time

puts "========================================"
puts "仿真运行完成: $sim_run_time"
puts "Testbench: $tb_name"
puts "========================================"
