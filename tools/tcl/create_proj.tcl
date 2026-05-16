# =============================================================================
# create_proj.tcl — Step 1-3: 创建工程、添加 RTL 源文件、设置 include 目录
#
# 前置变量 (由 vivado_sim.tcl 设置):
#   proj_name, device_part, proj_dir, dev_dir,
#   alu_rtl_dir, mu_rtl_dir, cpu_core_dir, ahb_dir, ahb_ip_dir,
#   apb_dir, apb_header_dir, apb_perips_dir, sys_rtl_dir
# =============================================================================

puts "========== Step 1: 创建工程 =========="

if { [catch {current_project} cur_proj] == 0 } {
    puts "关闭已打开的工程: $cur_proj"
    close_project
}

create_project $proj_name $proj_dir -part $device_part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

puts "工程已创建: $proj_dir"

# ---------------------------------------------------------------------------
# Step 2: 添加 RTL 源文件
# ---------------------------------------------------------------------------
puts "========== Step 2: 添加 RTL 源文件 =========="

add_files [glob -directory $alu_rtl_dir *.sv]

add_files [glob -directory $mu_rtl_dir *.sv]

set cpu_files [glob -directory $cpu_core_dir *.sv]
set filtered_cpu []
foreach f $cpu_files {
    if {![string match "*icache.sv" $f] && ![string match "*dcache.sv" $f]} {
        lappend filtered_cpu $f
    }
}
if {[llength $filtered_cpu] > 0} {
    add_files $filtered_cpu
}

add_files [glob -directory $ahb_dir *.sv]

add_files [glob -directory $apb_dir *.sv]

add_files [glob -directory $apb_perips_dir *.sv]

add_files "${sys_rtl_dir}/system_top.sv"

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
    $ahb_dir \
    $ahb_ip_dir \
    $apb_dir \
    $apb_header_dir \
    $apb_perips_dir \
    $tb_dir \
] [current_fileset]

puts "Include 目录已设置 (9 个目录)"
