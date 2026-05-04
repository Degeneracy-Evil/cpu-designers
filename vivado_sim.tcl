# =============================================================================
# vivado_sim.tcl — Vivado 仿真自动化脚本 (适用于本项目)
# 用法:
#   1. Vivado TCL Shell 直接运行:  source vivado_sim.tcl
# =============================================================================

# ---------------------------------------------------------------------------
# 用户可配置变量
# ---------------------------------------------------------------------------

# 项目名称
set proj_name       "simplecpu_bus"

# FPGA 器件型号
set device_part     "xc7a200tfbg676-2"

# === 路径设置 ===
# 获取当前脚本所在目录作为 base_dir，实现真正的跨平台与自适应
set base_dir        [file dirname [file normalize [info script]]]

puts "$base_dir"

# 项目输出目录
set proj_dir        "${base_dir}/build/${proj_name}"

# RTL 源文件根目录 (指向本仓库 dev/ 目录)
set dev_dir         "${base_dir}/dev"

# ALU RTL 目录
set alu_rtl_dir     "${dev_dir}/1-alu/rtl"

# CPU RTL 目录
set cpu_rtl_dir     "${dev_dir}/2-simpleCPU/rtl"

# Testbench 目录
set tb_dir          "${dev_dir}/2-simpleCPU/tb"

# 程序源文件目录 (COE / HEX 文件)
set prog_dir        "${dev_dir}/2-simpleCPU/program_source"

# FPGA 目录 (约束文件、DCP)
set fpga_dir        "${dev_dir}/2-simpleCPU/fpga"

# === IP 路径 ===
# 指向根目录下的 ips/ 目录
set ips_dir         "${base_dir}/ips"

# === 仿真配置 ===
set tb_name         "tb_simple_cpu_top"

# === testbench → COE/HEX 文件映射 ===
array set tb_coe_map {
    tb_simple_cpu_top  "icache_init.coe"
    tb_csr_test        "csr_test.coe"
    tb_align_test      "comprehensive_test.coe"
    tb_timer_irq_test  "comprehensive_test.coe"
    tb_timer_seconds   "comprehensive_test.coe"
    tb_led_marquee     "led_marquee.coe"
    tb_ahb_bus         ""
    tb_apb_perips      ""
    tb_cpu_bus_adapter ""
}

# === testbench → 仿真运行时间映射 (ns) ===
array set tb_runtime_map {
    tb_simple_cpu_top  "100000ns"
    tb_csr_test        "60000ns"
    tb_align_test      "60000ns"
    tb_timer_irq_test  "100000ns"
    tb_timer_seconds   "30000ns"
    tb_led_marquee     "1000000000ns"
    tb_ahb_bus         "5000ns"
    tb_apb_perips      "2000ns"
    tb_cpu_bus_adapter "5000ns"
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

# ALU 模块
add_files [glob -nocomplain -directory $alu_rtl_dir *.v]

# CPU 核心模块 (Exclude icache.v and dcache.v simulation models)
set cpu_files [glob -nocomplain -directory $cpu_rtl_dir *.v]
set filtered_cpu []
foreach f $cpu_files {
    if {![string match "*icache.v" $f] && ![string match "*dcache.v" $f]} {
        lappend filtered_cpu $f
    }
}
if {[llength $filtered_cpu] > 0} {
    add_files $filtered_cpu
}

update_compile_order -fileset sources_1

puts "RTL 源文件添加完成"

# ---------------------------------------------------------------------------
# Step 3: 设置头文件搜索路径
# ---------------------------------------------------------------------------
puts "========== Step 3: 设置 include 目录 =========="

set_property include_dirs [list \
    $alu_rtl_dir \
    $cpu_rtl_dir \
    $tb_dir \
] [current_fileset]

puts "Include 目录已设置"

# ---------------------------------------------------------------------------
# Step 4: 导入 IP 并配置 ICache COE
# ---------------------------------------------------------------------------
puts "========== Step 4: 导入 IP 并配置 ICache COE =========="

# 导入/读取已生成的 IP
if {[file exists "${ips_dir}/icache/icache.xci"]} {
    read_ip "${ips_dir}/icache/icache.xci"
}
if {[file exists "${ips_dir}/dcache/dcache.xci"]} {
    read_ip "${ips_dir}/dcache/dcache.xci"
}

# 仅当 icache IP 存在并且需要初始化文件时，配置 coe
if { $icache_coe_file ne "" } {
    set_property -dict [list \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File $icache_coe_file \
    ] [get_ips icache]
    puts "ICache IP 已配置 (COE: $icache_coe_file)"
} else {
    catch {
        set_property -dict [list \
            CONFIG.Load_Init_File {false} \
        ] [get_ips icache]
    }
    puts "ICache IP 已配置 (无 COE 初始化)"
}

catch { generate_target all [get_ips icache] }
catch { generate_target all [get_ips dcache] }

puts "IP 导入与配置完成"

# ---------------------------------------------------------------------------
# Step 5: 添加其他源文件 (DCP, XDC)
# ---------------------------------------------------------------------------
puts "========== Step 5: 添加 DCP 与 constraints =========="

# 添加 LCD DCP 作为源文件
if {[file exists "${fpga_dir}/lcd_module.dcp"]} {
    add_files "${fpga_dir}/lcd_module.dcp"
}

# 添加 XDC 作为约束文件
if {[file exists "${fpga_dir}/cpu.xdc"]} {
    add_files -fileset constrs_1 "${fpga_dir}/cpu.xdc"
}

puts "DCP 和约束文件添加完成"

# ---------------------------------------------------------------------------
# Step 6: 添加 testbench
# ---------------------------------------------------------------------------
puts "========== Step 6: 添加 testbench =========="

# 添加 testbench 主文件
if {[file exists "${tb_dir}/${tb_name}.v"]} {
    add_files -fileset sim_1 "${tb_dir}/${tb_name}.v"
}

# 添加 LCD 模块 stub
if { [file exists "${tb_dir}/lcd_module_stub.v"] } {
    add_files -fileset sim_1 "${tb_dir}/lcd_module_stub.v"
}

# 设置仿真顶层模块
catch { set_property top $tb_name [get_filesets sim_1] }

update_compile_order -fileset sim_1

puts "Testbench 已添加: $tb_name"

# ---------------------------------------------------------------------------
# Step 7: 设置仿真运行时间并启动行为级仿真
# ---------------------------------------------------------------------------
puts "========== Step 7: 启动仿真 =========="

# 设置 xsim 仿真运行时间
set_property xsim.simulate.runtime $sim_run_time [get_filesets sim_1]

# 启用 xsim 日志记录
set_property xsim.simulate.log_all_objects true [get_filesets sim_1]

puts "仿真配置: tb=$tb_name, runtime=$sim_run_time, coe=$icache_coe_file"

launch_simulation -mode behavioral

# ---------------------------------------------------------------------------
# Step 8: 读取仿真日志, 输出 PASS/FAIL 结果
# ---------------------------------------------------------------------------
puts "========== Step 8: 读取仿真日志 =========="

set sim_log_dir  "${proj_dir}/${proj_name}.sim/sim_1/behav/xsim"
set sim_log_file "${sim_log_dir}/xsim.log"

if { [file exists $sim_log_file] } {
    set fp   [open $sim_log_file r]
    set data [read $fp]
    close $fp
    puts $data
} else {
    puts "WARNING: 未找到仿真日志文件: $sim_log_file"
}

puts "========================================"
puts "仿真运行完成: $sim_run_time"
puts "Testbench: $tb_name"
puts "========================================"
