# ============================================================================
# _add_ila.tcl — Create ILA (Integrated Logic Analyzer) IP cores
# ============================================================================
# Source this script from within an open Vivado project.
#
# Creates two ILA IP cores:
#   1. ila_reset_axi  — sys_clk domain (reset status + CDC-side AXI signals)
#   2. ila_cpu_axi    — cpu_clk domain (CPU-side AXI signals + IF stage PC)
#
# Usage:
#   source _add_ila.tcl
# ============================================================================

puts "============================================================================"
puts "Creating ILA IP cores..."
puts "============================================================================"

# --------------------------------------------------------------------------
# ILA #1: ila_reset_axi (sys_clk domain)
# Probes: reset status [5], cdc_awaddr [32], CDC handshake [8],
#         cdc_wdata [32], cdc_araddr [32], cdc_rdata [32], CDC B/R [4]
# --------------------------------------------------------------------------
puts "Creating ila_reset_axi (sys_clk domain)..."

if {[catch {
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

    puts "  ila_reset_axi created and generated successfully."
} err_msg]} {
    puts "ERROR: Failed to create ila_reset_axi: $err_msg"
}

# --------------------------------------------------------------------------
# ILA #2: ila_cpu_axi (cpu_clk domain)
# Probes: cpu_awaddr [32], CPU handshake [8], cpu_wdata [32],
#         cpu_araddr [32], cpu_rdata [32], CPU B/R [4], if_pc [32]
# --------------------------------------------------------------------------
puts "Creating ila_cpu_axi (cpu_clk domain)..."

if {[catch {
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

    puts "  ila_cpu_axi created and generated successfully."
} err_msg]} {
    puts "ERROR: Failed to create ila_cpu_axi: $err_msg"
}

puts "============================================================================"
puts "ILA IP core creation complete."
puts "============================================================================"
