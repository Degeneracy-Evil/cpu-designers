# =============================================================================
# run_sim.tcl — Step 7-8: 启动仿真、读取日志
#
# 前置变量:
#   tb_name, sim_run_time, proj_dir, proj_name
# =============================================================================

puts "========== Step 7: 启动仿真 =========="

if { [catch {current_sim_state} sim_state] == 0 } {
    if { $sim_state ne "none" } {
        puts "关闭已有仿真"
        close_sim -force
    }
}

set_property xsim.simulate.runtime $sim_run_time [get_filesets sim_1]
set_property xsim.simulate.log_all_objects true [get_filesets sim_1]

puts "仿真配置: tb=$tb_name, runtime=$sim_run_time"

launch_simulation -mode behavioral

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
