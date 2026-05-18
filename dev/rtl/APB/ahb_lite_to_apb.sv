`include "apb_def.svh"
`timescale 1ns / 1ps

module ahb_lite_to_apb #(
    parameter ADDR_WIDTH = `APB_ADDR_WIDTH,
    parameter DATA_WIDTH = `APB_DATA_WIDTH
)(
    input  wire                  HCLK,
    input  wire                  HRESETn,

    input  wire  [ADDR_WIDTH-1:0] HADDR,
    input  wire  [1:0]            HTRANS,
    input  wire                   HWRITE,
    input  wire  [2:0]            HSIZE,
    input  wire  [2:0]            HBURST,
    input  wire  [3:0]            HPROT,
    input  wire  [DATA_WIDTH-1:0] HWDATA,
    input  wire                   HSEL,
    input  wire                   HREADY,

    output reg                   HREADYOUT,
    output reg                   HRESP,
    output reg  [DATA_WIDTH-1:0] HRDATA,

    output reg  [ADDR_WIDTH-1:0] PADDR,
    output reg  [2:0]            PPROT,
    output reg                   PSEL,
    output reg                   PENABLE,
    output reg                   PWRITE,
    output reg  [DATA_WIDTH-1:0] PWDATA,
    output reg  [DATA_WIDTH/8-1:0] PSTRB,

    input  wire                  PREADY,
    input  wire  [DATA_WIDTH-1:0] PRDATA,
    input  wire                  PSLVERR
);

    localparam BR_IDLE    = 2'b00;
    localparam BR_SETUP   = 2'b01;
    localparam BR_ACCESS  = 2'b10;

    reg [1:0] br_state;

    reg [DATA_WIDTH/8-1:0] latch_strb;

    wire ahb_transfer = HSEL & HREADY & (HTRANS[1]);

    always @(*) begin
        case (HSIZE)
            3'b000: latch_strb = 1 << HADDR[$clog2(DATA_WIDTH/8)-1:0];
            3'b001: latch_strb = 3 << {HADDR[$clog2(DATA_WIDTH/8)-1:1], 1'b0};
            default: latch_strb = {(DATA_WIDTH/8){1'b1}};
        endcase
    end

    always @(*) begin
        PPROT[0] = ~HPROT[1];
        PPROT[1] = ~HPROT[2];
        PPROT[2] = ~HPROT[0];
    end

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            br_state    <= BR_IDLE;
            PADDR       <= {ADDR_WIDTH{1'b0}};
            PSEL        <= 1'b0;
            PENABLE     <= 1'b0;
            PWRITE      <= 1'b0;
            PWDATA      <= {DATA_WIDTH{1'b0}};
            PSTRB       <= {(DATA_WIDTH/8){1'b0}};
            HREADYOUT   <= 1'b1;
            HRESP       <= 1'b0;
            HRDATA      <= {DATA_WIDTH{1'b0}};
        end else begin
            case (br_state)
                BR_IDLE: begin
                    if (ahb_transfer) begin
                        br_state    <= BR_SETUP;
                        PADDR       <= HADDR;
                        PSEL        <= 1'b1;
                        PENABLE     <= 1'b0;
                        PWRITE      <= HWRITE;
                        PSTRB       <= HWRITE ? latch_strb : {(DATA_WIDTH/8){1'b0}};
                        HREADYOUT   <= 1'b0;
                        HRESP       <= 1'b0;
                    end else begin
                        PSEL      <= 1'b0;
                        PENABLE   <= 1'b0;
                        HREADYOUT <= 1'b1;
                        HRESP     <= 1'b0;
                    end
                end

                BR_SETUP: begin
                    br_state  <= BR_ACCESS;
                    PENABLE   <= 1'b1;
                    PWDATA    <= HWDATA;
                    HREADYOUT <= 1'b0;
                end

                BR_ACCESS: begin
                    if (PREADY) begin
                        HRDATA <= PRDATA;
                        if (PSLVERR) begin
                            HRESP <= 1'b1;
                            if (HREADY) begin
                                br_state  <= BR_IDLE;
                                PSEL      <= 1'b0;
                                PENABLE   <= 1'b0;
                                HREADYOUT <= 1'b1;
                                HRESP     <= 1'b0;
                            end else begin
                                HREADYOUT <= 1'b0;
                            end
                        end else begin
                            if (ahb_transfer) begin
                                br_state    <= BR_SETUP;
                                PADDR       <= HADDR;
                                PSEL        <= 1'b1;
                                PENABLE     <= 1'b0;
                                PWRITE      <= HWRITE;
                                PSTRB       <= HWRITE ? latch_strb : {(DATA_WIDTH/8){1'b0}};
                                HREADYOUT   <= 1'b0;
                                HRESP       <= 1'b0;
                            end else begin
                                br_state  <= BR_IDLE;
                                PSEL      <= 1'b0;
                                PENABLE   <= 1'b0;
                                HREADYOUT <= 1'b1;
                                HRESP     <= 1'b0;
                            end
                        end
                    end else begin
                        HREADYOUT <= 1'b0;
                        HRESP     <= 1'b0;
                    end
                end

                default: begin
                    br_state  <= BR_IDLE;
                    PSEL      <= 1'b0;
                    PENABLE   <= 1'b0;
                    HREADYOUT <= 1'b1;
                    HRESP     <= 1'b0;
                end
            endcase
        end
    end

endmodule
