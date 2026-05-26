`timescale 1ns / 1ps
`include "ahb_def.svh"

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

    input         icache_refill_req,
    input  [31:0] icache_refill_addr,
    output [255:0] icache_refill_data,
    output        icache_refill_valid,

    input         dcache_refill_req,
    input  [31:0] dcache_refill_addr,
    output [255:0] dcache_refill_data,
    output        dcache_refill_valid,

    input         dcache_wb_req,
    input  [31:0] dcache_wb_addr,
    input  [255:0] dcache_wb_data,
    output        dcache_wb_valid,

    input         ptw_i_req,
    input  [31:0] ptw_i_addr,
    input         ptw_i_we,
    input  [31:0] ptw_i_wdata,
    output [31:0] ptw_i_rdata,
    output        ptw_i_done,
    output        ptw_i_error,

    input         ptw_d_req,
    input  [31:0] ptw_d_addr,
    input         ptw_d_we,
    input  [31:0] ptw_d_wdata,
    output [31:0] ptw_d_rdata,
    output        ptw_d_done,
    output        ptw_d_error,

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
    input         HRESP,

    output        icache_error,
    output        dcache_error,
    output        dcache_error_is_store,
    output [31:0] bus_error_addr
);

    localparam S_IDLE          = 4'd0;
    localparam S_MMIO_ADDR     = 4'd1;
    localparam S_MMIO_DATA     = 4'd2;
    localparam S_IREFILL_ADDR  = 4'd3;
    localparam S_IREFILL_DATA  = 4'd4;
    localparam S_DREFILL_ADDR  = 4'd5;
    localparam S_DREFILL_DATA  = 4'd6;
    localparam S_WB_ADDR       = 4'd7;
    localparam S_WB_DATA       = 4'd8;
    localparam S_PTW_ADDR      = 4'd9;
    localparam S_PTW_DATA      = 4'd10;

    reg [3:0]  state;

    reg [31:0] haddr_r;
    reg [1:0]  htrans_r;
    reg        hwrite_r;
    reg [2:0]  hsize_r;
    reg [2:0]  hburst_r;
    reg [3:0]  hprot_r;
    reg        hmastlock_r;
    reg [31:0] hwdata_r;

    reg [31:0] mmio_latch_wdata;
    reg        mmio_is_ireq;

    reg [31:0] ahb_inst_data_r;
    reg        ahb_inst_valid_r;
    reg [31:0] ahb_data_rdata_r;
    reg        ahb_data_valid_r;

    reg        mmio_inst_served;
    reg        mmio_data_served;

    reg [2:0]   beat_cnt;
    reg [31:0]  burst_base_addr;
    reg [255:0] refill_shift_reg;
    reg [255:0] wb_shift_reg;

    reg icache_refill_valid_r;
    reg dcache_refill_valid_r;
    reg dcache_wb_valid_r;

    reg icache_error_r;
    reg dcache_error_r;
    reg dcache_error_is_store_r;
    reg [31:0] bus_error_addr_r;

    reg [31:0] ptw_rdata_r;
    reg        ptw_done_r;
    reg        ptw_error_r;
    reg        ptw_is_inst_r;

    assign ahb_inst_data     = ahb_inst_data_r;
    assign ahb_inst_valid    = ahb_inst_valid_r;
    assign ahb_data_rdata    = ahb_data_rdata_r;
    assign ahb_data_valid    = ahb_data_valid_r;
    assign icache_refill_data  = refill_shift_reg;
    assign icache_refill_valid = icache_refill_valid_r;
    assign dcache_refill_data  = refill_shift_reg;
    assign dcache_refill_valid = dcache_refill_valid_r;
    assign dcache_wb_valid     = dcache_wb_valid_r;

    assign icache_error        = icache_error_r;
    assign dcache_error        = dcache_error_r;
    assign dcache_error_is_store = dcache_error_is_store_r;
    assign bus_error_addr      = bus_error_addr_r;

    assign ptw_i_rdata = ptw_rdata_r;
    assign ptw_i_done  = ptw_done_r && ptw_is_inst_r;
    assign ptw_i_error = ptw_error_r && ptw_is_inst_r;
    assign ptw_d_rdata = ptw_rdata_r;
    assign ptw_d_done  = ptw_done_r && !ptw_is_inst_r;
    assign ptw_d_error = ptw_error_r && !ptw_is_inst_r;

    wire beat_done = HREADY && htrans_r[1];
    wire last_beat = (beat_cnt == 3'd7);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state                <= S_IDLE;
            haddr_r              <= 32'b0;
            htrans_r             <= `AHB_TRANS_IDLE;
            hwrite_r             <= 1'b0;
            hsize_r              <= `AHB_SIZE_WORD;
            hburst_r             <= `AHB_BURST_SINGLE;
            hprot_r              <= 4'b0011;
            hmastlock_r          <= 1'b0;
            hwdata_r             <= 32'b0;
            mmio_latch_wdata     <= 32'b0;
            mmio_is_ireq         <= 1'b0;
            ahb_inst_data_r      <= 32'b0;
            ahb_inst_valid_r     <= 1'b0;
            ahb_data_rdata_r     <= 32'b0;
            ahb_data_valid_r     <= 1'b0;
            beat_cnt             <= 3'd0;
            burst_base_addr      <= 32'b0;
            refill_shift_reg     <= 256'b0;
            wb_shift_reg         <= 256'b0;
            icache_refill_valid_r <= 1'b0;
            dcache_refill_valid_r <= 1'b0;
            dcache_wb_valid_r     <= 1'b0;
            icache_error_r        <= 1'b0;
            dcache_error_r        <= 1'b0;
            dcache_error_is_store_r <= 1'b0;
            bus_error_addr_r      <= 32'b0;
            ptw_rdata_r           <= 32'b0;
            ptw_done_r            <= 1'b0;
            ptw_error_r           <= 1'b0;
            ptw_is_inst_r         <= 1'b0;
            mmio_inst_served      <= 1'b0;
            mmio_data_served      <= 1'b0;
        end else begin
            ahb_inst_valid_r      <= 1'b0;
            ahb_data_valid_r      <= 1'b0;
            icache_refill_valid_r <= 1'b0;
            dcache_refill_valid_r <= 1'b0;
            dcache_wb_valid_r     <= 1'b0;
            icache_error_r        <= 1'b0;
            dcache_error_r        <= 1'b0;
            dcache_error_is_store_r <= 1'b0;
            ptw_done_r            <= 1'b0;
            ptw_error_r           <= 1'b0;
            if (!icache_mmio_req) mmio_inst_served <= 1'b0;
            if (!dcache_mmio_req) mmio_data_served <= 1'b0;

            case (state)
                S_IDLE: begin
                    htrans_r <= `AHB_TRANS_IDLE;
                    if (icache_mmio_req && !ahb_inst_valid_r && !mmio_inst_served) begin
                        state            <= S_MMIO_ADDR;
                        haddr_r          <= icache_mmio_addr;
                        htrans_r         <= `AHB_TRANS_NONSEQ;
                        hwrite_r         <= 1'b0;
                        hsize_r          <= `AHB_SIZE_WORD;
                        hburst_r         <= `AHB_BURST_SINGLE;
                        hprot_r          <= 4'b0011;
                        hmastlock_r      <= 1'b0;
                        mmio_latch_wdata <= 32'b0;
                        mmio_is_ireq     <= 1'b1;
                    end else if (dcache_mmio_req && !ahb_data_valid_r && !mmio_data_served) begin
                        state            <= S_MMIO_ADDR;
                        haddr_r          <= dcache_mmio_addr;
                        htrans_r         <= `AHB_TRANS_NONSEQ;
                        hwrite_r         <= dcache_mmio_hwrite;
                        hsize_r          <= dcache_mmio_hsize;
                        hburst_r         <= `AHB_BURST_SINGLE;
                        hprot_r          <= 4'b0011;
                        hmastlock_r      <= 1'b0;
                        mmio_latch_wdata <= dcache_mmio_wdata;
                        mmio_is_ireq     <= 1'b0;
                    end else if (ptw_i_req && !ptw_done_r) begin
                        state            <= S_PTW_ADDR;
                        haddr_r          <= ptw_i_addr;
                        htrans_r         <= `AHB_TRANS_NONSEQ;
                        hwrite_r         <= ptw_i_we;
                        hsize_r          <= `AHB_SIZE_WORD;
                        hburst_r         <= `AHB_BURST_SINGLE;
                        hprot_r          <= 4'b0011;
                        hmastlock_r      <= 1'b0;
                        mmio_latch_wdata <= ptw_i_wdata;
                        ptw_is_inst_r    <= 1'b1;
                    end else if (ptw_d_req && !ptw_done_r) begin
                        state            <= S_PTW_ADDR;
                        haddr_r          <= ptw_d_addr;
                        htrans_r         <= `AHB_TRANS_NONSEQ;
                        hwrite_r         <= ptw_d_we;
                        hsize_r          <= `AHB_SIZE_WORD;
                        hburst_r         <= `AHB_BURST_SINGLE;
                        hprot_r          <= 4'b0011;
                        hmastlock_r      <= 1'b0;
                        mmio_latch_wdata <= ptw_d_wdata;
                        ptw_is_inst_r    <= 1'b0;
                    end else if (dcache_wb_req && !dcache_wb_valid_r) begin
                        state            <= S_WB_ADDR;
                        haddr_r          <= dcache_wb_addr;
                        htrans_r         <= `AHB_TRANS_NONSEQ;
                        hwrite_r         <= 1'b1;
                        hsize_r          <= `AHB_SIZE_WORD;
                        hburst_r         <= `AHB_BURST_INCR8;
                        hprot_r          <= 4'b0011;
                        hmastlock_r      <= 1'b0;
                        burst_base_addr  <= dcache_wb_addr;
                        beat_cnt         <= 3'd0;
                        wb_shift_reg     <= dcache_wb_data;
                    end else if (icache_refill_req && !icache_refill_valid_r) begin
                        state            <= S_IREFILL_ADDR;
                        haddr_r          <= icache_refill_addr;
                        htrans_r         <= `AHB_TRANS_NONSEQ;
                        hwrite_r         <= 1'b0;
                        hsize_r          <= `AHB_SIZE_WORD;
                        hburst_r         <= `AHB_BURST_INCR8;
                        hprot_r          <= 4'b0011;
                        hmastlock_r      <= 1'b0;
                        burst_base_addr  <= icache_refill_addr;
                        beat_cnt         <= 3'd0;
                        refill_shift_reg <= 256'b0;
                    end else if (dcache_refill_req && !dcache_refill_valid_r) begin
                        state            <= S_DREFILL_ADDR;
                        haddr_r          <= dcache_refill_addr;
                        htrans_r         <= `AHB_TRANS_NONSEQ;
                        hwrite_r         <= 1'b0;
                        hsize_r          <= `AHB_SIZE_WORD;
                        hburst_r         <= `AHB_BURST_INCR8;
                        hprot_r          <= 4'b0011;
                        hmastlock_r      <= 1'b0;
                        burst_base_addr  <= dcache_refill_addr;
                        beat_cnt         <= 3'd0;
                        refill_shift_reg <= 256'b0;
                    end
                end

                S_MMIO_ADDR: begin
                    if (HREADY) begin
                        if (HRESP == `AHB_RESP_ERROR) begin
                            state     <= S_IDLE;
                            htrans_r  <= `AHB_TRANS_IDLE;
                            bus_error_addr_r <= haddr_r;
                            if (mmio_is_ireq) begin
                                icache_error_r   <= 1'b1;
                                ahb_inst_valid_r <= 1'b1;
                            end else begin
                                dcache_error_r        <= 1'b1;
                                dcache_error_is_store_r <= hwrite_r;
                                ahb_data_valid_r  <= 1'b1;
                            end
                        end else begin
                            state     <= S_MMIO_DATA;
                            htrans_r  <= `AHB_TRANS_IDLE;
                            hwdata_r  <= mmio_latch_wdata;
                        end
                    end
                end

                S_MMIO_DATA: begin
                    if (HREADY) begin
                        if (HRESP == `AHB_RESP_ERROR) begin
                            state     <= S_IDLE;
                            htrans_r  <= `AHB_TRANS_IDLE;
                            bus_error_addr_r <= haddr_r;
                            if (mmio_is_ireq) begin
                                icache_error_r   <= 1'b1;
                                ahb_inst_valid_r <= 1'b1;
                            end else begin
                                dcache_error_r        <= 1'b1;
                                dcache_error_is_store_r <= hwrite_r;
                                ahb_data_valid_r  <= 1'b1;
                            end
                        end else begin
                            state     <= S_IDLE;
                            htrans_r  <= `AHB_TRANS_IDLE;
                            if (mmio_is_ireq) begin
                                ahb_inst_data_r  <= HRDATA;
                                ahb_inst_valid_r <= 1'b1;
                                mmio_inst_served <= 1'b1;
                            end else begin
                                ahb_data_rdata_r <= HRDATA;
                                ahb_data_valid_r <= 1'b1;
                                mmio_data_served <= 1'b1;
                            end
                        end
                    end
                end

                S_IREFILL_ADDR: begin
                    if (HREADY) begin
                        state    <= S_IREFILL_DATA;
                        htrans_r <= `AHB_TRANS_SEQ;
                        haddr_r  <= burst_base_addr + 32'd4;
                    end
                end

                S_IREFILL_DATA: begin
                    if (beat_done) begin
                        if (HRESP == `AHB_RESP_ERROR) begin
                            state    <= S_IDLE;
                            htrans_r <= `AHB_TRANS_IDLE;
                            icache_error_r   <= 1'b1;
                            bus_error_addr_r <= burst_base_addr;
                        end else begin
                            refill_shift_reg[beat_cnt*32 +: 32] <= HRDATA;
                            if (last_beat) begin
                                state    <= S_IDLE;
                                htrans_r <= `AHB_TRANS_IDLE;
                                icache_refill_valid_r <= 1'b1;
                            end else begin
                                beat_cnt <= beat_cnt + 3'd1;
                                haddr_r  <= burst_base_addr + ({29'b0, beat_cnt + 3'd1, 2'b0}) + 32'd4;
                                htrans_r <= `AHB_TRANS_SEQ;
                            end
                        end
                    end
                end

                S_DREFILL_ADDR: begin
                    if (HREADY) begin
                        state    <= S_DREFILL_DATA;
                        htrans_r <= `AHB_TRANS_SEQ;
                        haddr_r  <= burst_base_addr + 32'd4;
                    end
                end

                S_DREFILL_DATA: begin
                    if (beat_done) begin
                        if (HRESP == `AHB_RESP_ERROR) begin
                            state    <= S_IDLE;
                            htrans_r <= `AHB_TRANS_IDLE;
                            dcache_error_r   <= 1'b1;
                            dcache_error_is_store_r <= 1'b0;
                            bus_error_addr_r <= burst_base_addr;
                        end else begin
                            refill_shift_reg[beat_cnt*32 +: 32] <= HRDATA;
                            if (last_beat) begin
                                state    <= S_IDLE;
                                htrans_r <= `AHB_TRANS_IDLE;
                                dcache_refill_valid_r <= 1'b1;
                            end else begin
                                beat_cnt <= beat_cnt + 3'd1;
                                haddr_r  <= burst_base_addr + ({29'b0, beat_cnt + 3'd1, 2'b0}) + 32'd4;
                                htrans_r <= `AHB_TRANS_SEQ;
                            end
                        end
                    end
                end

                S_WB_ADDR: begin
                    if (HREADY) begin
                        state    <= S_WB_DATA;
                        htrans_r <= `AHB_TRANS_SEQ;
                        haddr_r  <= burst_base_addr + 32'd4;
                        hwdata_r <= wb_shift_reg[31:0];
                    end
                end

                S_WB_DATA: begin
                    if (beat_done) begin
                        if (HRESP == `AHB_RESP_ERROR) begin
                            state    <= S_IDLE;
                            htrans_r <= `AHB_TRANS_IDLE;
                            dcache_error_r   <= 1'b1;
                            dcache_error_is_store_r <= 1'b1;
                            bus_error_addr_r <= burst_base_addr;
                        end else begin
                            if (last_beat) begin
                                state    <= S_IDLE;
                                htrans_r <= `AHB_TRANS_IDLE;
                                dcache_wb_valid_r <= 1'b1;
                            end else begin
                                beat_cnt    <= beat_cnt + 3'd1;
                                wb_shift_reg <= wb_shift_reg >> 32;
                                hwdata_r    <= wb_shift_reg[63:32];
                                haddr_r     <= burst_base_addr + ({29'b0, beat_cnt + 3'd1, 2'b0}) + 32'd4;
                                htrans_r    <= `AHB_TRANS_SEQ;
                            end
                        end
                    end
                end

                S_PTW_ADDR: begin
                    if (HREADY) begin
                        state    <= S_PTW_DATA;
                        htrans_r <= `AHB_TRANS_IDLE;
                        hwdata_r <= mmio_latch_wdata;
                    end
                end

                S_PTW_DATA: begin
                    if (HREADY) begin
                        if (HRESP == `AHB_RESP_ERROR) begin
                            state       <= S_IDLE;
                            htrans_r    <= `AHB_TRANS_IDLE;
                            ptw_rdata_r <= 32'b0;
                            ptw_done_r  <= 1'b0;
                            ptw_error_r <= 1'b1;
                        end else begin
                            state       <= S_IDLE;
                            htrans_r    <= `AHB_TRANS_IDLE;
                            ptw_rdata_r <= HRDATA;
                            ptw_done_r  <= 1'b1;
                            ptw_error_r <= 1'b0;
                        end
                    end
                end

                default: begin
                    state    <= S_IDLE;
                    htrans_r <= `AHB_TRANS_IDLE;
                end
            endcase
        end
    end

    assign HADDR     = haddr_r;
    assign HTRANS    = htrans_r;
    assign HWRITE    = hwrite_r;
    assign HSIZE     = hsize_r;
    assign HBURST    = hburst_r;
    assign HPROT     = hprot_r;
    assign HMASTLOCK = hmastlock_r;
    assign HWDATA    = hwdata_r;

endmodule
