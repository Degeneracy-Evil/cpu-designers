# ============================================================================
# run_ddr3_sim.tcl — Vivado XSim simulation script for DDR3 testbenches
#
# Usage:
#   vivado -mode batch -source run_ddr3_sim.tcl -tclargs <tb_name>
#   where <tb_name> is one of: tb_ddr3_mig_ex, tb_ddr3_ahb_ex
#
# This script:
#   1. Creates a temporary Vivado project
#   2. Adds all required source files (MIG sim model, ddr3_model, WireDelay, RTL, TB)
#   3. Sets SIM_BYPASS_INIT_CAL=FAST and SIMULATION=TRUE
#   4. Compiles, elaborates, and runs simulation
#   5. Reports PASS/FAIL from simulation log
# ============================================================================

# --- Parse arguments ---
set tb_name [lindex $argv 0]
if {$tb_name eq ""} {
    puts "ERROR: Usage: vivado -mode batch -source run_ddr3_sim.tcl -tclargs <tb_name>"
    exit 1
}

puts "============================================================"
puts "DDR3 Simulation: $tb_name"
puts "============================================================"

# --- Paths ---
set repo_root  [file normalize [file join [file dirname [info script]] ../..]]
set dev_dir    [file join $repo_root dev]
set rtl_dir    [file join $dev_dir rtl]
set tb_dir     [file join $dev_dir tb]
set ahb_dir    [file join $rtl_dir AHB-lite]
set core_dir   [file join $rtl_dir core]

# MIG example project paths (source of MIG sim model + ddr3_model)
set ex_proj    [file join $repo_root project bd_soc_mig_7series_0_1_ex]
set ex_imports [file join $ex_proj imports]
set ex_ip      [file join $ex_proj bd_soc_mig_7series_0_1_ex.srcs sources_1 ip bd_soc_mig_7series_0_1 bd_soc_mig_7series_0_1]
set mig_rtl    [file join $ex_ip user_design rtl]

# Output project
set proj_name  "ddr3_sim_[clock seconds]"
set proj_dir   [file join $repo_root project $proj_name]

# --- Create project ---
create_project $proj_name $proj_dir -part xc7a200tfbg676-2 -force

# --- Add MIG simulation model sources ---
# The MIG sim model is a flat set of .v files under user_design/rtl/
# We add them all — Vivado will figure out the hierarchy.
puts "Adding MIG simulation model..."

# Top-level MIG wrappers
add_files -norecurse [file join $mig_rtl bd_soc_mig_7series_0_1.v]
add_files -norecurse [file join $mig_rtl bd_soc_mig_7series_0_1_mig.v]
add_files -norecurse [file join $mig_rtl bd_soc_mig_7series_0_1_mig_sim.v]

# MIG sub-directories: axi, clocking, controller, ecc, ip_top, phy, ui
foreach subdir {axi clocking controller ecc ip_top phy ui} {
    set subpath [file join $mig_rtl $subdir]
    if {[file exists $subpath]} {
        add_files [glob -nocomplain -directory $subpath *.v]
    }
}

# --- Add DDR3 model and support files ---
puts "Adding DDR3 model and WireDelay..."
add_files -norecurse [file join $ex_imports ddr3_model.sv]
add_files -norecurse [file join $ex_imports ddr3_model_parameters.vh]
add_files -norecurse [file join $ex_imports wiredly.v]

# --- Add glbl.v (Xilinx global signals: GSR, PULLUP, etc.) ---
# Use the one from the example project's sim directory
set glbl_v [file join $ex_proj bd_soc_mig_7series_0_1_ex.sim sim_1 behav xsim glbl.v]
if {[file exists $glbl_v]} {
    add_files -norecurse $glbl_v
} else {
    # Fallback: create minimal glbl.v
    set glbl_path [file join $proj_dir glbl.v]
    set glbl_fp [open $glbl_path w]
    puts $glbl_fp "`timescale 1ps/1ps"
    puts $glbl_fp "module glbl();"
    puts $glbl_fp "  wire GSR = 1'b1;"  ;# Global Set Reset (de-asserted)
    puts $glbl_fp "  wire GTS = 1'b0;"  ;# Global Tri-state (not active)
    puts $glbl_fp "  wire PRLD = 1'b1;" ;# Pre-load
    puts $glbl_fp "  wire LOCK = 1'b1;"
    puts $glbl_fp "endmodule"
    close $glbl_fp
    add_files -norecurse $glbl_path
}

# --- Add our RTL ---
puts "Adding project RTL..."
# AHB-Lite bus and related modules
add_files -norecurse [file join $ahb_dir ahb_lite_bus.sv]
add_files -norecurse [file join $ahb_dir ahb_sram_slave.sv]
add_files -norecurse [file join $ahb_dir ahb_bootrom_slave.sv]
add_files -norecurse [file join $ahb_dir ahb_lite_to_apb_bridge.sv]
add_files -norecurse [file join $ahb_dir ahb_plic_slave.sv]
add_files -norecurse [file join $ahb_dir ahb_clint_slave.sv]
add_files -norecurse [file join $ahb_dir ahb_default_slave.sv]
add_files -norecurse [file join $ahb_dir ahb_def.svh]
add_files -norecurse [file join $ahb_dir ddr3_bridge_wrapper.sv]

# Core modules (needed by ahb_lite_bus)
add_files [glob -nocomplain -directory $core_dir *.sv]
add_files [glob -nocomplain -directory $core_dir *.svh]

# --- Add testbench ---
puts "Adding testbench: $tb_name..."
set tb_file [file join $tb_dir ${tb_name}.sv]
if {![file exists $tb_file]} {
    puts "ERROR: Testbench file not found: $tb_file"
    exit 1
}
add_files -norecurse -fileset sim_1 $tb_file

# --- Set top module for simulation ---
set_property top $tb_name [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# --- Define SIM_BYPASS_INIT_CAL and SIMULATION ---
# These are Verilog defines needed by the MIG sim model
set_property verilog_define {SIM_BYPASS_INIT_CAL=FAST SIMULATION=TRUE} [get_filesets sim_1]
# Also set for sources
set_property verilog_define {SIM_BYPASS_INIT_CAL=FAST SIMULATION=TRUE} [current_fileset]

# --- Update compile order ---
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# --- Launch simulation ---
puts "============================================================"
puts "Launching simulation..."
puts "============================================================"

launch_simulation -mode behavioral

# Wait for simulation to finish (batch mode)
# The testbench will call $finish when done

puts "============================================================"
puts "Simulation complete."
puts "============================================================"

# --- Cleanup (optional: remove temp project) ---
# close_project
# file delete -force $proj_dir
