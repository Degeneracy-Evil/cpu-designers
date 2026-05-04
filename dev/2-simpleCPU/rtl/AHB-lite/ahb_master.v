`include "ahb_def.vh"
`timescale 1ns / 1ps

module ahb_master #(
    parameter ADDR_WIDTH = `AHB_ADDR_WIDTH,
    parameter DATA_WIDTH = `AHB_DATA_WIDTH
)(
    input  wire                    HCLK,
    input  wire                    HRESETn,

    input  wire                    req_valid,
    input  wire                    req_write,
    input  wire  [ADDR_WIDTH-1:0]  req_addr,
    input  wire  [DATA_WIDTH-1:0]  req_wdata,
    input  wire  [2:0]             req_size,
    input  wire  [2:0]             req_burst,
    input  wire  [3:0]             req_prot,
    input  wire                    req_lock,

    output wire                    req_ready,
    output wire                    resp_valid,
    output wire                    resp_error,
    output wire  [DATA_WIDTH-1:0]  resp_rdata,

    output reg  [ADDR_WIDTH-1:0]   HADDR,
    output reg  [1:0]              HTRANS,
    output reg                     HWRITE,
    output reg  [2:0]              HSIZE,
    output reg  [2:0]              HBURST,
    output reg  [3:0]              HPROT,
    output reg                     HMASTLOCK,
    output reg  [DATA_WIDTH-1:0]   HWDATA,

    input  wire                    HREADY,
    input  wire                    HRESP,
    input  wire  [DATA_WIDTH-1:0]  HRDATA
);

    reg [1:0] state;
    localparam ST_IDLE   = 2'b00;
    localparam ST_ADDR   = 2'b01;
    localparam ST_DATA   = 2'b10;
    localparam ST_ERROR  = 2'b11;

    reg [DATA_WIDTH-1:0]  latch_wdata;

    reg resp_valid_r;
    reg resp_error_r;
    reg [DATA_WIDTH-1:0] resp_rdata_r;

    assign resp_valid = resp_valid_r;
    assign resp_error = resp_error_r;
    assign resp_rdata = resp_rdata_r;

    wire transfer_done = HREADY & (HTRANS[1] | (HTRANS == `AHB_TRANS_IDLE));

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state        <= ST_IDLE;
            HADDR        <= {ADDR_WIDTH{1'b0}};
            HTRANS       <= `AHB_TRANS_IDLE;
            HWRITE       <= 1'b0;
            HSIZE        <= `AHB_SIZE_WORD;
            HBURST       <= `AHB_BURST_SINGLE;
            HPROT        <= 4'b0011;
            HMASTLOCK    <= 1'b0;
            HWDATA       <= {DATA_WIDTH{1'b0}};
            latch_wdata  <= {DATA_WIDTH{1'b0}};
            resp_valid_r <= 1'b0;
            resp_error_r <= 1'b0;
            resp_rdata_r <= {DATA_WIDTH{1'b0}};
        end else begin
            resp_valid_r <= 1'b0;

            case (state)
                ST_IDLE: begin
                    HTRANS <= `AHB_TRANS_IDLE;
                    if (req_valid) begin
                        state       <= ST_ADDR;
                        HADDR       <= req_addr;
                        HTRANS      <= `AHB_TRANS_NONSEQ;
                        HWRITE      <= req_write;
                        HSIZE       <= req_size;
                        HBURST      <= req_burst;
                        HPROT       <= req_prot;
                        HMASTLOCK   <= req_lock;
                        latch_wdata <= req_wdata;
                    end
                end

                ST_ADDR: begin
                    if (HREADY) begin
                        if (HRESP == `AHB_RESP_ERROR) begin
                            state        <= ST_ERROR;
                            HTRANS       <= `AHB_TRANS_IDLE;
                            resp_valid_r <= 1'b1;
                            resp_error_r <= 1'b1;
                        end else begin
                            state  <= ST_DATA;
                            HWDATA <= latch_wdata;
                        end
                    end else begin
                        HTRANS <= `AHB_TRANS_IDLE;
                    end
                end

                ST_DATA: begin
                    if (HREADY) begin
                        if (HRESP == `AHB_RESP_ERROR) begin
                            state        <= ST_ERROR;
                            HTRANS       <= `AHB_TRANS_IDLE;
                            resp_valid_r <= 1'b1;
                            resp_error_r <= 1'b1;
                        end else begin
                            state        <= ST_IDLE;
                            HTRANS       <= `AHB_TRANS_IDLE;
                            resp_valid_r <= 1'b1;
                            resp_error_r <= 1'b0;
                            resp_rdata_r <= HRDATA;
                        end
                    end
                end

                ST_ERROR: begin
                    if (HREADY) begin
                        state  <= ST_IDLE;
                        HTRANS <= `AHB_TRANS_IDLE;
                    end
                end

                default: begin
                    state  <= ST_IDLE;
                    HTRANS <= `AHB_TRANS_IDLE;
                end
            endcase
        end
    end

    assign req_ready = (state == ST_IDLE);

endmodule
