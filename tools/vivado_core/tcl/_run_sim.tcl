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
# Keep XSIM.ELABORATE.DEBUG_LEVEL at its default: "off" breaks the testbench
# hierarchical signal references (u_soc.cpu.*) used for trap/uart capture.
# Vivado's generated run Tcl unconditionally executes "add_wave /", so use a
# custom Tcl file even when LOG_ALL_SIGNALS is false.
set xsim_custom_tcl "${proj_dir}/.xsim_run_${tb_name}.tcl"
set xsim_custom_fp [open $xsim_custom_tcl w]

if { [info exists ::wave_level] && $::wave_level ne "" } {
    switch -- $::wave_level {
        minimal {
            puts $xsim_custom_fp {log_wave [get_objects /tb_*/u_soc/*]}
        }
        normal {
            puts $xsim_custom_fp {log_wave [get_objects /tb_*/u_soc/*]}
            puts $xsim_custom_fp {log_wave [get_objects /tb_*/u_soc/cpu/*]}
        }
        full {
            puts $xsim_custom_fp {log_wave [get_objects *]}
            puts $xsim_custom_fp {open_vcd sim_dump.vcd}
            puts $xsim_custom_fp {log_vcd [get_objects *]}
        }
        default {
            puts "WARNING: unknown wave_level '$::wave_level'; no waves will be recorded"
            puts $xsim_custom_fp {foreach wdb_file [glob -nocomplain *.wdb] {
                file delete -force $wdb_file
            }}
        }
    }
} else {
    # XSim opens an empty WDB before sourcing this file. On Linux, unlink it so
    # the run directory contains no WDB and it cannot grow accidentally.
    puts $xsim_custom_fp {foreach wdb_file [glob -nocomplain *.wdb] {
        file delete -force $wdb_file
    }}
}
puts $xsim_custom_fp "run $sim_run_time"
close $xsim_custom_fp

set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
set_property xsim.simulate.custom_tcl $xsim_custom_tcl [get_filesets sim_1]

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
