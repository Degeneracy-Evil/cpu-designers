# =============================================================================
# vivado_sim.tcl — Vivado 仿真自动化脚本
# 用法:
#   1. Vivado TCL Shell 直接运行:  source vivado_sim.tcl
#   2. 通过 tcl-tunnel 远程执行:   source <repo_root>/vivado_sim.tcl
#
# 注意:
#   - testbench 中的 $readmemh 使用相对路径，iverilog 可直接解析
#   - xsim 工作目录为 ${proj_dir}/${proj_name}.sim/sim_1/behav/xsim/
#     相对路径无法解析，需将 $readmemh 路径改为绝对路径
#     例如: "<repo_root>/dev/program_source/cpu_test.hex"
# =============================================================================

# ---------------------------------------------------------------------------
# 用户可配置变量 (根据实际环境修改)
# ---------------------------------------------------------------------------

# 项目名称
set proj_name       "simplecpu_bus"

# FPGA 器件型号
set device_part     "xc7a200tfbg676-2"

# === 路径设置 ===
# base_dir 自动取脚本所在目录, 无需手动修改
# 若需覆盖, 可取消注释并修改下行:
# set base_dir        "E:/Xprogram/FPGA/tmp"
if { ![info exists base_dir] } {
    set base_dir    [file dirname [file normalize [info script]]]
}

# 项目输出目录 (Vivado 工程文件统一存放于 project/ 子目录)
set proj_dir        "${base_dir}/project/${proj_name}"

# RTL 源文件根目录 (指向本仓库 dev/ 目录)
set dev_dir         "${base_dir}/dev"

# ALU RTL 目录
set alu_rtl_dir     "${dev_dir}/rtl/ALU"

# MU (乘除法器) RTL 目录
set mu_rtl_dir      "${dev_dir}/rtl/MU"

# CPU RTL 目录
set cpu_core_dir    "${dev_dir}/rtl/core"
set ahb_dir         "${dev_dir}/rtl/AHB-lite"
set ahb_ip_dir      "${dev_dir}/rtl/AHB-lite/ip"
set apb_dir         "${dev_dir}/rtl/APB"
set apb_header_dir  "${dev_dir}/rtl/APB/header"
set apb_perips_dir  "${dev_dir}/rtl/APB/perips"
set sys_rtl_dir     "${dev_dir}/rtl"

# Testbench 目录
set tb_dir          "${dev_dir}/tb"

# 程序源文件目录 (COE / HEX 文件)
set prog_dir        "${dev_dir}/program_source"

# FPGA 目录 (约束文件、DCP)
set fpga_dir        "${dev_dir}/fpga"

# === IP 路径 ===
set ips_dir         "${base_dir}/Reference/ips"

# === 仿真配置 ===
# 选择 testbench:
#   tb_simple_cpu_top     — CPU 全功能测试 (34 PASS, 需要 cpu_test.hex)
#   tb_simple_cpu_compute — CPU 计算/访存测试 (42 PASS, 需要 cpu_test_compute.hex)
#   tb_simple_cpu_trap    — CPU 异常/陷阱测试 (10 PASS, 需要 cpu_test_trap.hex)
#   tb_uart_hello         — UART 发送测试 (12 PASS, 需要 uart_hello.hex)
#   tb_led_marquee        — LED 走马灯测试 (16 PASS, 需要 led_marquee.hex)
#   tb_ahb_bus            — AHB 总线测试 (3 PASS, 无需 hex)
#   tb_apb_perips         — APB 外设测试 (10 PASS, 无需 hex)
#   tb_cpu_bus_adapter    — CPU 总线适配器测试 (6 PASS, 无需 hex)
set tb_name         "tb_simple_cpu_top"

# === testbench → COE/HEX 文件映射 ===
# ICache BRAM IP 的 COE 初始化文件 (设为 "" 则不加载 COE)
# 仅对使用 CPU 全系统的 testbench 有意义 (tb_simple_cpu_top 等)
# tb_ahb_bus / tb_apb_perips / tb_cpu_bus_adapter 不需要 COE
array set tb_coe_map {
    tb_simple_cpu_top     "cpu_test.coe"
    tb_simple_cpu_compute "cpu_test_compute.coe"
    tb_simple_cpu_trap    "cpu_test_trap.coe"
    tb_uart_hello         "uart_hello.coe"
    tb_led_marquee        "led_marquee.coe"
    tb_ahb_bus            ""
    tb_apb_perips         ""
    tb_cpu_bus_adapter    ""
}

# === testbench → 仿真运行时间映射 (ns) ===
array set tb_runtime_map {
    tb_simple_cpu_top     "500000ns"
    tb_simple_cpu_compute "500000ns"
    tb_simple_cpu_trap    "300000ns"
    tb_uart_hello         "5000000ns"
    tb_led_marquee        "1000000000ns"
    tb_ahb_bus            "5000ns"
    tb_apb_perips         "2000ns"
    tb_cpu_bus_adapter    "5000ns"
}

set icache_coe_file ""
if { [info exists tb_coe_map($tb_name)] } {
    set coe_name $tb_coe_map($tb_name)
    if { $coe_name ne "" } {
        set icache_coe_file "${prog_dir}/${coe_name}"
    }
}

set sim_run_time "100000ns"
if { [info exists tb_runtime_map($tb_name)] } {
    set sim_run_time $tb_runtime_map($tb_name)
}

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

# MU 乘除法器模块 (3 个文件)
add_files [glob -directory $mu_rtl_dir *.v]

# CPU 核心模块 (Exclude icache.v and dcache.v simulation models)
set cpu_files [glob -directory $cpu_core_dir *.v]
set filtered_cpu []
foreach f $cpu_files {
    if {![string match "*icache.v" $f] && ![string match "*dcache.v" $f]} {
        lappend filtered_cpu $f
    }
}
if {[llength $filtered_cpu] > 0} {
    add_files $filtered_cpu
}

# AHB-Lite 总线 (7 个文件)
add_files [glob -directory $ahb_dir *.v]

# AHB-Lite IP (sram_model.v is excluded to use real IP core)
# add_files [glob -directory $ahb_ip_dir *.v]

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
    $alu_rtl_dir \
    $mu_rtl_dir \
    $cpu_core_dir \
    $ahb_dir \
    $ahb_ip_dir \
    $apb_dir \
    $apb_header_dir \
    $apb_perips_dir \
    $tb_dir \
] [current_fileset]

puts "Include 目录已设置 (9 个目录)"

# ---------------------------------------------------------------------------
# Step 4: 导入 IP 并配置 ICache COE
# ---------------------------------------------------------------------------
puts "========== Step 4: 导入 IP 并配置 ICache COE =========="

# 导入/读取已生成的 IP
read_ip "${ips_dir}/icache/icache.xci"
read_ip "${ips_dir}/dcache/dcache.xci"
read_ip "${ips_dir}/Sram/Sram.xci"

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
generate_target all [get_ips Sram]

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

# 设置 xsim 仿真运行时间
set_property xsim.simulate.runtime $sim_run_time [get_filesets sim_1]

# 启用 xsim 日志记录, 将 testbench 的 $display 输出写入日志文件
set_property xsim.simulate.log_all_objects true [get_filesets sim_1]

puts "仿真配置: tb=$tb_name, runtime=$sim_run_time, coe=$icache_coe_file"

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
