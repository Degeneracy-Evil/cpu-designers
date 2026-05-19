# =============================================================================
# setup_ip.tcl — Step 4: 导入 IP 并配置 ICache/DCache COE
#
# 前置变量:
#   ips_dir, icache_coe_file, dcache_coe_file, proj_dir, proj_name
# =============================================================================

puts "========== Step 4: 导入 IP 并配置 ICache COE =========="

set ip_xci_dir "${proj_dir}/${proj_name}.srcs/sources_1/ip"

import_files -norecurse "${ips_dir}/icache.xci"
import_files -norecurse "${ips_dir}/dcache.xci"
import_files -norecurse "${ips_dir}/Sram.xci"

export_ip_user_files -of_objects [get_files "${ip_xci_dir}/icache/icache.xci"] -force -quiet
export_ip_user_files -of_objects [get_files "${ip_xci_dir}/dcache/dcache.xci"] -force -quiet
export_ip_user_files -of_objects [get_files "${ip_xci_dir}/Sram/Sram.xci"] -force -quiet

update_compile_order -fileset sources_1

if { $icache_coe_file ne "" } {
    set coe_tail [file tail $icache_coe_file]
    file copy -force $icache_coe_file "${ip_xci_dir}/icache/"
    file copy -force $dcache_coe_file "${ip_xci_dir}/dcache/"

    set_property -dict [list \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File "${ip_xci_dir}/icache/${coe_tail}" \
    ] [get_ips icache]

    set_property -dict [list \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File "${ip_xci_dir}/dcache/${coe_tail}" \
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

generate_target all [get_files "${ip_xci_dir}/icache/icache.xci"]
generate_target all [get_files "${ip_xci_dir}/dcache/dcache.xci"]
generate_target all [get_files "${ip_xci_dir}/Sram/Sram.xci"]

catch { config_ip_cache -export [get_ips -all icache] }
catch { config_ip_cache -export [get_ips -all dcache] }
catch { config_ip_cache -export [get_ips -all Sram] }

export_ip_user_files -of_objects [get_files "${ip_xci_dir}/icache/icache.xci"] -no_script -sync -force -quiet
export_ip_user_files -of_objects [get_files "${ip_xci_dir}/dcache/dcache.xci"] -no_script -sync -force -quiet
export_ip_user_files -of_objects [get_files "${ip_xci_dir}/Sram/Sram.xci"] -no_script -sync -force -quiet

puts "IP 导入与配置完成"
