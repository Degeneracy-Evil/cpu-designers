# =============================================================================
# _add_constrs.tcl — Add DCP + constraints
#
# Required variables (must be set before sourcing):
#   fpga_dir — FPGA directory (contains lcd_module.dcp and cpu.xdc)
# =============================================================================

# ---------------------------------------------------------------------------
# 变量检查
# ---------------------------------------------------------------------------
foreach _var {fpga_dir} {
    if { ![info exists $_var] } {
        puts "ERROR: _add_constrs.tcl — 缺少必需变量: $_var"
        return
    }
}

puts "========== Step 5: 添加 DCP 与 constraints =========="

if { [catch {
    import_files -norecurse "${fpga_dir}/lcd_module.dcp"
    import_files -norecurse -fileset constrs_1 "${fpga_dir}/cpu.xdc"
} err] } {
    puts "ERROR: 添加 DCP/约束文件失败: $err"
    return
}

puts "DCP 和约束文件添加完成"
