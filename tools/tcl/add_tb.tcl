# =============================================================================
# add_tb.tcl — Step 6: 添加 testbench + 更新 COE 配置
#
# 前置变量:
#   tb_dir, tb_name, icache_coe_file, dcache_coe_file
# =============================================================================

puts "========== Step 6: 添加 testbench =========="

set existing_sim_files [get_files -of_objects [get_filesets sim_1] -quiet]
if { [llength $existing_sim_files] > 0 } {
    remove_files -fileset sim_1 -quiet $existing_sim_files
}

add_files -fileset sim_1 "${tb_dir}/${tb_name}.sv"

if { [file exists "${tb_dir}/lcd_module_stub.sv"] } {
    add_files -fileset sim_1 "${tb_dir}/lcd_module_stub.sv"
}

set_property top $tb_name [get_filesets sim_1]

update_compile_order -fileset sim_1

puts "Testbench 已添加: $tb_name"

# ---------------------------------------------------------------------------
# 更新 Sram COE 配置 (reuse 时此步骤必不可少)
# ---------------------------------------------------------------------------
if { [catch {get_ips Sram} ip_sram] == 0 && $ip_sram ne "" } {
    if { $icache_coe_file ne "" } {
        set coe_tail [file tail $icache_coe_file]
        set ip_xci_dir "${proj_dir}/${proj_name}.srcs/sources_1/ip"
        file copy -force $icache_coe_file "${ip_xci_dir}/Sram/"
        set_property -dict [list \
            CONFIG.Load_Init_File {true} \
            CONFIG.Coe_File "${ip_xci_dir}/Sram/${coe_tail}" \
        ] $ip_sram
        puts "COE 已更新: $icache_coe_file"
    } else {
        set_property -dict [list \
            CONFIG.Load_Init_File {false} \
        ] $ip_sram
        puts "COE 已更新: 无 COE 初始化"
    }
    generate_target all $ip_sram
}
