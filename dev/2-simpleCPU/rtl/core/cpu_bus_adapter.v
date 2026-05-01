`timescale 1ns / 1ps
`include "ahb_def.vh"

module cpu_bus_adapter #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                        clk,
    input  wire                        resetn,

    input  wire  [ADDR_WIDTH-1:0]      inst_addr,
    output wire  [DATA_WIDTH-1:0]      inst_data,
    input  wire                        inst_req,

    input  wire  [ADDR_WIDTH-1:0]      data_addr,
    input  wire  [DATA_WIDTH-1:0]      data_wdata,
    output wire  [DATA_WIDTH-1:0]      data_rdata,
    input  wire  [3:0]                 data_wen,
    input  wire                        data_req,

    output reg                         req_valid,
    output reg                         req_write,
    output reg  [ADDR_WIDTH-1:0]       req_addr,
    output reg  [DATA_WIDTH-1:0]       req_wdata,
    output reg  [2:0]                  req_size,
    output reg  [2:0]                  req_burst,
    output reg  [3:0]                  req_prot,
    output reg                         req_lock,

    input  wire                        req_ready,
    input  wire                        resp_valid,
    input  wire                        resp_error,
    input  wire  [DATA_WIDTH-1:0]      resp_rdata,

    output wire                        inst_valid,
    output wire                        data_valid
);

    localparam ST_IDLE   = 3'b000;
    localparam ST_I_REQ  = 3'b001;
    localparam ST_I_WAIT = 3'b010;
    localparam ST_D_REQ  = 3'b011;
    localparam ST_D_WAIT = 3'b100;

    reg [2:0] state;

    reg [DATA_WIDTH-1:0] inst_data_r;
    reg [DATA_WIDTH-1:0] data_rdata_r;
    reg                  inst_valid_r;
    reg                  data_valid_r;

    assign inst_data  = inst_data_r;
    assign data_rdata = data_rdata_r;
    assign inst_valid = inst_valid_r;
    assign data_valid = data_valid_r;

    reg [ADDR_WIDTH-1:0] i_addr_r;
    reg d_write_r;
    reg [2:0] d_size_r;

    always @(*) begin
        d_write_r = 1'b0;
        d_size_r  = `AHB_SIZE_WORD;
        case (data_wen)
            4'b1111: begin
                d_write_r = 1'b0;
                d_size_r  = `AHB_SIZE_WORD;
            end
            4'b1110: begin
                d_write_r = 1'b1;
                d_size_r  = `AHB_SIZE_BYTE;
            end
            4'b1101: begin
                d_write_r = 1'b1;
                d_size_r  = `AHB_SIZE_BYTE;
            end
            4'b1011: begin
                d_write_r = 1'b1;
                d_size_r  = `AHB_SIZE_BYTE;
            end
            4'b0111: begin
                d_write_r = 1'b1;
                d_size_r  = `AHB_SIZE_BYTE;
            end
            4'b1100: begin
                d_write_r = 1'b1;
                d_size_r  = `AHB_SIZE_HWORD;
            end
            4'b0011: begin
                d_write_r = 1'b1;
                d_size_r  = `AHB_SIZE_HWORD;
            end
            4'b0000: begin
                d_write_r = 1'b1;
                d_size_r  = `AHB_SIZE_WORD;
            end
            default: begin
                d_write_r = 1'b0;
                d_size_r  = `AHB_SIZE_WORD;
            end
        endcase
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state       <= ST_IDLE;
            req_valid   <= 1'b0;
            req_write   <= 1'b0;
            req_addr    <= {ADDR_WIDTH{1'b0}};
            req_wdata   <= {DATA_WIDTH{1'b0}};
            req_size    <= `AHB_SIZE_WORD;
            req_burst   <= `AHB_BURST_SINGLE;
            req_prot    <= 4'b0011;
            req_lock    <= 1'b0;
            inst_data_r <= {DATA_WIDTH{1'b0}};
            data_rdata_r<= {DATA_WIDTH{1'b0}};
            inst_valid_r<= 1'b0;
            data_valid_r<= 1'b0;
            i_addr_r    <= {ADDR_WIDTH{1'b0}};
        end else begin
            inst_valid_r <= 1'b0;
            data_valid_r <= 1'b0;
            case (state)
                ST_IDLE: begin
                    req_valid <= 1'b0;
                    if (inst_req) begin
                        state     <= ST_I_REQ;
                    end else if (data_req) begin
                        state     <= ST_D_REQ;
                    end
                end

                ST_I_REQ: begin
                    req_valid <= 1'b1;
                    req_write <= 1'b0;
                    req_addr  <= inst_addr;
                    req_wdata <= {DATA_WIDTH{1'b0}};
                    req_size  <= `AHB_SIZE_WORD;
                    req_burst <= `AHB_BURST_SINGLE;
                    req_prot  <= 4'b0011;
                    req_lock  <= 1'b0;
                    i_addr_r  <= inst_addr;
                    if (req_ready) begin
                        state     <= ST_I_WAIT;
                    end
                end

                ST_I_WAIT: begin
                    req_valid <= 1'b0;
                    if (resp_valid) begin
                        if (inst_addr == i_addr_r) begin
                            inst_data_r <= resp_rdata;
                            inst_valid_r<= 1'b1;
                            if (data_req) begin
                                state <= ST_D_REQ;
                            end else begin
                                state <= ST_IDLE;
                            end
                        end else begin
                            state <= ST_I_REQ;
                        end
                    end
                end

                ST_D_REQ: begin
                    req_valid <= 1'b1;
                    req_write <= d_write_r;
                    req_addr  <= data_addr;
                    req_wdata <= data_wdata;
                    req_size  <= d_size_r;
                    req_burst <= `AHB_BURST_SINGLE;
                    req_prot  <= 4'b0011;
                    req_lock  <= 1'b0;
                    if (req_ready) begin
                        state     <= ST_D_WAIT;
                    end
                end

                ST_D_WAIT: begin
                    req_valid <= 1'b0;
                    if (resp_valid) begin
                        data_rdata_r <= resp_rdata;
                        data_valid_r <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state     <= ST_IDLE;
                    req_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
