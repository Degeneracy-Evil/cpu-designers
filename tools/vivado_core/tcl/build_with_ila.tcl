# =============================================================================
# build_with_ila.tcl — Build FPGA bitstream with ILA debug probes enabled
#
# This script:
#   1. Opens the existing FPGA project
#   2. Creates ILA IP cores (ila_reset_axi, ila_cpu_axi)
#   3. Adds ila_stub.sv to the project
#   4. Sets ENABLE_ILA define so real ILA cores are instantiated
#   5. Runs synthesis + implementation + write_bitstream
#   6. Copies bit + ltx files to project root
#
# Usage:
#   vivado -mode batch -source build_with_ila.tcl
# =============================================================================

set base_dir    "/home/wangzy2024/cpu-designers"
set proj_dir    "${base_dir}/project/fpga"
set proj_name   "simplecpu_soc"
set xpr_path    "${proj_dir}/${proj_name}.xpr"

# =========================================================================
# Step 1: Open project
# =========================================================================
puts "============================================================================"
puts "Step 1: Opening project..."
puts "============================================================================"

if { ![file exists $xpr_path] } {
    puts "ERROR: Project not found: $xpr_path"
    puts "Please create the project first with: vivado_do -create"
    exit 1
}

open_project $xpr_path
puts "Project opened: $xpr_path"

# =========================================================================
# Step 2: Add ila_stub.sv to project
# =========================================================================
puts "============================================================================"
puts "Step 2: Adding ila_stub.sv..."
puts "============================================================================"

set ila_stub_path "${base_dir}/dev/rtl/common/ila_stub.sv"
if { ![file exists $ila_stub_path] } {
    puts "ERROR: ila_stub.sv not found: $ila_stub_path"
    exit 1
}

# Add the stub file if not already in project
set existing [get_files -quiet "ila_stub.sv"]
if { $existing eq "" } {
    add_files -norecurse $ila_stub_path
    puts "ila_stub.sv added to project."
} else {
    puts "ila_stub.sv already in project."
}

# =========================================================================
# Step 3: Create ILA IP cores
# =========================================================================
puts "============================================================================"
puts "Step 3: Creating ILA IP cores..."
puts "============================================================================"

# --- ILA #1: ila_reset_axi (sys_clk domain) ---
set ila1_exists [get_ips -quiet ila_reset_axi]
if { $ila1_exists eq "" } {
    puts "Creating ila_reset_axi (sys_clk domain)..."
    create_ip -name ila -vendor xilinx.com -library ip -module_name ila_reset_axi
    set_property -dict [list \
        CONFIG.C_NUM_OF_PROBES      {7}    \
        CONFIG.C_PROBE0_WIDTH       {5}    \
        CONFIG.C_PROBE1_WIDTH       {32}   \
        CONFIG.C_PROBE2_WIDTH       {8}    \
        CONFIG.C_PROBE3_WIDTH       {32}   \
        CONFIG.C_PROBE4_WIDTH       {32}   \
        CONFIG.C_PROBE5_WIDTH       {32}   \
        CONFIG.C_PROBE6_WIDTH       {4}    \
        CONFIG.C_DATA_DEPTH         {4096} \
        CONFIG.C_INPUT_PIPE_STAGES  {1}    \
    ] [get_ips ila_reset_axi]
    generate_target all [get_ips ila_reset_axi]
    puts "ila_reset_axi created."
} else {
    puts "ila_reset_axi already exists, skipping creation."
}

# --- ILA #2: ila_cpu_axi (cpu_clk domain) ---
set ila2_exists [get_ips -quiet ila_cpu_axi]
if { $ila2_exists eq "" } {
    puts "Creating ila_cpu_axi (cpu_clk domain)..."
    create_ip -name ila -vendor xilinx.com -library ip -module_name ila_cpu_axi
    set_property -dict [list \
        CONFIG.C_NUM_OF_PROBES      {7}    \
        CONFIG.C_PROBE0_WIDTH       {32}   \
        CONFIG.C_PROBE1_WIDTH       {8}    \
        CONFIG.C_PROBE2_WIDTH       {32}   \
        CONFIG.C_PROBE3_WIDTH       {32}   \
        CONFIG.C_PROBE4_WIDTH       {32}   \
        CONFIG.C_PROBE5_WIDTH       {4}    \
        CONFIG.C_PROBE6_WIDTH       {32}   \
        CONFIG.C_DATA_DEPTH         {4096} \
        CONFIG.C_INPUT_PIPE_STAGES  {1}    \
    ] [get_ips ila_cpu_axi]
    generate_target all [get_ips ila_cpu_axi]
    puts "ila_cpu_axi created."
} else {
    puts "ila_cpu_axi already exists, skipping creation."
}

