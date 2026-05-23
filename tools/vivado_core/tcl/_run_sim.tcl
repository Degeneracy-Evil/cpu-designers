# =============================================================================
# _run_sim.tcl — Launch simulation + read log
#
# Required variables (must be set before sourcing):
#   tb_name       — Testbench module name
#   sim_run_time  — Simulation runtime (e.g. "5ms", "5000ns")
#   proj_dir      — Project directory (absolute path)
#   proj_name     — Project name
# =============================================================================

# ---------------------------------------------------------------------------
# 变量检查
# ---------------------------------------------------------------------------
foreach _var {tb_name sim_run_time proj_dir proj_name} {
    if { ![info exists $_var] } {
        puts "ERROR: _run_sim.tcl — 缺少必需变量: $_var"
        return
    }
}

puts "========== Step 7: 启动仿真 =========="

# 关闭已有仿真
if { [catch {current_sim_state} sim_state] == 0 } {
    if { $sim_state ne "none" } {
        puts "关闭已有仿真"
        close_sim -force
    }
}

set_property xsim.simulate.runtime $sim_run_time [get_filesets sim_1]
set_property xsim.simulate.log_all_objects true [get_filesets sim_1]

puts "仿真配置: tb=$tb_name, runtime=$sim_run_time"

if { [catch {launch_simulation -mode behavioral} err] } {
    puts "ERROR: 启动仿真失败: $err"
    return
}

# ---------------------------------------------------------------------------
# Step 8: 读取仿真日志
# ---------------------------------------------------------------------------
puts "========== Step 8: 读取仿真日志 =========="

set sim_log_dir  "${proj_dir}/${proj_name}.sim/sim_1/behav/xsim"
set sim_log_file "${sim_log_dir}/xsim.log"

if { [file exists $sim_log_file] } {
    set fp   [open $sim_log_file r]
    set data [read $fp]
    close $fp
    puts $data
} else {
    puts "WARNING: 未找到仿真日志文件: $sim_log_file"
    puts "可尝试手动查看: $sim_log_dir/"
}

puts "========================================"
puts "仿真运行完成: $sim_run_time"
puts "Testbench: $tb_name"
puts "========================================"
