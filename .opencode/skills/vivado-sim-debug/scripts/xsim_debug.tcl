# =============================================================================
# xsim_debug.tcl — Vivado XSim 批处理调试仿真脚本
#
# 支持三级调试深度：
#   minimal  — 仅顶层端口和关键控制信号（快速定位）
#   normal   — Core pipeline + register file + 外设（正常调试）
#   full     — 全部信号 + VCD 导出（深度调试）
#
# 用法：
#   xsim <snapshot> -tclbatch xsim_debug.tcl -wdb sim.wdb
#
# 可选环境变量（在 xsim 命令前设置）：
#   set sim_time   "10ms"     ;# 仿真时间
#   set log_level  "normal"   ;# 调试深度: minimal/normal/full
#   set vcd_file   "sim.vcd"  ;# VCD 文件名（仅 full 模式）
#   set tb_path    "/tb"      ;# testbench 顶层路径
#   set dut_path   "/tb/u_soc";# DUT 路径
# =============================================================================

# ── 默认配置 ──
if { ![info exists sim_time] }  { set sim_time  "10ms" }
if { ![info exists log_level] } { set log_level  "normal" }
if { ![info exists vcd_file] }  { set vcd_file   "sim_debug.vcd" }
if { ![info exists tb_path] }   { set tb_path    "/tb" }
if { ![info exists dut_path] }  { set dut_path   "/tb/u_soc" }

puts "========== xsim_debug.tcl =========="
puts "  sim_time  = $sim_time"
puts "  log_level = $log_level"
puts "  vcd_file  = $vcd_file"
puts "  tb_path   = $tb_path"
puts "  dut_path  = $dut_path"
puts "====================================="

# =============================================================================
# Tier 1: minimal — 关键控制信号
# =============================================================================
if { $log_level eq "minimal" } {
    puts "Signal logging: MINIMAL (top-level + key control)"

    # 时钟和复位
    log_wave ${tb_path}/clk
    log_wave ${tb_path}/resetn

    # CPU 核心关键信号
    log_wave ${dut_path}/cpu/if_pc
    log_wave ${dut_path}/cpu/if_inst
    log_wave ${dut_path}/cpu/if_done
    log_wave ${dut_path}/cpu/exe_pc
    log_wave ${dut_path}/cpu/exe_inst
    log_wave ${dut_path}/cpu/exe_done
    log_wave ${dut_path}/cpu/exe_branch_taken
    log_wave ${dut_path}/cpu/wb_pc
    log_wave ${dut_path}/cpu/wb_inst
    log_wave ${dut_path}/cpu/wb_done

    # MMIO 接口
    log_wave ${dut_path}/cpu/ahb_inst_valid
    log_wave ${dut_path}/cpu/ahb_inst_data
}

# =============================================================================
# Tier 2: normal — Core pipeline + register file + 外设
# =============================================================================
if { $log_level eq "normal" } {
    puts "Signal logging: NORMAL (pipeline + regfile + peripherals)"

    # Tier 1 信号
    log_wave ${tb_path}/clk
    log_wave ${tb_path}/resetn
    log_wave ${dut_path}/cpu/if_pc
    log_wave ${dut_path}/cpu/if_inst
    log_wave ${dut_path}/cpu/if_done
    log_wave ${dut_path}/cpu/exe_pc
    log_wave ${dut_path}/cpu/exe_inst
    log_wave ${dut_path}/cpu/exe_done
    log_wave ${dut_path}/cpu/wb_pc
    log_wave ${dut_path}/cpu/wb_inst
    log_wave ${dut_path}/cpu/wb_done

    # 寄存器文件（递归）
    log_wave -r ${dut_path}/cpu/u_regfile/*

    # ALU
    log_wave ${dut_path}/cpu/u_alu/*

    # 总线桥
    log_wave ${dut_path}/cpu/u_bus_bridge/*

    # Trap/CSR
    log_wave ${dut_path}/u_trap_csr/u_trap_mgr/*
    log_wave ${dut_path}/u_trap_csr/u_csr_if/u_csr/*

    # UART（常用调试外设）
    log_wave ${dut_path}/u_apb_perips/u_uart/rx_fifo_count
    log_wave ${dut_path}/u_apb_perips/u_uart/rx_data_valid
    log_wave ${dut_path}/u_apb_perips/u_uart/tx_data_valid

    # Cache 状态
    log_wave ${dut_path}/u_icache_wrap/state
    log_wave ${dut_path}/u_dcache_wrap/state
}

# =============================================================================
# Tier 3: full — 全部信号 + VCD 导出
# =============================================================================
if { $log_level eq "full" } {
    puts "Signal logging: FULL (all signals + VCD export)"

    # 递归记录全部信号
    log_wave -r ${dut_path}/*

    # 同时生成 VCD 供外部工具（GTKWave 等）
    puts "Opening VCD file: $vcd_file"
    open_vcd $vcd_file

    # VCD 仅记录 CPU 核心信号（减小文件大小）
    log_vcd ${dut_path}/cpu/*
    log_vcd ${dut_path}/u_icache_wrap/*
    log_vcd ${dut_path}/u_dcache_wrap/*
}

# =============================================================================
# 运行仿真
# =============================================================================
puts "Running simulation for $sim_time ..."
run $sim_time
puts "Simulation completed at time: [current_time]"

# =============================================================================
# 清理
# =============================================================================
if { $log_level eq "full" } {
    puts "Closing VCD file"
    close_vcd
}

# 保存波形配置
save_wave_config "sim_debug.wcfg"

puts "========================================"
puts "Debug simulation complete"
puts "  WDB: available in current session"
if { $log_level eq "full" } {
    puts "  VCD: $vcd_file"
}
puts "  Wave config: sim_debug.wcfg"
puts "========================================"

quit
