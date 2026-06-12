# =============================================================================
# _refresh_tb.tcl — Incremental testbench refresh
#
# Required variables (must be set before sourcing):
#   tb_dir          — Testbench directory
#   tb_name         — Testbench module name (without .sv extension)
#   icache_coe_file — ICache COE file path (empty string = no COE)
#   dcache_coe_file — DCache COE file path (empty string = no COE)
#   proj_dir        — Project directory (absolute path)
#   proj_name       — Project name
#
# 说明:
#   移除当前仿真文件, 添加新 testbench, 更新 COE 配置。
#   不重建工程, 仅刷新仿真文件集。
# =============================================================================

# ---------------------------------------------------------------------------
# 变量检查
# ---------------------------------------------------------------------------
foreach _var {tb_dir tb_name icache_coe_file dcache_coe_file proj_dir proj_name} {
    if { ![info exists $_var] } {
        puts "ERROR: _refresh_tb.tcl — 缺少必需变量: $_var"
        return
    }
}

puts "========== 刷新 testbench (增量) =========="

# Step 1: 移除已有仿真文件
set existing_sim_files [get_files -of_objects [get_filesets sim_1] -quiet]
if { [llength $existing_sim_files] > 0 } {
    if { [catch {remove_files -fileset sim_1 $existing_sim_files} err] } {
        puts "WARNING: 移除已有仿真文件失败: $err"
    } else {
        puts "已移除 [llength $existing_sim_files] 个仿真文件"
    }
}

# Step 2: 添加新 testbench
if { [catch {add_files -fileset sim_1 "${tb_dir}/${tb_name}.sv"} err] } {
    puts "ERROR: 添加 testbench 失败: $err"
    return
}
puts "已添加 testbench: ${tb_dir}/${tb_name}.sv"

# Step 3: 添加 lcd_module_stub (如果存在)
if { [file exists "${tb_dir}/lcd_module_stub.sv"] } {
    add_files -fileset sim_1 "${tb_dir}/lcd_module_stub.sv"
    puts "已添加 lcd_module_stub.sv"
}

# Step 4: 设置顶层模块
set_property top $tb_name [get_filesets sim_1]

# Step 5: 更新编译顺序
update_compile_order -fileset sim_1

puts "Testbench 刷新完成: $tb_name"

# ---------------------------------------------------------------------------
# Step 6: 更新 ROM COE 配置 (同 _refresh_coe.tcl 逻辑)
# ---------------------------------------------------------------------------
if { [catch {get_ips ROM} ip_rom] == 0 && $ip_rom ne "" } {
    set ip_xci_dir "${proj_dir}/${proj_name}.srcs/sources_1/ip"

    if { $icache_coe_file ne "" } {
        if { ![file exists $icache_coe_file] } {
            puts "WARNING: COE 文件不存在: $icache_coe_file, ROM 将不加载 COE"
            set_property -dict [list \
                CONFIG.Load_Init_File {false} \
            ] $ip_rom
        } else {
            set coe_tail [file tail $icache_coe_file]
            if { [catch {file copy -force $icache_coe_file "${ip_xci_dir}/ROM/"} err] } {
                puts "WARNING: 复制 COE 文件失败: $err"
            }
            set_property -dict [list \
                CONFIG.Load_Init_File {true} \
                CONFIG.Coe_File "${ip_xci_dir}/ROM/${coe_tail}" \
            ] $ip_rom
            puts "ROM COE 已更新: $icache_coe_file"
        }
    } else {
        set_property -dict [list \
        CONFIG.Load_Init_File {false} \
        ] $ip_rom
    puts "ROM COE 已更新: 无 COE 初始化"
    }

    if { [catch {generate_target all $ip_rom} err] } {
        puts "WARNING: generate_target ROM 失败: $err"
    }
} else {
    puts "WARNING: 未找到 ROM IP, 跳过 COE 更新"
}

puts "Testbench + COE 刷新完成 (增量, 未重建工程)"
