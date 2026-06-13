/**
 * axi4lite_default_slave.sv — AXI4-Lite Default Slave (decode error).
 *
 * Migrated from ahb_default_slave.sv (AHB-Lite → AXI4-Lite).
 * Returns DECERR for every transaction — read and write alike.
 * No internal state beyond handshake latches.
 *
 * Address map: unmapped addresses (decoded by crossbar as default).
 */
`include "axi4_def.svh"
`timescale 1ns / 1ps

module axi4lite_default_slave #(
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
    input  logic                  s_axi_rready
);

    // =========================================================================
    // Write Channel — accept AW + W, respond with DECERR
    // =========================================================================
    reg  aw_latch, w_latch;
    wire aw_done = aw_latch || (s_axi_awready && s_axi_awvalid);
    wire w_done  = w_latch  || (s_axi_wready  && s_axi_wvalid);

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            aw_latch     <= 1'b0;
            w_latch      <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= `AXI_RESP_DECERR;
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
    // Read Channel — accept AR, respond with DECERR + zero data
    // =========================================================================
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= `AXI_RESP_DECERR;
            s_axi_rdata  <= {DATA_WIDTH{1'b0}};
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end else if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= `AXI_RESP_DECERR;
                s_axi_rdata  <= {DATA_WIDTH{1'b0}};
            end
        end
    end

    assign s_axi_arready = !s_axi_rvalid;

endmodule
