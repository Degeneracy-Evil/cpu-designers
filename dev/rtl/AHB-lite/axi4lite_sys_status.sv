/**
 * axi4lite_sys_status.sv — AXI4-Lite read-only System Status slave.
 *
 * Migrated from ahb_sys_status.sv (AHB-Lite → AXI4-Lite).
 * Same register map and status inputs; only the bus interface changed.
 *
 * Address map: 0x0400_0000 (decoded by crossbar as HADDR[31:24]==8'h04)
 *
 * Register map (offset from base):
 *   0x00: STATUS register (read-only)
 *         [0]   init_calib_complete  — MIG DDR3 calibration done
 *         [1]   mig_mmcm_locked      — MIG internal MMCM locked
 *         [2]   clk_wiz_locked       — Clocking Wizard locked
 *         [31:3] reserved (0)
 *
 * Write channel: silently acknowledged with OKAY (status is read-only).
 * Read channel: combinational status mux, 1-cycle latency (AR → R).
 */
`include "axi4_def.svh"
`timescale 1ns / 1ps

module axi4lite_sys_status #(
    parameter ADDR_WIDTH = `AXI_ADDR_WIDTH,
    parameter DATA_WIDTH = `AXI_DATA_WIDTH
)(
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,

    // Write Address Channel
    input  logic [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [2:0]            s_axi_awprot,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,

    // Write Data Channel
    input  logic [DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,

    // Write Response Channel
    output logic [1:0]            s_axi_bresp,
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready,

    // Read Address Channel
    input  logic [ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [2:0]            s_axi_arprot,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,

    // Read Data Channel
    output logic [DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,

    // Status inputs (synchronous to s_axi_aclk)
    input  wire                   i_init_calib_complete,
    input  wire                   i_mig_mmcm_locked,
    input  wire                   i_clk_wiz_locked
);

    // =========================================================================
    // Write Channel — read-only slave, writes acknowledged with OKAY
    // =========================================================================
    reg  aw_latch, w_latch;
    wire aw_done = aw_latch || (s_axi_awready && s_axi_awvalid);
    wire w_done  = w_latch  || (s_axi_wready  && s_axi_wvalid);

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            aw_latch     <= 1'b0;
            w_latch      <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= `AXI_RESP_OKAY;
        end else begin
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
                aw_latch     <= 1'b0;
                w_latch      <= 1'b0;
            end else if (!s_axi_bvalid) begin
                if (s_axi_awready && s_axi_awvalid)
                    aw_latch <= 1'b1;
                if (s_axi_wready && s_axi_wvalid)
                    w_latch <= 1'b1;
                if (aw_done && w_done)
                    s_axi_bvalid <= 1'b1;
            end
        end
    end

    assign s_axi_awready = !aw_latch && !s_axi_bvalid;
    assign s_axi_wready  = !w_latch  && !s_axi_bvalid;

    // =========================================================================
    // Read Channel — combinational status register, 1-cycle latency
    // =========================================================================
    // Latch address during AR handshake, then drive RVALID with muxed data.
    reg [ADDR_WIDTH-1:0] latch_araddr;

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= `AXI_RESP_OKAY;
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            latch_araddr  <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end else if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= `AXI_RESP_OKAY;
                latch_araddr <= s_axi_araddr;
                // Combinational mux based on latched address
                case (s_axi_araddr[3:0])
                    4'h0: s_axi_rdata <= {29'b0,
                                           i_clk_wiz_locked,
                                           i_mig_mmcm_locked,
                                           i_init_calib_complete};
                    default: s_axi_rdata <= {DATA_WIDTH{1'b0}};
                endcase
            end
        end
    end

    assign s_axi_arready = !s_axi_rvalid;

endmodule
