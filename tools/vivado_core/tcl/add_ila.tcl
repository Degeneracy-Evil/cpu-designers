# Create the optional ILA cores used by system_top.sv when ENABLE_ILA is set.
# Run this script only after opening the target Vivado project:
#
#   open_project build/project/<session>/simplecpu_soc.xpr
#   source tools/vivado_core/tcl/add_ila.tcl

if {[catch {current_project}]} {
    error "Open a Vivado project before sourcing add_ila.tcl"
}

proc create_ila_if_missing {name properties} {
    if {[llength [get_ips -quiet $name]] > 0} {
        puts "ILA already exists: $name"
        return
    }

    create_ip -name ila -vendor xilinx.com -library ip -module_name $name
    set_property -dict $properties [get_ips $name]
    generate_target all [get_ips $name]
    puts "Created ILA: $name"
}

create_ila_if_missing ila_reset_axi [list \
    CONFIG.C_NUM_OF_PROBES     {7}    \
    CONFIG.C_PROBE0_WIDTH      {5}    \
    CONFIG.C_PROBE1_WIDTH      {32}   \
    CONFIG.C_PROBE2_WIDTH      {8}    \
    CONFIG.C_PROBE3_WIDTH      {32}   \
    CONFIG.C_PROBE4_WIDTH      {32}   \
    CONFIG.C_PROBE5_WIDTH      {32}   \
    CONFIG.C_PROBE6_WIDTH      {4}    \
    CONFIG.C_DATA_DEPTH        {4096} \
    CONFIG.C_INPUT_PIPE_STAGES {1}    \
]

create_ila_if_missing ila_cpu_axi [list \
    CONFIG.C_NUM_OF_PROBES     {7}    \
    CONFIG.C_PROBE0_WIDTH      {32}   \
    CONFIG.C_PROBE1_WIDTH      {8}    \
    CONFIG.C_PROBE2_WIDTH      {32}   \
    CONFIG.C_PROBE3_WIDTH      {32}   \
    CONFIG.C_PROBE4_WIDTH      {32}   \
    CONFIG.C_PROBE5_WIDTH      {4}    \
    CONFIG.C_PROBE6_WIDTH      {32}   \
    CONFIG.C_DATA_DEPTH        {4096} \
    CONFIG.C_INPUT_PIPE_STAGES {1}    \
]
