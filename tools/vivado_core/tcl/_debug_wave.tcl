# ============================================================================
# _debug_wave.tcl — Three-tier debug waveform configuration for XSim
#
# Usage (from Vivado TCL shell after launch_simulation):
#   source _debug_wave.tcl
#   debug_wave_minimal    ;# Top-level ports + key control
#   debug_wave_normal    ;# Core pipeline + regfile + peripherals
#   debug_wave_full      ;# All signals + VCD export
# ============================================================================

proc debug_wave_minimal {} {
    # Top-level system ports + key control signals
    log_wave [get_objects /tb_*/u_soc/clk]
    log_wave [get_objects /tb_*/u_soc/resetn]
    log_wave [get_objects /tb_*/u_soc/if_pc]
    log_wave [get_objects /tb_*/u_soc/if_inst]
    log_wave [get_objects /tb_*/u_soc/exe_pc]
    log_wave [get_objects /tb_*/u_soc/exe_inst]
    log_wave [get_objects /tb_*/u_soc/wb_pc]
    log_wave [get_objects /tb_*/u_soc/wb_inst]
    log_wave [get_objects /tb_*/u_soc/display_state]
    puts "Debug waveform: minimal (top ports + control)"
}

proc debug_wave_normal {} {
    # Core pipeline + register file + peripheral bus
    log_wave [get_objects /tb_*/u_soc/*]
    log_wave [get_objects /tb_*/u_soc/cpu/*]
    puts "Debug waveform: normal (core pipeline + regfile + perips)"
}

proc debug_wave_full {} {
    # All signals + VCD export for GTKWave
    log_wave [get_objects *]
    open_vcd sim_dump.vcd
    log_vcd [get_objects *]
    puts "Debug waveform: full (all signals + VCD export)"
}
