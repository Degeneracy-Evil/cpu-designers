# =============================================================================
# _program.tcl — Connect hardware + program FPGA
#
# Required variables (must be set before sourcing):
#   bit_file — Path to bitstream file (e.g. "/path/to/system_top.bit")
# =============================================================================

# ---------------------------------------------------------------------------
# 变量检查
# ---------------------------------------------------------------------------
foreach _var {bit_file} {
    if { ![info exists $_var] } {
        puts "ERROR: _program.tcl — 缺少必需变量: $_var"
        return
    }
}

puts "========================================"
puts "开始下载 bitstream 到 FPGA..."
puts "========================================"

if { ![file exists $bit_file] } {
    puts "--> [ERROR] 找不到 bitstream 文件: $bit_file"
    return
}

# 连接硬件
if { [catch {open_hw} err] } {
    puts "WARNING: open_hw 失败 (可能已打开): $err"
}
if { [catch {connect_hw_server} err] } {
    puts "ERROR: 连接 hw_server 失败: $err"
    return
}
if { [catch {open_hw_target} err] } {
    puts "ERROR: 打开 hw_target 失败: $err"
    return
}

# 获取设备并配置
set hw_device [lindex [get_hw_devices] 0]
if { $hw_device eq "" } {
    puts "ERROR: 未找到硬件设备"
    catch { close_hw }
    return
}

current_hw_device $hw_device
refresh_hw_device -update_hw_probes false $hw_device

set_property PROBES.FILE {} $hw_device
set_property FULL_PROBES.FILE {} $hw_device
set_property PROGRAM.FILE $bit_file $hw_device

# 下载
if { [catch {program_hw_devices $hw_device} err] } {
    puts "ERROR: 下载 bitstream 失败: $err"
    catch { close_hw }
    return
}

refresh_hw_device $hw_device
catch { close_hw }

puts "--> 下载成功: $bit_file"
