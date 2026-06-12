# =============================================================================
# _setup_ip.tcl — Import IP + configure COE
#
# Required variables (must be set before sourcing):
#   ips_dir         — IP directory (contains icached.xci, dcached.xci, ROM.xci)
#   icache_coe_file — ICache COE file path (empty string = no COE)
#   dcache_coe_file — DCache COE file path (empty string = no COE)
#   proj_dir        — Project directory (absolute path)
#   proj_name       — Project name
#
# IP 说明:
#   icached  — ICache 数据 BRAM (256bit×32, True Dual Port) — 冷启动, 无 COE
#   dcached  — DCache 数据 BRAM (256bit×32, True Dual Port) — 冷启动, 无 COE
#   ROM      — Boot ROM    (32bit×8192) — 可选 COE 初始化程序
# =============================================================================

# ---------------------------------------------------------------------------
# 变量检查
# ---------------------------------------------------------------------------
foreach _var {ips_dir icache_coe_file dcache_coe_file proj_dir proj_name} {
    if { ![info exists $_var] } {
        puts "ERROR: _setup_ip.tcl — 缺少必需变量: $_var"
        return
    }
}

puts "========== Step 4: 导入 IP 并配置 ROM COE =========="

set ip_xci_dir "${proj_dir}/${proj_name}.srcs/sources_1/ip"

# 导入 XCI 文件
if { [catch {
    import_files -norecurse "${ips_dir}/icached.xci"
    import_files -norecurse "${ips_dir}/dcached.xci"
    import_files -norecurse "${ips_dir}/ROM.xci"
} err] } {
    puts "ERROR: 导入 IP XCI 文件失败: $err"
    return
}

update_compile_order -fileset sources_1

# ICache/DCache 数据 BRAM: 冷启动, 不加载 COE
set ip_icached [get_ips -all icached]
set ip_dcached [get_ips -all dcached]
    set ip_rom    [get_ips -all ROM]

if { $ip_icached eq "" } {
    puts "WARNING: get_ips icached 返回空, 尝试刷新 IP..."
    update_compile_order -fileset sources_1
    set ip_icached [get_ips -all icached]
    set ip_dcached [get_ips -all dcached]
set ip_rom    [get_ips -all ROM]
}

if { $ip_icached eq "" || $ip_dcached eq "" || $ip_rom eq "" } {
    puts "ERROR: 无法获取 IP 对象 (icached=$ip_icached, dcached=$ip_dcached, ROM=$ip_rom)"
    return
}

set_property -dict [list \
    CONFIG.Load_Init_File {false} \
] $ip_icached

set_property -dict [list \
    CONFIG.Load_Init_File {false} \
] $ip_dcached

# ROM (boot ROM): 用 COE 初始化程序 (icache_coe_file 复用为程序 COE)
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
        puts "ROM IP 已配置 (COE: $icache_coe_file)"
    }
} else {
    set_property -dict [list \
        CONFIG.Load_Init_File {false} \
    ] $ip_rom
    puts "ROM IP 已配置 (无 COE 初始化)"
}

# 生成 IP 目标
if { [catch {generate_target all $ip_icached} err] } {
    puts "WARNING: generate_target icached 失败: $err"
}
if { [catch {generate_target all $ip_dcached} err] } {
    puts "WARNING: generate_target dcached 失败: $err"
}
if { [catch {generate_target all $ip_rom} err] } {
    puts "WARNING: generate_target ROM 失败: $err"
}

catch { config_ip_cache -export $ip_icached }
catch { config_ip_cache -export $ip_dcached }
catch { config_ip_cache -export $ip_rom }

export_ip_user_files -of_objects $ip_icached -no_script -sync -force -quiet
export_ip_user_files -of_objects $ip_dcached -no_script -sync -force -quiet
export_ip_user_files -of_objects $ip_rom    -no_script -sync -force -quiet

puts "IP 导入与配置完成"
