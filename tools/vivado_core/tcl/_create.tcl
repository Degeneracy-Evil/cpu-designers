# =============================================================================
# _create.tcl — Create project + add RTL + set include directories
#
# Required variables (must be set before sourcing):
#   proj_name       — Project name (e.g. "simplecpu_bus")
#   device_part     — FPGA part (e.g. "xc7a200tfbg676-2")
#   proj_dir        — Project directory (absolute path)
#   alu_rtl_dir     — ALU RTL directory
#   mu_rtl_dir     — MU RTL directory
#   cpu_core_dir    — CPU core RTL directory
#   ahb_dir         — AHB-Lite RTL directory
#   ahb_ip_dir      — AHB-Lite IP directory
#   apb_dir         — APB RTL directory
#   apb_header_dir  — APB header directory
#   apb_perips_dir  — APB peripherals directory
#   sys_rtl_dir     — System RTL directory (contains system_top.sv)
#   common_dir      — Common RTL directory (contains reset_sync.sv etc.)
#   tb_dir          — Testbench directory
# =============================================================================

# ---------------------------------------------------------------------------
# 变量检查
# ---------------------------------------------------------------------------
foreach _var {proj_name device_part proj_dir alu_rtl_dir mu_rtl_dir cpu_core_dir \
               ahb_dir ahb_ip_dir apb_dir apb_header_dir apb_perips_dir sys_rtl_dir common_dir tb_dir \
               amba_dir ram_wrap_dir} {
    if { ![info exists $_var] } {
        puts "ERROR: _create.tcl — 缺少必需变量: $_var"
        return
    }
}

# ---------------------------------------------------------------------------
# Step 1: 创建工程
# ---------------------------------------------------------------------------
puts "========== Step 1: 创建工程 =========="

if { [catch {current_project} cur_proj] == 0 } {
    puts "关闭已打开的工程: $cur_proj"
    close_project
}

if { [catch {create_project $proj_name $proj_dir -part $device_part -force} err] } {
    puts "ERROR: 创建工程失败: $err"
    return
}
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

puts "工程已创建: $proj_dir (拷贝策略)"

# ---------------------------------------------------------------------------
# Step 2: 添加 RTL 源文件 (add_files -scan_for_includes)
#
# 使用 add_files -scan_for_includes 代替逐文件 import_files:
#   -scan_for_includes 让 Vivado 自动扫描 `include 依赖
#   -自动推断编译顺序，解决 update_compile_order 依赖缺失问题
#   -参考 chiplab 框架项目的 create_project.tcl
#
# 注意: sys_rtl_dir (src/rtl/) 的顶层文件需单独添加，
#       因为 add_files -scan_for_includes 会递归包含 _archived/ 等不需要的子目录
# ---------------------------------------------------------------------------
puts "========== Step 2: 添加 RTL 源文件 =========="

# ALU
if { [catch {add_files -scan_for_includes $alu_rtl_dir} err] } {
    puts "WARNING: 添加 ALU RTL 失败: $err"
}

# MU
if { [catch {add_files -scan_for_includes $mu_rtl_dir} err] } {
    puts "WARNING: 添加 MU RTL 失败: $err"
}

# CPU Core (含 cache_def.svh, core_bus_types.svh 等头文件)
if { [catch {add_files -scan_for_includes $cpu_core_dir} err] } {
    puts "WARNING: 添加 CPU Core RTL 失败: $err"
}

# Common (reset_sync, etc.)
if { [catch {add_files -scan_for_includes $common_dir} err] } {
    puts "WARNING: 添加 Common RTL 失败: $err"
}

# AHB-Lite
if { [catch {add_files -scan_for_includes $ahb_dir} err] } {
    puts "WARNING: 添加 AHB-Lite RTL 失败: $err"
}

# AMBA
if { [catch {add_files -scan_for_includes $amba_dir} err] } {
    puts "WARNING: 添加 AMBA RTL 失败: $err"
}

# RAM Wrapper
if { [catch {add_files -scan_for_includes $ram_wrap_dir} err] } {
    puts "WARNING: 添加 RAM Wrapper RTL 失败: $err"
}

# APB (含子目录 perips/, header/)
if { [catch {add_files -scan_for_includes $apb_dir} err] } {
    puts "WARNING: 添加 APB RTL 失败: $err"
}

# System RTL 顶层文件 (不递归，避免包含 _archived/)
if { [catch {add_files -norecurse "${sys_rtl_dir}/system_top.sv"} err] } {
    puts "WARNING: 添加 system_top.sv 失败: $err"
}
if { [catch {add_files -norecurse "${sys_rtl_dir}/soc_config.vh"} err] } {
    puts "WARNING: 添加 soc_config.vh 失败: $err"
}
if { [file exists "${sys_rtl_dir}/axi4_def.svh"] } {
    if { [catch {add_files -norecurse "${sys_rtl_dir}/axi4_def.svh"} err] } {
        puts "WARNING: 添加 axi4_def.svh 失败: $err"
    }
}
if { [file exists "${sys_rtl_dir}/debug_uart_tx.sv"] } {
    if { [catch {add_files -norecurse "${sys_rtl_dir}/debug_uart_tx.sv"} err] } {
        puts "WARNING: 添加 debug_uart_tx.sv 失败: $err"
    }
}

update_compile_order -fileset sources_1

puts "RTL 源文件添加完成"

# ---------------------------------------------------------------------------
# Step 3: 设置头文件搜索路径
# ---------------------------------------------------------------------------
puts "========== Step 3: 设置 include 目录 =========="

set_property include_dirs [list \
    $alu_rtl_dir \
    $mu_rtl_dir \
    $cpu_core_dir \
    $common_dir \
    $ahb_dir \
    $ahb_ip_dir \
    $amba_dir \
    $ram_wrap_dir \
    $apb_dir \
    $apb_header_dir \
    $apb_perips_dir \
    $sys_rtl_dir \
    $tb_dir \
] [current_fileset]

puts "Include 目录已设置 (14 个目录)"
