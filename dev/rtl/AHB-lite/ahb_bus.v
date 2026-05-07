// DEPRECATED: This module uses the old 4-slave AHB bus structure with default_slave.
// The current system uses ahb_periph_bus with SLAVE_NUM=2 (HADDR[31] decode).
// Retained for reference only; do not instantiate in new designs.
`include "ahb_def.vh"
`timescale 1ns / 1ps

module ahb_bus #(
    parameter ADDR_WIDTH  = `AHB_ADDR_WIDTH,
    parameter DATA_WIDTH  = `AHB_DATA_WIDTH,
    parameter SLAVE_NUM   = 4,
    parameter MEM_DEPTH   = 262144,
    parameter WAIT_STATES = 0
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
    output wire  [DATA_WIDTH-1:0]  resp_rdata
);

    wire [ADDR_WIDTH-1:0]  bus_HADDR;
    wire [1:0]             bus_HTRANS;
    wire                   bus_HWRITE;
    wire [2:0]             bus_HSIZE;
    wire [2:0]             bus_HBURST;
    wire [3:0]             bus_HPROT;
    wire                   bus_HMASTLOCK;
    wire [DATA_WIDTH-1:0]  bus_HWDATA;

    wire [DATA_WIDTH-1:0]  bus_HRDATA;
    wire                   bus_HREADY;
    wire                   bus_HRESP;

    wire [SLAVE_NUM-1:0]   slave_HSELx;

    wire [DATA_WIDTH*SLAVE_NUM-1:0] slave_HRDATA;
    wire [SLAVE_NUM-1:0]   slave_HREADYOUT;
    wire [SLAVE_NUM-1:0]   slave_HRESP;

    ahb_master #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_ahb_master (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .req_valid (req_valid),
        .req_write (req_write),
        .req_addr  (req_addr),
        .req_wdata (req_wdata),
        .req_size  (req_size),
        .req_burst (req_burst),
        .req_prot  (req_prot),
        .req_lock  (req_lock),
        .req_ready (req_ready),
        .resp_valid(resp_valid),
        .resp_error(resp_error),
        .resp_rdata(resp_rdata),
        .HADDR     (bus_HADDR),
        .HTRANS    (bus_HTRANS),
        .HWRITE    (bus_HWRITE),
        .HSIZE     (bus_HSIZE),
        .HBURST    (bus_HBURST),
        .HPROT     (bus_HPROT),
        .HMASTLOCK (bus_HMASTLOCK),
        .HWDATA    (bus_HWDATA),
        .HREADY    (bus_HREADY),
        .HRESP     (bus_HRESP),
        .HRDATA    (bus_HRDATA)
    );

    ahb_decoder #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .SLAVE_NUM  (SLAVE_NUM)
    ) u_ahb_decoder (
        .HADDR  (bus_HADDR),
        .HREADY (bus_HREADY),
        .HSELx  (slave_HSELx)
    );

    ahb_mux #(
        .DATA_WIDTH (DATA_WIDTH),
        .SLAVE_NUM  (SLAVE_NUM)
    ) u_ahb_mux (
        .HSELx          (slave_HSELx),
        .slave_HRDATA   (slave_HRDATA),
        .slave_HREADYOUT(slave_HREADYOUT),
        .slave_HRESP    (slave_HRESP),
        .HRDATA         (bus_HRDATA),
        .HREADY         (bus_HREADY),
        .HRESP          (bus_HRESP)
    );

    genvar g;
    generate
        for (g = 0; g < SLAVE_NUM; g = g + 1) begin : gen_hrdata
            wire [DATA_WIDTH-1:0] hrdata;
            assign slave_HRDATA[g*DATA_WIDTH +: DATA_WIDTH] = hrdata;
        end
    endgenerate

    generate
        for (g = 0; g < SLAVE_NUM - 1; g = g + 1) begin : gen_sram_slave
            ahb_sram_slave #(
                .ADDR_WIDTH  (ADDR_WIDTH),
                .DATA_WIDTH  (DATA_WIDTH),
                .MEM_DEPTH   (MEM_DEPTH),
                .WAIT_STATES (WAIT_STATES)
            ) u_ahb_sram_slave (
                .HCLK      (HCLK),
                .HRESETn   (HRESETn),
                .HSEL      (slave_HSELx[g]),
                .HADDR     (bus_HADDR),
                .HTRANS    (bus_HTRANS),
                .HWRITE    (bus_HWRITE),
                .HSIZE     (bus_HSIZE),
                .HBURST    ({1'b0, bus_HBURST}),
                .HPROT     (bus_HPROT),
                .HWDATA    (bus_HWDATA),
                .HREADY    (bus_HREADY),
                .HREADYOUT (slave_HREADYOUT[g]),
                .HRESP     (slave_HRESP[g]),
                .HRDATA    (gen_hrdata[g].hrdata)
            );
        end
    endgenerate

    ahb_default_slave #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_ahb_default_slave (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HSEL      (slave_HSELx[SLAVE_NUM-1]),
        .HTRANS    (bus_HTRANS),
        .HREADY    (bus_HREADY),
        .HREADYOUT (slave_HREADYOUT[SLAVE_NUM-1]),
        .HRESP     (slave_HRESP[SLAVE_NUM-1]),
        .HRDATA    (gen_hrdata[SLAVE_NUM-1].hrdata)
    );

endmodule
