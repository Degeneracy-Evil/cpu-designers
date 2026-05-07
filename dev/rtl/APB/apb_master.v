`include "apb_def.vh"
`timescale 1ns / 1ps

module apb_master #(
    parameter ADDR_WIDTH = `APB_ADDR_WIDTH,
    parameter DATA_WIDTH = `APB_DATA_WIDTH,
    parameter STRB_WIDTH = `APB_STRB_WIDTH,
    parameter PROT_WIDTH = `APB_PROT_WIDTH
)(
    input  wire                  PCLK,
    input  wire                  PRESETn,

    output reg  [ADDR_WIDTH-1:0] PADDR,
    output reg  [PROT_WIDTH-1:0] PPROT,
    output reg                   PSEL,
    output reg                   PENABLE,
    output reg                   PWRITE,
    output reg  [DATA_WIDTH-1:0] PWDATA,
    output reg  [STRB_WIDTH-1:0] PSTRB,

    input  wire                  PREADY,
    input  wire  [DATA_WIDTH-1:0] PRDATA,
    input  wire                  PSLVERR,

    input  wire                  req_valid,
    input  wire                  req_write,
    input  wire  [ADDR_WIDTH-1:0] req_addr,
    input  wire  [DATA_WIDTH-1:0] req_wdata,
    input  wire  [STRB_WIDTH-1:0] req_strb,
    input  wire  [PROT_WIDTH-1:0] req_prot,

    output reg                   req_ready,
    output reg                   resp_valid,
    output reg                   resp_error,
    output reg  [DATA_WIDTH-1:0] resp_rdata
);

    reg [1:0] state;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            state     <= `APB_STATE_IDLE;
            PADDR     <= {ADDR_WIDTH{1'b0}};
            PPROT     <= {PROT_WIDTH{1'b0}};
            PSEL      <= 1'b0;
            PENABLE   <= 1'b0;
            PWRITE    <= 1'b0;
            PWDATA    <= {DATA_WIDTH{1'b0}};
            PSTRB     <= {STRB_WIDTH{1'b0}};
            req_ready <= 1'b1;
            resp_valid<= 1'b0;
            resp_error<= 1'b0;
            resp_rdata<= {DATA_WIDTH{1'b0}};
        end else begin
            case (state)
                `APB_STATE_IDLE: begin
                    resp_valid <= 1'b0;
                    if (req_valid) begin
                        state     <= `APB_STATE_SETUP;
                        PADDR     <= req_addr;
                        PPROT     <= req_prot;
                        PSEL      <= 1'b1;
                        PENABLE   <= 1'b0;
                        PWRITE    <= req_write;
                        PWDATA    <= req_wdata;
                        PSTRB     <= req_write ? req_strb : {STRB_WIDTH{1'b0}};
                        req_ready <= 1'b0;
                    end else begin
                        PSEL      <= 1'b0;
                        PENABLE   <= 1'b0;
                        req_ready <= 1'b1;
                    end
                end

                `APB_STATE_SETUP: begin
                    state   <= `APB_STATE_ACCESS;
                    PENABLE <= 1'b1;
                end

                `APB_STATE_ACCESS: begin
                    if (PREADY) begin
                        state      <= `APB_STATE_IDLE;
                        PSEL       <= 1'b0;
                        PENABLE    <= 1'b0;
                        req_ready  <= 1'b1;
                        resp_valid <= 1'b1;
                        resp_error <= PSLVERR;
                        resp_rdata <= PRDATA;
                    end
                end

                default: begin
                    state   <= `APB_STATE_IDLE;
                    PSEL    <= 1'b0;
                    PENABLE <= 1'b0;
                end
            endcase
        end
    end

endmodule
