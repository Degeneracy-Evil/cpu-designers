# ============================================================================
# run_ddr3_sim.tcl — Vivado XSim simulation script for DDR3 testbenches
#
# Usage:
#   vivado -mode batch -source dev/tb/run_ddr3_sim.tcl -tclargs <tb_name> [hex_file]
#   where <tb_name> is one of: tb_ddr3_mig_ex, tb_ddr3_ahb_ex, tb_ddr3_system
#   and [hex_file] is optional hex file for tb_ddr3_system (copied to xsim dir)
#
# This script:
#   1. Creates a temporary Vivado project
#   2. Adds all required source files (MIG sim model, ddr3_model, WireDelay, RTL, TB)
#   3. Sets SIM_BYPASS_INIT_CAL=FAST and SIMULATION=TRUE
#   4. Compiles, elaborates, and runs simulation
# ============================================================================

# --- Parse arguments ---
set tb_name [lindex $argv 0]
if {$tb_name eq ""} {
    puts "ERROR: Usage: vivado -mode batch -source run_ddr3_sim.tcl -tclargs <tb_name> \[hex_file\]"
    exit 1
}
set hex_file [lindex $argv 1]

puts "============================================================"
puts "DDR3 Simulation: $tb_name"
if {$hex_file ne ""} {
    puts "HEX file: $hex_file"
}
puts "============================================================"

# --- Paths ---
set repo_root  [file normalize [file join [file dirname [info script]] ../..]]
set dev_dir    [file join $repo_root dev]
set rtl_dir    [file join $dev_dir rtl]
set tb_dir     [file join $dev_dir tb]
set ahb_dir    [file join $rtl_dir AHB-lite]
set apb_dir    [file join $rtl_dir APB]
set core_dir   [file join $rtl_dir core]
set perips_dir [file join $apb_dir perips]

# MIG example project paths (source of MIG sim model + ddr3_model)
set ex_proj    [file join $repo_root project bd_soc_mig_7series_0_1_ex]
set ex_imports [file join $ex_proj imports]
set ex_ip      [file join $ex_proj bd_soc_mig_7series_0_1_ex.srcs sources_1 ip bd_soc_mig_7series_0_1 bd_soc_mig_7series_0_1]
set mig_rtl    [file join $ex_ip user_design rtl]

# DDR3 test project paths (source of IP cores: bridge, clk_wiz)
set ddr3_proj  [file join $repo_root project ddr3_test simplecpu_soc.srcs sources_1 ip]

# Output project
set proj_name  "ddr3_sim_[clock seconds]"
set proj_dir   [file join $repo_root project $proj_name]

# --- Create project ---
create_project $proj_name $proj_dir -part xc7a200tfbg676-2 -force

# --- Add MIG simulation model sources ---
puts "Adding MIG simulation model..."

# Top-level MIG wrappers
add_files -norecurse [file join $mig_rtl bd_soc_mig_7series_0_1.v]
add_files -norecurse [file join $mig_rtl bd_soc_mig_7series_0_1_mig.v]
add_files -norecurse [file join $mig_rtl bd_soc_mig_7series_0_1_mig_sim.v]

# MIG sub-directories
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

# --- Add IP cores (AHB-AXI bridge, Clocking Wizard) ---
puts "Adding IP cores..."
# AHB-Lite to AXI4 bridge (VHDL) — add both wrapper and RTL library
set bridge_rtl [file normalize [file join $ddr3_proj ahblite_axi_bridge_0 ahblite_axi_bridge_0 hdl ahblite_axi_bridge_v3_0_vh_rfs.vhd]]
set bridge_sim [file normalize [file join $ddr3_proj ahblite_axi_bridge_0 ahblite_axi_bridge_0 sim ahblite_axi_bridge_0.vhd]]
add_files -norecurse $bridge_rtl
add_files -norecurse $bridge_sim
# Clocking Wizard (Verilog)
add_files -norecurse [file join $ddr3_proj clk_wiz_0 clk_wiz_0 clk_wiz_0.v]

