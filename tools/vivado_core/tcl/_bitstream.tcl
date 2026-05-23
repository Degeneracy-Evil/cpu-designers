# =============================================================================
# _bitstream.tcl — Synthesize + implement + write bitstream
#
# Required variables (must be set before sourcing):
#   proj_dir    — Project directory (absolute path)
#   proj_name   — Project name
#   base_dir    — Base directory (bit file will be copied here)
#   top_module  — Top module name (e.g. "system_top")
#   jobs        — (optional) Number of parallel jobs (default: 14)
# =============================================================================

# ---------------------------------------------------------------------------
# 变量检查
# ---------------------------------------------------------------------------
foreach _var {proj_dir proj_name base_dir top_module} {
    if { ![info exists $_var] } {
        puts "ERROR: _bitstream.tcl — 缺少必需变量: $_var"
        return
    }
}

# 可选变量默认值
if { ![info exists jobs] } {
    set jobs 14
}

puts "========================================"
puts "开始生成 bitstream..."
puts "========================================"

# 设置顶层模块
if { [catch {
    set_property top $top_module [current_fileset]
    update_compile_order -fileset sources_1
} err] } {
    puts "ERROR: 设置顶层模块失败: $err"
    return
}

# 综合
puts "开始综合 (synth_1, jobs=$jobs)..."
if { [catch {reset_run synth_1} err] } {
    puts "WARNING: reset_run synth_1 失败: $err"
}
if { [catch {launch_runs synth_1 -jobs $jobs} err] } {
    puts "ERROR: 启动综合失败: $err"
    return
}
if { [catch {wait_on_run synth_1} err] } {
    puts "ERROR: 等待综合完成失败: $err"
    return
}

# 实现
puts "开始实现 (impl_1, jobs=$jobs)..."
if { [catch {launch_runs impl_1 -jobs $jobs} err] } {
    puts "ERROR: 启动实现失败: $err"
    return
}
if { [catch {wait_on_run impl_1} err] } {
    puts "ERROR: 等待实现完成失败: $err"
    return
}

# 生成 bitstream
puts "开始生成 bitstream (impl_1 -to_step write_bitstream, jobs=$jobs)..."
if { [catch {launch_runs impl_1 -to_step write_bitstream -jobs $jobs} err] } {
    puts "ERROR: 启动 bitstream 生成失败: $err"
    return
}
if { [catch {wait_on_run impl_1} err] } {
    puts "ERROR: 等待 bitstream 生成完成失败: $err"
    return
}

# 复制 bit 文件
set bit_file "${proj_dir}/${proj_name}.runs/impl_1/${top_module}.bit"
if { [file exists $bit_file] } {
    if { [catch {file copy -force $bit_file "${base_dir}/${top_module}.bit"} err] } {
        puts "WARNING: 复制 bit 文件失败: $err"
    } else {
        puts "--> 成功生成 bitstream: ${base_dir}/${top_module}.bit"
    }
} else {
    puts "--> [ERROR] Bitstream 生成失败: $bit_file 不存在"
}
