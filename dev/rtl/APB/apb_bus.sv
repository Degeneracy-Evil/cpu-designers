`include "apb_def.svh"
`timescale 1ns / 1ps

module apb_bus #(
    parameter ADDR_WIDTH  = `APB_ADDR_WIDTH,
    parameter DATA_WIDTH  = `APB_DATA_WIDTH,
    parameter STRB_WIDTH  = `APB_STRB_WIDTH,
    parameter PROT_WIDTH  = `APB_PROT_WIDTH,
    parameter SLAVE_NUM   = 4,
    parameter REG_NUM     = 4
)(
    input  wire                  PCLK,
    input  wire                  PRESETn,

    input  wire                  req_valid,
    input  wire                  req_write,
    input  wire  [ADDR_WIDTH-1:0] req_addr,
    input  wire  [DATA_WIDTH-1:0] req_wdata,
    input  wire  [STRB_WIDTH-1:0] req_strb,
    input  wire  [PROT_WIDTH-1:0] req_prot,

    output wire                  req_ready,
    output wire                  resp_valid,
    output wire                  resp_error,
    output wire  [DATA_WIDTH-1:0] resp_rdata
);

    wire [ADDR_WIDTH-1:0] bus_PADDR;
    wire [PROT_WIDTH-1:0] bus_PPROT;
    wire                  bus_PSEL;
    wire                  bus_PENABLE;
    wire                  bus_PWRITE;
    wire [DATA_WIDTH-1:0] bus_PWDATA;
    wire [STRB_WIDTH-1:0] bus_PSTRB;

    wire [SLAVE_NUM-1:0]  slave_PSELx;

    wire [SLAVE_NUM-1:0]  slave_PREADY;
    wire [DATA_WIDTH-1:0] slave_PRDATA [0:SLAVE_NUM-1];
    wire [SLAVE_NUM-1:0]  slave_PSLVERR;

    reg  bus_PREADY;
    reg  [DATA_WIDTH-1:0] bus_PRDATA;
    reg  bus_PSLVERR;

    apb_master #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .STRB_WIDTH (STRB_WIDTH),
        .PROT_WIDTH (PROT_WIDTH)
    ) u_apb_master (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),
        .PADDR     (bus_PADDR),
        .PPROT     (bus_PPROT),
        .PSEL      (bus_PSEL),
        .PENABLE   (bus_PENABLE),
        .PWRITE    (bus_PWRITE),
        .PWDATA    (bus_PWDATA),
        .PSTRB     (bus_PSTRB),
        .PREADY    (bus_PREADY),
        .PRDATA    (bus_PRDATA),
        .PSLVERR   (bus_PSLVERR),
        .req_valid (req_valid),
        .req_write (req_write),
        .req_addr  (req_addr),
        .req_wdata (req_wdata),
        .req_strb  (req_strb),
        .req_prot  (req_prot),
        .req_ready (req_ready),
        .resp_valid(resp_valid),
        .resp_error(resp_error),
        .resp_rdata(resp_rdata)
    );

    apb_decoder #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .SLAVE_NUM  (SLAVE_NUM)
    ) u_apb_decoder (
        .PADDR (bus_PADDR),
        .PSELx (slave_PSELx)
    );

    integer j;
    always @(*) begin
        bus_PREADY  = 1'b1;
        bus_PSLVERR = 1'b0;
        for (j = 0; j < SLAVE_NUM; j = j + 1) begin
            if (slave_PSELx[j] & bus_PSEL) begin
                bus_PREADY  = slave_PREADY[j];
                bus_PSLVERR = slave_PSLVERR[j];
            end
        end
    end

    genvar g;
    generate
        for (g = 0; g < SLAVE_NUM; g = g + 1) begin : gen_slave
            apb_slave #(
                .ADDR_WIDTH (ADDR_WIDTH),
                .DATA_WIDTH (DATA_WIDTH),
                .STRB_WIDTH (STRB_WIDTH),
                .PROT_WIDTH (PROT_WIDTH),
                .REG_NUM    (REG_NUM)
            ) u_apb_slave (
                .PCLK    (PCLK),
                .PRESETn (PRESETn),
                .PADDR   (bus_PADDR),
                .PPROT   (bus_PPROT),
                .PSEL    (slave_PSELx[g] & bus_PSEL),
                .PENABLE (bus_PENABLE),
                .PWRITE  (bus_PWRITE),
                .PWDATA  (bus_PWDATA),
                .PSTRB   (bus_PSTRB),
                .PREADY  (slave_PREADY[g]),
                .PRDATA  (slave_PRDATA[g]),
                .PSLVERR (slave_PSLVERR[g])
            );
        end
    endgenerate

    integer k;
    always @(*) begin
        bus_PRDATA = {DATA_WIDTH{1'b0}};
        for (k = 0; k < SLAVE_NUM; k = k + 1) begin
            if (slave_PSELx[k] & bus_PSEL) begin
                bus_PRDATA = slave_PRDATA[k];
            end
        end
    end

endmodule