# --- Add glbl.v ---
set glbl_v [file join $ex_proj bd_soc_mig_7series_0_1_ex.sim sim_1 behav xsim glbl.v]
if {[file exists $glbl_v]} {
    add_files -norecurse $glbl_v
} else {
    set glbl_path [file join $proj_dir glbl.v]
    set glbl_fp [open $glbl_path w]
    puts $glbl_fp "`timescale 1ps/1ps"
    puts $glbl_fp "module glbl();"
    puts $glbl_fp "  wire GSR = 1'b1;"
    puts $glbl_fp "  wire GTS = 1'b0;"
    puts $glbl_fp "  wire PRLD = 1'b1;"
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
add_files -norecurse [file join $ahb_dir ahb_sys_status.sv]
add_files -norecurse [file join $ahb_dir ahb_default_slave.sv]
add_files -norecurse [file join $ahb_dir ahb_mux.sv]
add_files -norecurse [file join $ahb_dir ahb_plic.sv]
add_files -norecurse [file join $ahb_dir ahb_clint.sv]
add_files -norecurse [file join $ahb_dir ahb_def.svh]
add_files -norecurse [file join $ahb_dir ddr3_bridge_wrapper.sv]

# APB bridge and peripherals
add_files -norecurse [file join $apb_dir ahb_lite_to_apb.sv]
add_files -norecurse [file join $apb_dir apb_decoder.sv]
add_files -norecurse [file join $apb_dir apb_def.svh]
add_files -norecurse [file join $perips_dir apb_perips.sv]
add_files -norecurse [file join $perips_dir gpio.sv]
add_files -norecurse [file join $perips_dir uart_top.sv]
add_files -norecurse [file join $perips_dir uart_rx.sv]
add_files -norecurse [file join $perips_dir uart_tx.sv]
add_files -norecurse [file join $perips_dir timer.sv]
add_files -norecurse [file join $perips_dir spi.sv]

# System top (needed by tb_ddr3_system)
add_files -norecurse [file join $rtl_dir system_top.sv]

# LCD module stub for simulation (real lcd_module is a DCP netlist)
add_files -norecurse [file join $tb_dir lcd_module_stub.sv]

# Core modules
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

# --- Copy hex file to project if provided ---
if {$hex_file ne ""} {
    set hex_src [file normalize $hex_file]
    if {[file exists $hex_src]} {
        # Copy to project dir so $readmemh can find it
        file copy -force $hex_src [file join $proj_dir prog.hex]
        puts "Copied $hex_src -> [file join $proj_dir prog.hex]"
    } else {
        puts "WARNING: HEX file not found: $hex_src"
    }
}

# --- Set top module for simulation ---
set_property top $tb_name [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# --- Define SIM_BYPASS_INIT_CAL and SIMULATION ---
set_property verilog_define {SIM_BYPASS_INIT_CAL=FAST SIMULATION=TRUE} [get_filesets sim_1]
set_property verilog_define {SIM_BYPASS_INIT_CAL=FAST SIMULATION=TRUE} [current_fileset]

# --- Set include paths for `include directives ---
set_property include_dirs [list $ahb_dir $apb_dir $core_dir] [get_filesets sources_1]
set_property include_dirs [list $ahb_dir $apb_dir $core_dir] [current_fileset]

# --- Update compile order ---
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# --- Diagnostic: check fileset contents ---
puts "DIAG: sources_1 files: [llength [get_files -of_objects [get_filesets sources_1]]]"

# --- Set bridge RTL library ---
# NOTE: set_property library corrupts fileset in Vivado 2018.3 — do NOT use.
# Instead, we compile bridge VHDL directly via xvlog into the correct library.
# set bridge_rtl_obj [get_files -of_objects [get_filesets sources_1] -quiet $bridge_rtl]
# if {$bridge_rtl_obj ne ""} {
#     set_property library ahblite_axi_bridge_v3_0_13 $bridge_rtl_obj
#     puts "Set bridge RTL library to ahblite_axi_bridge_v3_0_13"
# } else {
#     puts "WARNING: Could not find bridge RTL file to set library"
# }

# --- Remove bridge VHDL from Vivado project (we compile via xvlog directly) ---
# The bridge VHDL must be in library ahblite_axi_bridge_v3_0_13, but
# set_property library corrupts the fileset. Remove from project and compile manually.
set bridge_files [get_files -of_objects [get_filesets sources_1] -quiet "*ahblite_axi_bridge*"]
if {[llength $bridge_files] > 0} {
    remove_files $bridge_files
    puts "Removed [llength $bridge_files] bridge VHDL files from project (will compile via xvlog)"
}

# --- Set simulation runtime ---
# Full MIG calibration needs ~200-400µs; use 1000µs for MIG/AHB tests
set sim_runtime "1000us"
if {$tb_name eq "tb_ddr3_system"} {
    set sim_runtime "10ms"
}
set_property xsim.simulate.runtime $sim_runtime [get_filesets sim_1]

# --- Launch simulation ---
puts "============================================================"
puts "Launching simulation (runtime: $sim_runtime)..."
puts "============================================================"

launch_simulation -mode behavioral

puts "============================================================"
puts "Simulation complete."
puts "============================================================"
