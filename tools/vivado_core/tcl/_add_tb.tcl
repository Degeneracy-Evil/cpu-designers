# =============================================================================
# _add_tb.tcl — Add testbench + update COE
#
# Required variables (must be set before sourcing):
#   tb_dir          — Testbench directory
#   tb_name         — Testbench module name (without .sv extension)
#   icache_coe_file — ICache COE file path (empty string = no COE)
#   dcache_coe_file — DCache COE file path (empty string = no COE)
#   proj_dir        — Project directory (absolute path)
#   proj_name       — Project name
# =============================================================================

# ---------------------------------------------------------------------------
# 变量检查
# ---------------------------------------------------------------------------
foreach _var {tb_dir tb_name icache_coe_file dcache_coe_file proj_dir proj_name} {
    if { ![info exists $_var] } {
        puts "ERROR: _add_tb.tcl — 缺少必需变量: $_var"
        return
    }
}

puts "========== Step 6: 添加 testbench =========="

# 移除已有仿真文件
set existing_sim_files [get_files -of_objects [get_filesets sim_1] -quiet]
if { [llength $existing_sim_files] > 0 } {
    remove_files -fileset sim_1 -quiet $existing_sim_files
}

# 添加 testbench
if { [catch {import_files -fileset sim_1 "${tb_dir}/${tb_name}.sv"} err] } {
    puts "ERROR: 添加 testbench 失败: $err"
    return
}

# 添加 lcd_module_stub (如果存在)
if { [file exists "${tb_dir}/lcd_module_stub.sv"] } {
    import_files -fileset sim_1 "${tb_dir}/lcd_module_stub.sv"
}

set_property top $tb_name [get_filesets sim_1]

update_compile_order -fileset sim_1

puts "Testbench 已添加: $tb_name"

# ---------------------------------------------------------------------------
# 更新 ROM COE 配置 (reuse 时此步骤必不可少)
# ---------------------------------------------------------------------------
if { [catch {get_ips ROM} ip_rom] == 0 && $ip_rom ne "" } {
    if { $icache_coe_file ne "" } {
        if { ![file exists $icache_coe_file] } {
            puts "WARNING: COE 文件不存在: $icache_coe_file, 跳过 COE 更新"
        } else {
            set coe_tail [file tail $icache_coe_file]
            set ip_xci_dir "${proj_dir}/${proj_name}.srcs/sources_1/ip"
            if { [catch {file copy -force $icache_coe_file "${ip_xci_dir}/ROM/"} err] } {
                puts "WARNING: 复制 COE 文件失败: $err"
            }
            set_property -dict [list \
                CONFIG.Load_Init_File {true} \
                CONFIG.Coe_File "${ip_xci_dir}/ROM/${coe_tail}" \
            ] $ip_rom
            puts "COE 已更新: $icache_coe_file"
        }
    } else {
        set_property -dict [list \
            CONFIG.Load_Init_File {false} \
        ] $ip_rom
        puts "COE 已更新: 无 COE 初始化"
    }
    if { [catch {generate_target all $ip_rom} err] } {
        puts "WARNING: generate_target ROM 失败: $err"
    }
} else {
    puts "WARNING: 未找到 ROM IP, 跳过 COE 更新"
}
