# =============================================================================
# _refresh_coe.tcl — Incremental COE-only refresh
#
# Required variables (must be set before sourcing):
#   icache_coe_file — ICache COE file path (empty string = no COE)
#   dcache_coe_file — DCache COE file path (empty string = no COE)
#   proj_dir        — Project directory (absolute path)
#   proj_name       — Project name
#
# 说明:
#   仅更新 ROM IP 的 COE 配置, 不重建工程。
#   适用于程序 COE 变更后快速刷新, 无需完整 rebuild。
# =============================================================================

# ---------------------------------------------------------------------------
# 变量检查
# ---------------------------------------------------------------------------
foreach _var {icache_coe_file dcache_coe_file proj_dir proj_name} {
    if { ![info exists $_var] } {
        puts "ERROR: _refresh_coe.tcl — 缺少必需变量: $_var"
        return
    }
}

puts "========== 刷新 COE 配置 (增量) =========="

# 获取 ROM IP
if { [catch {get_ips ROM} ip_rom] || $ip_rom eq "" } {
    puts "ERROR: 未找到 ROM IP, 无法刷新 COE"
    return
}

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

# 重新生成 IP 目标
if { [catch {generate_target all $ip_rom} err] } {
    puts "WARNING: generate_target ROM 失败: $err"
} else {
    puts "ROM IP 目标已重新生成"
}

puts "COE 刷新完成 (增量, 未重建工程)"
