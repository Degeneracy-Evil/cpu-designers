`include "ahb_def.svh"
`timescale 1ns / 1ps

module ahb_sram_slave #(
    parameter ADDR_WIDTH   = `AHB_ADDR_WIDTH,
    parameter DATA_WIDTH   = `AHB_DATA_WIDTH,
    parameter MEM_DEPTH    = 262144,
    parameter WAIT_STATES  = 0
)(
    input  wire                    HCLK,
    input  wire                    HRESETn,

    input  wire                    HSEL,
    input  wire  [ADDR_WIDTH-1:0]  HADDR,
    input  wire  [1:0]             HTRANS,
    input  wire                    HWRITE,
    input  wire  [2:0]             HSIZE,
    input  wire  [3:0]             HBURST,
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

    reg [3:0] byte_we;
    always @(*) begin
        case (latch_size)
            `AHB_SIZE_BYTE: begin
                case (latch_addr[1:0])
                    2'b00: byte_we = 4'b0001;
                    2'b01: byte_we = 4'b0010;
                    2'b10: byte_we = 4'b0100;
                    2'b11: byte_we = 4'b1000;
                endcase
            end
            `AHB_SIZE_HWORD: begin
                byte_we = latch_addr[1] ? 4'b1100 : 4'b0011;
            end
            default: byte_we = 4'b1111;
        endcase
    end

    wire bram_read_start = ahb_transfer && !HWRITE;
    wire bram_write_do   = latch_sel && latch_write && (wait_cnt == 4'd1);

    wire        bram_ena   = bram_read_start || bram_write_do;
    wire [3:0]  bram_wea   = bram_write_do ? byte_we : 4'b0;
    wire [INDEX_WIDTH-1:0] bram_addra = bram_write_do ? latch_addr[INDEX_WIDTH+1:2] : HADDR[INDEX_WIDTH+1:2];
    wire [31:0] bram_dina  = HWDATA;
    wire [31:0] bram_douta;

    Sram u_bram (
        .clka   (HCLK),
        .ena    (bram_ena),
        .wea    (bram_wea),
        .addra  (bram_addra),
        .dina   (bram_dina),
        .douta  (bram_douta),
        .clkb   (HCLK),
        .enb    (1'b0),
        .web    (4'b0),
        .addrb  ({INDEX_WIDTH{1'b0}}),
        .dinb   (32'b0),
        .doutb  ()
    );

    always @(posedge HCLK or negedge HRESETn) begin
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

                HREADYOUT <= 1'b0;
                HRESP     <= 1'b0;
                wait_cnt  <= BRAM_LATENCY + WAIT_STATES;
            end else if ((HSEL && HREADY && (HTRANS == `AHB_TRANS_IDLE || HTRANS == `AHB_TRANS_BUSY)) ||
                         (!HSEL && HREADY)) begin
                HREADYOUT <= 1'b1;
                HRESP     <= 1'b0;
                latch_sel <= 1'b0;
            end
        end
    end

endmodule
