`include "apb_def.svh"
`timescale 1ns / 1ps

module apb_slave #(
    parameter ADDR_WIDTH   = `APB_ADDR_WIDTH,
    parameter DATA_WIDTH   = `APB_DATA_WIDTH,
    parameter STRB_WIDTH   = `APB_STRB_WIDTH,
    parameter PROT_WIDTH   = `APB_PROT_WIDTH,
    parameter REG_NUM      = 4,
    parameter BASE_ADDR    = 32'h0000_0000
)(
    input  wire                  PCLK,
    input  wire                  PRESETn,

    input  wire  [ADDR_WIDTH-1:0] PADDR,
    input  wire  [PROT_WIDTH-1:0] PPROT,
    input  wire                   PSEL,
    input  wire                   PENABLE,
    input  wire                   PWRITE,
    input  wire  [DATA_WIDTH-1:0] PWDATA,
    input  wire  [STRB_WIDTH-1:0] PSTRB,

    output reg                   PREADY,
    output reg  [DATA_WIDTH-1:0] PRDATA,
    output reg                   PSLVERR
);

    localparam REG_ADDR_WIDTH = (REG_NUM > 1) ? $clog2(REG_NUM) : 1;

    reg [DATA_WIDTH-1:0] regs [0:REG_NUM-1];

    wire [REG_ADDR_WIDTH-1:0] reg_idx;
    assign reg_idx = PADDR[REG_ADDR_WIDTH+1:2];

    integer i;
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            for (i = 0; i < REG_NUM; i = i + 1) begin
                regs[i] <= {DATA_WIDTH{1'b0}};
            end
            PREADY   <= 1'b1;
            PRDATA   <= {DATA_WIDTH{1'b0}};
            PSLVERR  <= 1'b0;
        end else begin
            PREADY  <= 1'b1;
            PSLVERR <= 1'b0;

            if (PSEL & PENABLE & PWRITE & PREADY) begin
                for (i = 0; i < STRB_WIDTH; i = i + 1) begin
                    if (PSTRB[i]) begin
                        regs[reg_idx][i*8+:8] <= PWDATA[i*8+:8];
                    end
                end
            end

            if (PSEL & PENABLE) begin
                if (!PWRITE) begin
                    PRDATA <= regs[reg_idx];
                end
            end else begin
                PRDATA <= {DATA_WIDTH{1'b0}};
            end
        end
    end

endmodule
