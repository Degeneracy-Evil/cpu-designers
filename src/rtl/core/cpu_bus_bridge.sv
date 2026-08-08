`timescale 1ns / 1ps
`include "axi4_def.svh"

module cpu_bus_bridge(
    input         clk,
    input         resetn,

    input         icache_mmio_req,
    output        icache_mmio_accept,
    input  [31:0] icache_mmio_addr,

    input         dcache_mmio_req,
    output        dcache_mmio_accept,
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
    output        icache_refill_done,
    output        icache_refill_error,

    input         dcache_refill_req,
    input  [31:0] dcache_refill_addr,
    output [255:0] dcache_refill_data,
    output        dcache_refill_valid,
    output        dcache_refill_done,
    output        dcache_refill_error,

    input         ptw_req,
    input  [31:0] ptw_addr,
    input         ptw_we,
    input  [31:0] ptw_wdata,
    output [31:0] ptw_rdata,
    output        ptw_done,
    output        ptw_error,

    output logic [3:0]  awid,
    output logic [31:0] awaddr,
    output logic [7:0]  awlen,
    output logic [2:0]  awsize,
    output logic [1:0]  awburst,
    output logic        awlock,
    output logic [3:0]  awcache,
    output logic [2:0]  awprot,
    output logic [3:0]  awqos,
    output logic [3:0]  awregion,
    output logic        awvalid,
    input  logic        awready,

    output logic [31:0] wdata,
    output logic [3:0]  wstrb,
    output logic        wlast,
    output logic        wvalid,
    input  logic        wready,

    input  logic [1:0]  bresp,
    input  logic        bvalid,
    output logic        bready,

    output logic [3:0]  arid,
    output logic [31:0] araddr,
    output logic [7:0]  arlen,
    output logic [2:0]  arsize,
    output logic [1:0]  arburst,
    output logic        arlock,
    output logic [3:0]  arcache,
    output logic [2:0]  arprot,
    output logic [3:0]  arqos,
    output logic [3:0]  arregion,
    output logic        arvalid,
    input  logic        arready,

    input  logic [31:0] rdata,
    input  logic [1:0]  rresp,
    input  logic        rlast,
    input  logic        rvalid,
    output logic        rready,

    output        icache_error,
    output        dcache_error,
    output        dcache_error_is_store,
    output [31:0] bus_error_addr
);
    localparam [2:0] CLIENT_I_MMIO   = 3'd0;
    localparam [2:0] CLIENT_D_MMIO   = 3'd1;
    localparam [2:0] CLIENT_I_REFILL = 3'd2;
    localparam [2:0] CLIENT_D_REFILL = 3'd3;
    localparam [2:0] CLIENT_PTW      = 3'd4;

    localparam [2:0] S_IDLE       = 3'd0;
    localparam [2:0] S_READ_ADDR  = 3'd1;
    localparam [2:0] S_READ_DATA  = 3'd2;
    localparam [2:0] S_WRITE_SEND = 3'd3;
    localparam [2:0] S_WRITE_RESP = 3'd4;

    reg [2:0] state;
    reg [2:0] client_r;
    reg [31:0] addr_r;
    reg [2:0]  size_r;
    reg [7:0]  len_r;
    reg [31:0] write_data_r;

    reg [2:0] beat_r;
    reg [255:0] read_line_r;
    reg read_error_r;
    reg aw_done_r;
    reg w_done_r;

    // Level-style cache/PTW requests are blocked after completion until the
    // source observes its response and drops req. This is the compatibility
    // adapter around the bridge's single internal req/response transaction.
    reg block_i_refill_r;
    reg block_d_refill_r;
    reg block_ptw_r;

    reg [31:0] inst_data_r;
    reg inst_valid_r;
    reg [31:0] data_rdata_r;
    reg data_valid_r;
    reg i_mmio_accept_r;
    reg d_mmio_accept_r;
    reg [255:0] i_refill_data_r;
    reg i_refill_valid_r;
    reg i_refill_done_r;
    reg i_refill_error_r;
    reg [255:0] d_refill_data_r;
    reg d_refill_valid_r;
    reg d_refill_done_r;
    reg d_refill_error_r;
    reg [31:0] ptw_rdata_r;
    reg ptw_done_r;
    reg ptw_error_r;
    reg icache_error_r;
    reg dcache_error_r;
    reg dcache_error_is_store_r;
    reg [31:0] bus_error_addr_r;

    wire r_error = (rresp == `AXI_RESP_SLVERR) || (rresp == `AXI_RESP_DECERR);
    wire b_error = (bresp == `AXI_RESP_SLVERR) || (bresp == `AXI_RESP_DECERR);
    wire [255:0] read_line_with_current =
        (read_line_r & ~({224'b0, 32'hFFFF_FFFF} << (beat_r * 32))) |
        ({224'b0, rdata} << (beat_r * 32));

    wire [1:0] byte_lane = addr_r[1:0];
    wire [3:0] single_wstrb =
        (size_r == `AXI_SIZE_1B) ? (4'b0001 << byte_lane) :
        (size_r == `AXI_SIZE_2B) ? (4'b0011 << byte_lane) : 4'b1111;
    wire [31:0] single_wdata =
        (size_r == `AXI_SIZE_1B) ? (write_data_r << (byte_lane * 8)) :
        write_data_r;

    assign ahb_inst_data = inst_data_r;
    assign ahb_inst_valid = inst_valid_r;
    assign ahb_data_rdata = data_rdata_r;
    assign ahb_data_valid = data_valid_r;
    assign icache_mmio_accept = i_mmio_accept_r;
    assign dcache_mmio_accept = d_mmio_accept_r;
    assign icache_refill_data = i_refill_data_r;
    assign icache_refill_valid = i_refill_valid_r;
    assign icache_refill_done = i_refill_done_r;
    assign icache_refill_error = i_refill_error_r;
    assign dcache_refill_data = d_refill_data_r;
    assign dcache_refill_valid = d_refill_valid_r;
    assign dcache_refill_done = d_refill_done_r;
    assign dcache_refill_error = d_refill_error_r;
    assign ptw_rdata = ptw_rdata_r;
    assign ptw_done = ptw_done_r;
    assign ptw_error = ptw_error_r;
    assign icache_error = icache_error_r;
    assign dcache_error = dcache_error_r;
    assign dcache_error_is_store = dcache_error_is_store_r;
    assign bus_error_addr = bus_error_addr_r;

    always_comb begin
        awid = 4'b0;
        awaddr = addr_r;
        awlen = len_r;
        awsize = size_r;
        awburst = `AXI_BURST_INCR;
        awlock = `AXI_LOCK_NORMAL;
        awcache = `AXI_CACHE_DEV_NONBUF;
        awprot = `AXI_PROT_DATA_PRIV_SECURE;
        awqos = 4'b0;
        awregion = 4'b0;
        awvalid = (state == S_WRITE_SEND) && !aw_done_r;

        wdata = single_wdata;
        wstrb = single_wstrb;
        wlast = (beat_r == len_r[2:0]);
        wvalid = (state == S_WRITE_SEND) && !w_done_r;
        bready = (state == S_WRITE_RESP);

        arid = 4'b0;
        araddr = addr_r;
        arlen = len_r;
        arsize = size_r;
        arburst = `AXI_BURST_INCR;
        arlock = `AXI_LOCK_NORMAL;
        arcache = ((client_r == CLIENT_I_REFILL) || (client_r == CLIENT_D_REFILL)) ?
                  `AXI_CACHE_NORM_BUF : `AXI_CACHE_DEV_NONBUF;
        arprot = ((client_r == CLIENT_I_MMIO) || (client_r == CLIENT_I_REFILL)) ?
                 `AXI_PROT_INST_PRIV_SECURE : `AXI_PROT_DATA_PRIV_SECURE;
        arqos = 4'b0;
        arregion = 4'b0;
        arvalid = (state == S_READ_ADDR);
        rready = (state == S_READ_DATA);
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= S_IDLE;
            client_r <= CLIENT_I_MMIO;
            addr_r <= 32'b0;
            size_r <= `AXI_SIZE_4B;
            len_r <= 8'b0;
            write_data_r <= 32'b0;
            beat_r <= 3'b0;
            read_line_r <= 256'b0;
            read_error_r <= 1'b0;
            aw_done_r <= 1'b0;
            w_done_r <= 1'b0;
            block_i_refill_r <= 1'b0;
            block_d_refill_r <= 1'b0;
            block_ptw_r <= 1'b0;
            inst_data_r <= 32'b0;
            inst_valid_r <= 1'b0;
            data_rdata_r <= 32'b0;
            data_valid_r <= 1'b0;
            i_mmio_accept_r <= 1'b0;
            d_mmio_accept_r <= 1'b0;
            i_refill_data_r <= 256'b0;
            i_refill_valid_r <= 1'b0;
            i_refill_done_r <= 1'b0;
            i_refill_error_r <= 1'b0;
            d_refill_data_r <= 256'b0;
            d_refill_valid_r <= 1'b0;
            d_refill_done_r <= 1'b0;
            d_refill_error_r <= 1'b0;
            ptw_rdata_r <= 32'b0;
            ptw_done_r <= 1'b0;
            ptw_error_r <= 1'b0;
            icache_error_r <= 1'b0;
            dcache_error_r <= 1'b0;
            dcache_error_is_store_r <= 1'b0;
            bus_error_addr_r <= 32'b0;
        end else begin
            inst_valid_r <= 1'b0;
            data_valid_r <= 1'b0;
            i_mmio_accept_r <= 1'b0;
            d_mmio_accept_r <= 1'b0;
            i_refill_valid_r <= 1'b0;
            i_refill_done_r <= 1'b0;
            i_refill_error_r <= 1'b0;
            d_refill_valid_r <= 1'b0;
            d_refill_done_r <= 1'b0;
            d_refill_error_r <= 1'b0;
            ptw_done_r <= 1'b0;
            ptw_error_r <= 1'b0;
            icache_error_r <= 1'b0;
            dcache_error_r <= 1'b0;
            dcache_error_is_store_r <= 1'b0;

            if (!icache_refill_req) block_i_refill_r <= 1'b0;
            if (!dcache_refill_req) block_d_refill_r <= 1'b0;
            if (!ptw_req) block_ptw_r <= 1'b0;

            case (state)
                S_IDLE: begin
                    beat_r <= 3'b0;
                    read_line_r <= 256'b0;
                    read_error_r <= 1'b0;
                    aw_done_r <= 1'b0;
                    w_done_r <= 1'b0;

                    if (icache_mmio_req) begin
                        client_r <= CLIENT_I_MMIO;
                        addr_r <= icache_mmio_addr;
                        size_r <= `AXI_SIZE_4B;
                        len_r <= 8'd0;
                        i_mmio_accept_r <= 1'b1;
                        state <= S_READ_ADDR;
                    end else if (dcache_mmio_req) begin
                        client_r <= CLIENT_D_MMIO;
                        addr_r <= dcache_mmio_addr;
                        size_r <= dcache_mmio_hsize;
                        len_r <= 8'd0;
                        write_data_r <= dcache_mmio_wdata;
                        d_mmio_accept_r <= 1'b1;
                        state <= dcache_mmio_hwrite ? S_WRITE_SEND : S_READ_ADDR;
                    end else if (ptw_req && !block_ptw_r) begin
                        client_r <= CLIENT_PTW;
                        addr_r <= ptw_addr;
                        size_r <= `AXI_SIZE_4B;
                        len_r <= 8'd0;
                        write_data_r <= ptw_wdata;
                        state <= ptw_we ? S_WRITE_SEND : S_READ_ADDR;
                    end else if (icache_refill_req && !block_i_refill_r) begin
                        client_r <= CLIENT_I_REFILL;
                        addr_r <= icache_refill_addr;
                        size_r <= `AXI_SIZE_4B;
                        len_r <= 8'd7;
                        state <= S_READ_ADDR;
                    end else if (dcache_refill_req && !block_d_refill_r) begin
                        client_r <= CLIENT_D_REFILL;
                        addr_r <= dcache_refill_addr;
                        size_r <= `AXI_SIZE_4B;
                        len_r <= 8'd7;
                        state <= S_READ_ADDR;
                    end
                end

                S_READ_ADDR: begin
                    if (arvalid && arready)
                        state <= S_READ_DATA;
                end

                S_READ_DATA: begin
                    if (rvalid && rready) begin
                        read_line_r[beat_r*32 +: 32] <= rdata;
                        if (r_error)
                            read_error_r <= 1'b1;
                        if (rlast) begin
                            state <= S_IDLE;
                            bus_error_addr_r <= addr_r;
                            case (client_r)
                                CLIENT_I_MMIO: begin
                                    inst_data_r <= rdata;
                                    inst_valid_r <= 1'b1;
                                    if (read_error_r || r_error)
                                        icache_error_r <= 1'b1;
                                end
                                CLIENT_D_MMIO: begin
                                    data_rdata_r <= rdata;
                                    data_valid_r <= 1'b1;
                                    if (read_error_r || r_error) begin
                                        dcache_error_r <= 1'b1;
                                        dcache_error_is_store_r <= 1'b0;
                                    end
                                end
                                CLIENT_I_REFILL: begin
                                    block_i_refill_r <= 1'b1;
                                    i_refill_done_r <= 1'b1;
                                    i_refill_error_r <= read_error_r || r_error;
                                    if (read_error_r || r_error)
                                        icache_error_r <= 1'b1;
                                    else begin
                                        i_refill_data_r <= read_line_with_current;
                                        i_refill_valid_r <= 1'b1;
                                    end
                                end
                                CLIENT_D_REFILL: begin
                                    block_d_refill_r <= 1'b1;
                                    d_refill_done_r <= 1'b1;
                                    if (read_error_r || r_error) begin
                                        d_refill_error_r <= 1'b1;
                                        dcache_error_r <= 1'b1;
                                        dcache_error_is_store_r <= 1'b0;
                                    end else begin
                                        d_refill_data_r <= read_line_with_current;
                                        d_refill_valid_r <= 1'b1;
                                    end
                                end
                                default: begin
                                    block_ptw_r <= 1'b1;
                                    ptw_rdata_r <= rdata;
                                    ptw_done_r <= 1'b1;
                                    ptw_error_r <= read_error_r || r_error;
                                end
                            endcase
                        end else begin
                            beat_r <= beat_r + 3'd1;
                        end
                    end
                end

                S_WRITE_SEND: begin
                    if (awvalid && awready)
                        aw_done_r <= 1'b1;
                    if (wvalid && wready) begin
                        if (wlast)
                            w_done_r <= 1'b1;
                        else
                            beat_r <= beat_r + 3'd1;
                    end
                    if ((aw_done_r || (awvalid && awready)) &&
                        (w_done_r || (wvalid && wready && wlast)))
                        state <= S_WRITE_RESP;
                end

                S_WRITE_RESP: begin
                    if (bvalid && bready) begin
                        state <= S_IDLE;
                        bus_error_addr_r <= addr_r;
                        case (client_r)
                            CLIENT_D_MMIO: begin
                                data_valid_r <= 1'b1;
                                if (b_error) begin
                                    dcache_error_r <= 1'b1;
                                    dcache_error_is_store_r <= 1'b1;
                                end
                            end
                            default: begin
                                block_ptw_r <= 1'b1;
                                ptw_done_r <= 1'b1;
                                ptw_error_r <= b_error;
                            end
                        endcase
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
