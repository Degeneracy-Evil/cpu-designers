# =============================================================================
# setup_ip.tcl — Step 4: 导入 IP 并配置 ICache/DCache COE
#
# 前置变量:
#   ips_dir, icache_coe_file, dcache_coe_file, proj_dir
# =============================================================================

puts "========== Step 4: 导入 IP 并配置 ICache COE =========="

read_ip "${ips_dir}/icache/icache.xci"
read_ip "${ips_dir}/dcache/dcache.xci"
read_ip "${ips_dir}/Sram/Sram.xci"

if { $icache_coe_file ne "" } {
    set_property -dict [list \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File $icache_coe_file \
    ] [get_ips icache]

    set_property -dict [list \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File $dcache_coe_file \
    ] [get_ips dcache]
    puts "ICache 和 DCache IP 已配置 (COE: $icache_coe_file)"
} else {
    set_property -dict [list \
        CONFIG.Load_Init_File {false} \
    ] [get_ips icache]

    set_property -dict [list \
        CONFIG.Load_Init_File {false} \
    ] [get_ips dcache]
    puts "ICache 和 DCache IP 已配置 (无 COE 初始化)"
}

generate_target all [get_ips icache]
generate_target all [get_ips dcache]
generate_target all [get_ips Sram]

puts "IP 导入与配置完成"
