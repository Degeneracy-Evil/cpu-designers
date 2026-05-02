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

# === IP 路径 ===
set ips_dir         "${base_dir}/Reference/ips"

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
# Step 4: 导入 IP 并配置 ICache COE
# ---------------------------------------------------------------------------
puts "========== Step 4: 导入 IP 并配置 ICache COE =========="

# 导入/读取已生成的 IP
read_ip "${ips_dir}/icache/icache.xci"
read_ip "${ips_dir}/dcache/dcache.xci"
# 若有其他IP也同样导入，按需取消下行注释
# read_ip "${ips_dir}/Sram/Sram.xci"

if { $icache_coe_file ne "" } {
    set_property -dict [list \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File $icache_coe_file \
    ] [get_ips icache]
    puts "ICache IP 已配置 (COE: $icache_coe_file)"
} else {
    set_property -dict [list \
        CONFIG.Load_Init_File {false} \
    ] [get_ips icache]
    puts "ICache IP 已配置 (无 COE 初始化)"
}

generate_target all [get_ips icache]
generate_target all [get_ips dcache]

puts "IP 导入与配置完成"

# ---------------------------------------------------------------------------
# Step 5: 添加其他源文件 (DCP, XDC)
# ---------------------------------------------------------------------------
puts "========== Step 5: 添加 DCP 与 constraints =========="

# 添加 LCD DCP 作为源文件
add_files "${fpga_dir}/lcd_module.dcp"

# 添加 XDC 作为约束文件
add_files -fileset constrs_1 "${fpga_dir}/cpu.xdc"

puts "DCP 和约束文件添加完成"

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
# Step 7: 设置仿真运行时间并启动行为级仿真
# ---------------------------------------------------------------------------
puts "========== Step 7: 启动仿真 =========="

# 设置 xsim 仿真运行时间 (覆盖默认 1000ns)
set_property xsim.simulate.runtime $sim_run_time [get_filesets sim_1]

# 启用 xsim 日志记录, 将 testbench 的 $display 输出写入日志文件
set_property xsim.simulate.log_all_objects true [get_filesets sim_1]

launch_simulation -mode behavioral

# ---------------------------------------------------------------------------
# Step 8: 读取仿真日志, 输出 PASS/FAIL 结果
# ---------------------------------------------------------------------------
puts "========== Step 8: 读取仿真日志 =========="

# XSIM 日志文件路径
set sim_log_dir  "${proj_dir}/${proj_name}.sim/sim_1/behav/xsim"
set sim_log_file "${sim_log_dir}/xsim.log"

if { [file exists $sim_log_file] } {
    set fp   [open $sim_log_file r]
    set data [read $fp]
    close $fp
    puts $data
} else {
    puts "WARNING: 未找到仿真日志文件: $sim_log_file"
    puts "可尝试手动查看: $sim_log_dir/"
}

puts "========================================"
puts "仿真运行完成: $sim_run_time"
puts "Testbench: $tb_name"
puts "========================================"
