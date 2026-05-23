# =============================================================================
# _archive.tcl — Export project archive
#
# Required variables (must be set before sourcing):
#   proj_dir    — Project directory (absolute path)
#   proj_name   — Project name
#   base_dir    — Base directory (archive will be saved under base_dir/archive/)
# =============================================================================

# ---------------------------------------------------------------------------
# 变量检查
# ---------------------------------------------------------------------------
foreach _var {proj_dir proj_name base_dir} {
    if { ![info exists $_var] } {
        puts "ERROR: _archive.tcl — 缺少必需变量: $_var"
        return
    }
}

puts "========================================"
puts "开始导出项目 Archive..."
puts "========================================"

# 生成时间戳
set time_str [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set target_archive_dir "${base_dir}/archive"
set archive_path "${target_archive_dir}/${proj_name}_${time_str}.xpr.zip"

# 确保归档目录存在
if { ![file exists $target_archive_dir] } {
    file mkdir $target_archive_dir
}

# 尝试完整归档 (含 IP 缓存和配置)
if { [catch {archive_project $archive_path -force -include_local_ip_cache -include_config_settings} err] } {
    # 降级为基本归档
    if { [catch {archive_project $archive_path -force} err2] } {
        puts "--> [ERROR] 导出项目 Archive 失败: $err2"
    } else {
        puts "--> 成功导出项目 Archive (基础模式): $archive_path"
    }
} else {
    puts "--> 成功导出项目 Archive: $archive_path"
}
