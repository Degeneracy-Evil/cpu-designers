# =============================================================================
# add_constrs.tcl — Step 5: 添加 DCP 与约束文件
#
# 前置变量:
#   fpga_dir
# =============================================================================

puts "========== Step 5: 添加 DCP 与 constraints =========="

add_files "${fpga_dir}/lcd_module.dcp"
add_files -fileset constrs_1 "${fpga_dir}/cpu.xdc"

puts "DCP 和约束文件添加完成"