# =========================================================================
# Step 4: Set ENABLE_ILA define
# =========================================================================
puts "============================================================================"
puts "Step 4: Setting ENABLE_ILA verilog define..."
puts "============================================================================"

# Add ENABLE_ILA to the Verilog defines — this activates the real ILA instantiation
# in system_top.sv instead of the stub modules
# In Vivado 2018.3, Verilog defines are set via the 'verilog_define' property
# Format: set_property verilog_define {DEFINE1=1 DEFINE2} [current_fileset]
set_property verilog_define {ENABLE_ILA} [current_fileset]
puts "ENABLE_ILA define set."

# Also set top module
set_property top system_top [current_fileset]
update_compile_order -fileset sources_1

# =========================================================================
# Step 5: Synthesize + Implement + Write Bitstream
# =========================================================================
puts "============================================================================"
puts "Step 5: Running synthesis + implementation + write_bitstream..."
puts "============================================================================"

# Reset and run synthesis
puts "Running synthesis (synth_1)..."
reset_run synth_1
launch_runs synth_1 -jobs 14
wait_on_run synth_1

# Check synthesis status
set synth_status [get_property STATUS [get_runs synth_1]]
if { ![string match "*Complete*" $synth_status] } {
    puts "ERROR: Synthesis failed with status: $synth_status"
    exit 1
}
puts "Synthesis complete."

# Run implementation
puts "Running implementation (impl_1)..."
launch_runs impl_1 -jobs 14
wait_on_run impl_1

# Check implementation status
set impl_status [get_property STATUS [get_runs impl_1]]
if { ![string match "*Complete*" $impl_status] } {
    puts "ERROR: Implementation failed with status: $impl_status"
    exit 1
}
puts "Implementation complete."

# Generate bitstream
puts "Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 14
wait_on_run impl_1

# =========================================================================
# Step 6: Copy output files
# =========================================================================
puts "============================================================================"
puts "Step 6: Copying output files..."
puts "============================================================================"

set impl_dir "${proj_dir}/${proj_name}.runs/impl_1"

# Copy bit file
set bit_file "${impl_dir}/system_top.bit"
if { [file exists $bit_file] } {
    file copy -force $bit_file "${base_dir}/system_top_ila.bit"
    puts "Bitstream: ${base_dir}/system_top_ila.bit"
} else {
    puts "ERROR: Bit file not found: $bit_file"
}

# Copy LTX probe file (critical for ILA — Hardware Manager needs this)
set ltx_file "${impl_dir}/system_top.ltx"
if { [file exists $ltx_file] } {
    file copy -force $ltx_file "${base_dir}/system_top_ila.ltx"
    puts "Probes:    ${base_dir}/system_top_ila.ltx"
} else {
    puts "WARNING: LTX probe file not found: $ltx_file"
    puts "  ILA probes may not have been inserted. Check synthesis log."
}

puts "============================================================================"
puts "Build with ILA complete!"
puts "============================================================================"
puts ""
puts "To program FPGA with ILA:"
puts "  1. Open Vivado Hardware Manager"
puts "  2. Connect to target"
puts "  3. Set PROGRAM.FILE = system_top_ila.bit"
puts "  4. Set PROBES.FILE  = system_top_ila.ltx  <-- CRITICAL!"
puts "  5. Program device"
puts "  6. Right-click hw_ila_1/hw_ila_2 → Add Probes to Trigger"
puts "  7. Set trigger condition → Run Trigger"
puts ""
