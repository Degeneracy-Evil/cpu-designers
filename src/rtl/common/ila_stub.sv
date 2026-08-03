`timescale 1ns / 1ps

// ============================================================================
// ILA stub modules — empty bodies for simulation when ILA IP is not available
// ============================================================================

// ----------------------------------------------------------------------------
// ila_reset_axi — Stub for sys_clk domain ILA (reset + CDC-side AXI signals)
// ----------------------------------------------------------------------------
module ila_reset_axi (
    input  wire        clk,
    input  wire [4:0]  probe0,   // packed reset status
    input  wire [31:0] probe1,   // cdc_awaddr
    input  wire [7:0]  probe2,   // CDC AXI handshake
    input  wire [31:0] probe3,   // cdc_wdata
    input  wire [31:0] probe4,   // cdc_araddr
    input  wire [31:0] probe5,   // cdc_rdata
    input  wire [3:0]  probe6    // CDC B/R channel status
);

    // Empty body — stub only

endmodule

// ----------------------------------------------------------------------------
// ila_cpu_axi — Stub for cpu_clk domain ILA (CPU-side AXI signals)
// ----------------------------------------------------------------------------
module ila_cpu_axi (
    input  wire        clk,
    input  wire [31:0] probe0,   // cpu_awaddr
    input  wire [7:0]  probe1,   // CPU AXI handshake
    input  wire [31:0] probe2,   // cpu_wdata
    input  wire [31:0] probe3,   // cpu_araddr
    input  wire [31:0] probe4,   // cpu_rdata
    input  wire [3:0]  probe5,   // CPU B/R channel status
    input  wire [31:0] probe6    // if_pc
);

    // Empty body — stub only

endmodule
