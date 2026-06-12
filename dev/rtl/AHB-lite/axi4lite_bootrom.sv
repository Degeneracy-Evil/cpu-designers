/**
 * axi4lite_bootrom.sv — AXI4-Lite Boot ROM slave (read-only).
 *
 * Migrated from ahb_bootrom_slave.sv (AHB-Lite → AXI4-Lite).
 * Same BRAM content and address mapping; only the bus interface changed.
 *
 * Address map: 0xFC00_0000 (decoded by crossbar as HADDR[31:24]==8'hFC)
 *
 * Write channel: silently acknowledged with OKAY (ROM is read-only).
 * Read channel: 1-cycle BRAM latency, then RVALID driven.
 */
`include "axi4_def.svh"
`timescale 1ns / 1ps

module axi4lite_bootrom #(
    parameter ADDR_WIDTH   = `AXI_ADDR_WIDTH,
    parameter DATA_WIDTH   = `AXI_DATA_WIDTH,
    parameter MEM_DEPTH    = 8192
)(
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,

    // Write Address Channel
    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // Write Data Channel
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // Write Response Channel
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // Read Address Channel
    input  logic [31:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // Read Data Channel
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);

    localparam INDEX_WIDTH = $clog2(MEM_DEPTH);

    // =========================================================================
    // Write Channel — read-only slave, writes acknowledged with OKAY
    // =========================================================================
    // AW and W channels are independent; latch each handshake separately.
    // When both complete, drive BVALID with OKAY.
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
    // Read Channel — BRAM with 1-cycle latency
    // =========================================================================
    // FSM: RD_IDLE → accept AR, enable BRAM
    //       RD_DATA → BRAM output valid, drive RVALID
    enum logic { RD_IDLE, RD_DATA } rd_state;

    reg [INDEX_WIDTH-1:0] latch_addra;

    // BRAM address: live during AR handshake, latched afterwards
    wire [INDEX_WIDTH-1:0] bram_addra = (rd_state == RD_IDLE) ?
                                         s_axi_araddr[INDEX_WIDTH+1:2] :
                                         latch_addra;

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            rd_state     <= RD_IDLE;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= `AXI_RESP_OKAY;
            s_axi_rdata  <= {DATA_WIDTH{1'b0}};
            latch_addra  <= {INDEX_WIDTH{1'b0}};
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    if (s_axi_arvalid) begin
                        rd_state    <= RD_DATA;
                        latch_addra <= s_axi_araddr[INDEX_WIDTH+1:2];
                    end
                end
                RD_DATA: begin
                    s_axi_rvalid <= 1'b1;
                    s_axi_rdata  <= bram_douta;
                    s_axi_rresp  <= `AXI_RESP_OKAY;
                    if (s_axi_rready) begin
                        rd_state     <= RD_IDLE;
                        s_axi_rvalid <= 1'b0;
                    end
                end
            endcase
        end
    end

    assign s_axi_arready = (rd_state == RD_IDLE);

    // =========================================================================
    // BRAM Storage — identical to AHB version
    // =========================================================================
    wire bram_ena = s_axi_arvalid && (rd_state == RD_IDLE);

`ifdef SIMULATION
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    // BUG-55 fix: Initialize mem array to zero in simulation.
    // Without this, the entire 8K-entry array starts as X, causing the CPU
    // to fetch X instructions → X propagates through the entire pipeline
    // every cycle → massive event storm in XSim (5000x slowdown).
    initial begin
        for (integer i = 0; i < MEM_DEPTH; i = i + 1)
            mem[i] = {DATA_WIDTH{1'b0}};
    end
    wire [31:0] bram_douta = mem[bram_addra];
`else
    wire [31:0] bram_douta;

    ROM u_bram (
        .clka   (s_axi_aclk),
        .ena    (bram_ena),
        .wea    (1'b0),             // Always read-only — tie WE off
        .addra  (bram_addra),
        .dina   (32'b0),           // Don't care — never written
        .douta  (bram_douta),
        .clkb   (s_axi_aclk),
        .enb    (1'b0),
        .web    (1'b0),
        .addrb  ({INDEX_WIDTH{1'b0}}),
        .dinb   (32'b0),
        .doutb  ()
    );
`endif

endmodule
