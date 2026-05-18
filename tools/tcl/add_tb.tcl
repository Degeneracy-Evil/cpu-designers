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
# 更新 ICache/DCache COE 配置 (reuse 时此步骤必不可少)
# ---------------------------------------------------------------------------
if { [catch {get_ips icache} ] == 0 } {
    if { $icache_coe_file ne "" } {
        set_property -dict [list \
            CONFIG.Load_Init_File {true} \
            CONFIG.Coe_File $icache_coe_file \
        ] [get_ips icache]

        set_property -dict [list \
            CONFIG.Load_Init_File {true} \
            CONFIG.Coe_File $dcache_coe_file \
        ] [get_ips dcache]
        puts "COE 已更新: $icache_coe_file"
    } else {
        set_property -dict [list \
            CONFIG.Load_Init_File {false} \
        ] [get_ips icache]

        set_property -dict [list \
            CONFIG.Load_Init_File {false} \
        ] [get_ips dcache]
        puts "COE 已更新: 无 COE 初始化"
    }
    generate_target all [get_ips icache]
    generate_target all [get_ips dcache]
}
