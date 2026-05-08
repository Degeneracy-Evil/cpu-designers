`timescale 1ns / 1ps
`include "ahb_def.vh"

module cpu_bus_bridge(
    input         clk,
    input         reset,

    input         icache_mmio_req,
    input  [31:0] icache_mmio_addr,

    input         dcache_mmio_req,
    input  [31:0] dcache_mmio_addr,
    input  [31:0] dcache_mmio_wdata,
    input         dcache_mmio_hwrite,
    input  [2:0]  dcache_mmio_hsize,

    output [31:0] ahb_inst_data,
    output        ahb_inst_valid,
    output [31:0] ahb_data_rdata,
    output        ahb_data_valid,

    output [31:0] HADDR,
    output [1:0]  HTRANS,
    output        HWRITE,
    output [2:0]  HSIZE,
    output [2:0]  HBURST,
    output [3:0]  HPROT,
    output        HMASTLOCK,
    output [31:0] HWDATA,
    input  [31:0] HRDATA,
    input         HREADY,
    input         HRESP
);

    localparam AHB_IDLE = 2'd0;
    localparam AHB_ADDR = 2'd1;
    localparam AHB_DATA = 2'd2;

    reg [1:0]  ahb_state;
    reg [31:0] ahb_HADDR_r;
    reg [1:0]  ahb_HTRANS_r;
    reg        ahb_HWRITE_r;
    reg [2:0]  ahb_HSIZE_r;
    reg [2:0]  ahb_HBURST_r;
    reg [3:0]  ahb_HPROT_r;
    reg        ahb_HMASTLOCK_r;
    reg [31:0] ahb_HWDATA_r;

    reg [31:0] ahb_latch_wdata;
    reg        ahb_is_ireq_r;

    reg [31:0] ahb_inst_data_r;
    reg        ahb_inst_valid_r;
    reg [31:0] ahb_data_rdata_r;
    reg        ahb_data_valid_r;

    assign ahb_inst_data  = ahb_inst_data_r;
    assign ahb_inst_valid = ahb_inst_valid_r;
    assign ahb_data_rdata = ahb_data_rdata_r;
    assign ahb_data_valid = ahb_data_valid_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ahb_state        <= AHB_IDLE;
            ahb_HADDR_r     <= 32'b0;
            ahb_HTRANS_r    <= `AHB_TRANS_IDLE;
            ahb_HWRITE_r    <= 1'b0;
            ahb_HSIZE_r     <= `AHB_SIZE_WORD;
            ahb_HBURST_r    <= `AHB_BURST_SINGLE;
            ahb_HPROT_r     <= 4'b0011;
            ahb_HMASTLOCK_r <= 1'b0;
            ahb_HWDATA_r    <= 32'b0;
            ahb_latch_wdata <= 32'b0;
            ahb_is_ireq_r   <= 1'b0;
            ahb_inst_data_r <= 32'b0;
            ahb_inst_valid_r<= 1'b0;
            ahb_data_rdata_r<= 32'b0;
            ahb_data_valid_r<= 1'b0;
        end else begin
            ahb_inst_valid_r <= 1'b0;
            ahb_data_valid_r <= 1'b0;

            case (ahb_state)
                AHB_IDLE: begin
                    ahb_HTRANS_r <= `AHB_TRANS_IDLE;
                    if (icache_mmio_req && !ahb_inst_valid_r && !ahb_data_valid_r) begin
                        ahb_state        <= AHB_ADDR;
                        ahb_HADDR_r     <= icache_mmio_addr;
                        ahb_HTRANS_r    <= `AHB_TRANS_NONSEQ;
                        ahb_HWRITE_r    <= 1'b0;
                        ahb_HSIZE_r     <= `AHB_SIZE_WORD;
                        ahb_HBURST_r    <= `AHB_BURST_SINGLE;
                        ahb_HPROT_r     <= 4'b0011;
                        ahb_HMASTLOCK_r <= 1'b0;
                        ahb_latch_wdata <= 32'b0;
                        ahb_is_ireq_r   <= 1'b1;
                    end else if (dcache_mmio_req && !ahb_inst_valid_r && !ahb_data_valid_r) begin
                        ahb_state        <= AHB_ADDR;
                        ahb_HADDR_r     <= dcache_mmio_addr;
                        ahb_HTRANS_r    <= `AHB_TRANS_NONSEQ;
                        ahb_HWRITE_r    <= dcache_mmio_hwrite;
                        ahb_HSIZE_r     <= dcache_mmio_hsize;
                        ahb_HBURST_r    <= `AHB_BURST_SINGLE;
                        ahb_HPROT_r     <= 4'b0011;
                        ahb_HMASTLOCK_r <= 1'b0;
                        ahb_latch_wdata <= dcache_mmio_wdata;
                        ahb_is_ireq_r   <= 1'b0;
                    end
                end

                AHB_ADDR: begin
                    if (HREADY) begin
                        if (HRESP == `AHB_RESP_ERROR) begin
                            ahb_state     <= AHB_IDLE;
                            ahb_HTRANS_r  <= `AHB_TRANS_IDLE;
                            ahb_data_valid_r <= 1'b1;
                        end else begin
                            ahb_state     <= AHB_DATA;
                            ahb_HWDATA_r  <= ahb_latch_wdata;
                        end
                    end else begin
                        ahb_HTRANS_r <= `AHB_TRANS_IDLE;
                    end
                end

                AHB_DATA: begin
                    if (HREADY) begin
                        ahb_state     <= AHB_IDLE;
                        ahb_HTRANS_r  <= `AHB_TRANS_IDLE;
                        if (ahb_is_ireq_r) begin
                            ahb_inst_data_r  <= HRDATA;
                            ahb_inst_valid_r <= 1'b1;
                        end else begin
                            ahb_data_rdata_r <= HRDATA;
                            ahb_data_valid_r <= 1'b1;
                        end
                    end
                end

                default: begin
                    ahb_state     <= AHB_IDLE;
                    ahb_HTRANS_r  <= `AHB_TRANS_IDLE;
                end
            endcase
        end
    end

    assign HADDR     = ahb_HADDR_r;
    assign HTRANS    = ahb_HTRANS_r;
    assign HWRITE    = ahb_HWRITE_r;
    assign HSIZE     = ahb_HSIZE_r;
    assign HBURST    = ahb_HBURST_r;
    assign HPROT     = ahb_HPROT_r;
    assign HMASTLOCK = ahb_HMASTLOCK_r;
    assign HWDATA    = ahb_HWDATA_r;

endmodule
