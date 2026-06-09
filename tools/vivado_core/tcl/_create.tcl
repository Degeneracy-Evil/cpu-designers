# =============================================================================
# _create.tcl — Create project + add RTL + set include directories
#
# Required variables (must be set before sourcing):
#   proj_name       — Project name (e.g. "simplecpu_bus")
#   device_part     — FPGA part (e.g. "xc7a200tfbg676-2")
#   proj_dir        — Project directory (absolute path)
#   alu_rtl_dir     — ALU RTL directory
#   mu_rtl_dir     — MU RTL directory
#   fpu_rtl_dir    — FPU RTL directory
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
foreach _var {proj_name device_part proj_dir alu_rtl_dir mu_rtl_dir fpu_rtl_dir cpu_core_dir \
               ahb_dir ahb_ip_dir apb_dir apb_header_dir apb_perips_dir sys_rtl_dir common_dir tb_dir} {
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
# Step 2: 添加 RTL 源文件
# ---------------------------------------------------------------------------
puts "========== Step 2: 添加 RTL 源文件 =========="

# ALU
if { [catch {
    foreach f [glob -directory $alu_rtl_dir *.sv] {
        import_files -norecurse $f
    }
} err] } {
    puts "WARNING: 添加 ALU RTL 失败: $err"
}

# MU
if { [catch {
    foreach f [glob -directory $mu_rtl_dir *.sv] {
        import_files -norecurse $f
    }
} err] } {
    puts "WARNING: 添加 MU RTL 失败: $err"
}

# FPU
if { [catch {
    foreach f [glob -directory $fpu_rtl_dir *.sv] {
        import_files -norecurse $f
    }
} err] } {
    puts "WARNING: 添加 FPU RTL 失败: $err"
}

# CPU Core
if { [catch {
    foreach f [glob -directory $cpu_core_dir *.sv] {
        import_files -norecurse $f
    }
} err] } {
    puts "WARNING: 添加 CPU Core RTL 失败: $err"
}

# Common (reset_sync, etc.)
if { [catch {
    foreach f [glob -directory $common_dir *.sv] {
        import_files -norecurse $f
    }
} err] } {
    puts "WARNING: 添加 Common RTL 失败: $err"
}

# AHB-Lite (.sv + .svh)
if { [catch {
    foreach f [glob -directory $ahb_dir *.sv] {
        import_files -norecurse $f
    }
    foreach f [glob -directory $ahb_dir *.svh] {
        import_files -norecurse $f
        set_property file_type "Verilog Header" [get_files [file tail $f]]
    }
} err] } {
    puts "WARNING: 添加 AHB-Lite RTL 失败: $err"
}

# APB (.sv + .svh)
if { [catch {
    foreach f [glob -directory $apb_dir *.sv] {
        import_files -norecurse $f
    }
    foreach f [glob -directory $apb_dir *.svh] {
        import_files -norecurse $f
        set_property file_type "Verilog Header" [get_files [file tail $f]]
    }
} err] } {
    puts "WARNING: 添加 APB RTL 失败: $err"
}

# APB Peripherals
if { [catch {
    foreach f [glob -directory $apb_perips_dir *.sv] {
        import_files -norecurse $f
    }
} err] } {
    puts "WARNING: 添加 APB Peripherals RTL 失败: $err"
}

# APB Headers
if { [catch {
    foreach f [glob -directory $apb_header_dir *.svh] {
        import_files -norecurse $f
        set_property file_type "Verilog Header" [get_files [file tail $f]]
    }
} err] } {
    puts "WARNING: 添加 APB Header 失败: $err"
}

# System Top
if { [catch {import_files -norecurse "${sys_rtl_dir}/system_top.sv"} err] } {
    puts "WARNING: 添加 system_top.sv 失败: $err"
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
    $fpu_rtl_dir \
    $cpu_core_dir \
    $common_dir \
    $ahb_dir \
    $ahb_ip_dir \
    $apb_dir \
    $apb_header_dir \
    $apb_perips_dir \
    $tb_dir \
] [current_fileset]

puts "Include 目录已设置 (9 个目录)"
