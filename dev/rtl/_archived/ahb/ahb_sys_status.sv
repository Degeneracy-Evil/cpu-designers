/**
 * ahb_sys_status.sv — AHB-Lite read-only System Status slave.
 *
 * Exposes FPGA system status signals as a memory-mapped read-only register.
 * Writes are silently acknowledged (HREADYOUT=1, HRESP=OKAY) with no effect.
 *
 * Address map: 0x0400_0000 (decoded by ahb_lite_bus as HADDR[31:24]==8'h04)
 *
 * Register map (offset from base):
 *   0x00: STATUS register (read-only)
 *         [0]   init_calib_complete  — MIG DDR3 calibration done
 *         [1]   mig_mmcm_locked      — MIG internal MMCM locked
 *         [2]   clk_wiz_locked       — Clocking Wizard locked
 *         [31:3] reserved (0)
 */
`include "ahb_def.svh"
`timescale 1ns / 1ps

module ahb_sys_status #(
    parameter ADDR_WIDTH = `AHB_ADDR_WIDTH,
    parameter DATA_WIDTH = `AHB_DATA_WIDTH
)(
    input  wire                    HCLK,
    input  wire                    HRESETn,

    input  wire                    HSEL,
    input  wire  [ADDR_WIDTH-1:0]  HADDR,
    input  wire  [1:0]             HTRANS,
    input  wire                    HWRITE,
    input  wire                    HREADY,

    output wire                    HREADYOUT,
    output wire                    HRESP,
    output logic [DATA_WIDTH-1:0]  HRDATA,

    // Status inputs (synchronous to HCLK)
    input  wire                    i_init_calib_complete,
    input  wire                    i_mig_mmcm_locked,
    input  wire                    i_clk_wiz_locked
);

    wire ahb_transfer = HSEL & HREADY & HTRANS[1];

    // Latch address and write flag during address phase
    reg                    latch_valid;
    reg  [ADDR_WIDTH-1:0]  latch_addr;
    reg                    latch_write;

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            latch_valid <= 1'b0;
            latch_addr  <= {ADDR_WIDTH{1'b0}};
            latch_write <= 1'b0;
        end else begin
            latch_valid <= ahb_transfer;
            if (ahb_transfer) begin
                latch_addr  <= HADDR;
                latch_write <= HWRITE;
            end
        end
    end

    // Combinational read data — available in data phase (1 cycle latency)
    wire rd_valid = latch_valid && !latch_write;

    always_comb begin
        HRDATA = {DATA_WIDTH{1'b0}};
        if (rd_valid) begin
            case (latch_addr[3:0])
                4'h0: HRDATA = {29'b0,
                                 i_clk_wiz_locked,
                                 i_mig_mmcm_locked,
                                 i_init_calib_complete};
                default: HRDATA = {DATA_WIDTH{1'b0}};
            endcase
        end
    end

    // Zero-wait-state: always ready, always OKAY
    assign HREADYOUT = 1'b1;
    assign HRESP     = 1'b0;

endmodule
