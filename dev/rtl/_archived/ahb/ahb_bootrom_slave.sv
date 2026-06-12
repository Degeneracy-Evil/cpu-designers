/**
 * ahb_bootrom_slave.sv — AHB-Lite Boot ROM slave (read-only).
 *
 * Same interface as ahb_sram_slave but writes are silently acknowledged
 * (HREADYOUT=1, HRESP=OKAY) without modifying BRAM contents.
 * The BRAM is initialized via COE file in synthesis or $readmemh in simulation.
 *
 * Address map: 0xFC00_0000 (decoded by ahb_lite_bus as HADDR[31:24]==8'hFC)
 */
`include "ahb_def.svh"
`timescale 1ns / 1ps

module ahb_bootrom_slave #(
    parameter ADDR_WIDTH   = `AHB_ADDR_WIDTH,
    parameter DATA_WIDTH   = `AHB_DATA_WIDTH,
    parameter MEM_DEPTH    = 8192,
    parameter WAIT_STATES  = 0
)(
    input  wire                    HCLK,
    input  wire                    HRESETn,

    input  wire                    HSEL,
    input  wire  [ADDR_WIDTH-1:0]  HADDR,
    input  wire  [1:0]             HTRANS,
    input  wire                    HWRITE,
    input  wire  [2:0]             HSIZE,
    input  wire  [2:0]             HBURST,
    input  wire  [3:0]             HPROT,
    input  wire  [DATA_WIDTH-1:0]  HWDATA,
    input  wire                    HREADY,

    output reg                     HREADYOUT,
    output reg                     HRESP,
    output reg  [DATA_WIDTH-1:0]   HRDATA
);

    localparam INDEX_WIDTH  = $clog2(MEM_DEPTH);
    localparam BRAM_LATENCY = 1;

    reg [ADDR_WIDTH-1:0]   latch_addr;
    reg                    latch_write;
    reg [2:0]              latch_size;
    reg                    latch_sel;

    wire ahb_transfer = HSEL & HREADY & (HTRANS[1]);

    reg [3:0] wait_cnt;

    // BRAM read signals
    wire bram_read_start = ahb_transfer && !HWRITE;
    // Writes are ignored — BRAM never written, but we still need to
    // complete the AHB data phase with HREADYOUT=1.
    wire bram_write_do   = latch_sel && latch_write && (wait_cnt == 4'd1);

    wire        bram_ena   = bram_read_start;           // Only enable for reads
    wire [INDEX_WIDTH-1:0] bram_addra = HADDR[INDEX_WIDTH+1:2];

    // --- Storage: BRAM IP (synthesis) vs register array (simulation) ---
    // In simulation, expose a `mem` array so testbenches can inject
    // trampoline instructions via hierarchical reference (e.g. .mem[0]).
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
        .clka   (HCLK),
        .ena    (bram_ena),
        .wea    (1'b0),             // Always read-only — tie WE off
        .addra  (bram_addra),
        .dina   (32'b0),           // Don't care — never written
        .douta  (bram_douta),
        .clkb   (HCLK),
        .enb    (1'b0),
        .web    (1'b0),
        .addrb  ({INDEX_WIDTH{1'b0}}),
        .dinb   (32'b0),
        .doutb  ()
    );
`endif

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HREADYOUT  <= 1'b1;
            HRESP      <= 1'b0;
            HRDATA     <= {DATA_WIDTH{1'b0}};
            latch_addr <= {ADDR_WIDTH{1'b0}};
            latch_write<= 1'b0;
            latch_size <= `AHB_SIZE_WORD;
            latch_sel  <= 1'b0;
            wait_cnt   <= 4'd0;
        end else begin
            if (wait_cnt > 4'd0) begin
                wait_cnt <= wait_cnt - 4'd1;
                if (wait_cnt == 4'd1) begin
                    HREADYOUT <= 1'b1;
                    HRESP     <= 1'b0;
                    if (!latch_write) begin
                        HRDATA <= bram_douta;
                    end
                    latch_sel <= 1'b0;
                end
            end else if (ahb_transfer) begin
                latch_addr  <= HADDR;
                latch_write <= HWRITE;
                latch_size  <= HSIZE;
                latch_sel   <= 1'b1;

                if (HWRITE) begin
                    // Write to ROM: acknowledge immediately, discard data
                    HREADYOUT <= 1'b1;
                    HRESP     <= 1'b0;
                    wait_cnt  <= 4'd0;
                end else begin
                    // Read from ROM: normal BRAM latency
                    HREADYOUT <= 1'b0;
                    HRESP     <= 1'b0;
                    wait_cnt  <= BRAM_LATENCY + WAIT_STATES;
                end
            end else if ((HSEL && HREADY && (HTRANS == `AHB_TRANS_IDLE || HTRANS == `AHB_TRANS_BUSY)) ||
                         (!HSEL && HREADY)) begin
                HREADYOUT <= 1'b1;
                HRESP     <= 1'b0;
                latch_sel <= 1'b0;
            end
        end
    end

endmodule
