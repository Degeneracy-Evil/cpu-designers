`include "ahb_def.vh"
`timescale 1ns / 1ps

module ahb_periph_bus #(
    parameter ADDR_WIDTH  = `AHB_ADDR_WIDTH,
    parameter DATA_WIDTH  = `AHB_DATA_WIDTH,
    parameter SLAVE_NUM   = 2,
    parameter MEM_DEPTH   = 262144,
    parameter WAIT_STATES = 0,
    parameter GPIO_NUM    = 16,
    parameter UART_FREQ   = 25
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

    output wire                    o_timer_irq,
    inout  wire [GPIO_NUM-1:0]     io_gpioPin,
    input  wire                    i_uart_rx,
    output wire                    o_uart_tx,
    output wire                    o_spiMosi,
    input  wire                    i_spiMiso,
    output wire                    o_spiSs,
    output wire                    o_spiClk
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

    wire [DATA_WIDTH-1:0]  slave_HRDATA   [0:SLAVE_NUM-1];
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

    ahb_sram_slave #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .MEM_DEPTH   (MEM_DEPTH),
        .WAIT_STATES (WAIT_STATES)
    ) u_ahb_sram_slave (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HSEL      (slave_HSELx[0]),
        .HADDR     (bus_HADDR),
        .HTRANS    (bus_HTRANS),
        .HWRITE    (bus_HWRITE),
        .HSIZE     (bus_HSIZE),
        .HBURST    ({1'b0, bus_HBURST}),
        .HPROT     (bus_HPROT),
        .HWDATA    (bus_HWDATA),
        .HREADY    (bus_HREADY),
        .HREADYOUT (slave_HREADYOUT[0]),
        .HRESP     (slave_HRESP[0]),
        .HRDATA    (slave_HRDATA[0])
    );

    wire [ADDR_WIDTH-1:0]  bridge_PADDR;
    wire [2:0]             bridge_PPROT;
    wire                   bridge_PSEL;
    wire                   bridge_PENABLE;
    wire                   bridge_PWRITE;
    wire [DATA_WIDTH-1:0]  bridge_PWDATA;
    wire [DATA_WIDTH/8-1:0] bridge_PSTRB;

    reg                    bridge_PREADY;
    reg  [DATA_WIDTH-1:0]  bridge_PRDATA;
    reg                    bridge_PSLVERR;

    wire [3:0]             apb_slave_PSELx;
    wire [3:0]             apb_slave_PREADY;
    wire [DATA_WIDTH-1:0]  apb_slave0_PRDATA;
    wire [DATA_WIDTH-1:0]  apb_slave1_PRDATA;
    wire [DATA_WIDTH-1:0]  apb_slave2_PRDATA;
    wire [DATA_WIDTH-1:0]  apb_slave3_PRDATA;
    wire [3:0]             apb_slave_PSLVERR;

    wire [DATA_WIDTH-1:0]  bridge_HRDATA;

    ahb_lite_to_apb #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_ahb_lite_to_apb (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HADDR     (bus_HADDR),
        .HTRANS    (bus_HTRANS),
        .HWRITE    (bus_HWRITE),
        .HSIZE     (bus_HSIZE),
        .HBURST    (bus_HBURST),
        .HPROT     (bus_HPROT),
        .HWDATA    (bus_HWDATA),
        .HSEL      (slave_HSELx[1]),
        .HREADY    (bus_HREADY),
        .HREADYOUT (slave_HREADYOUT[1]),
        .HRESP     (slave_HRESP[1]),
        .HRDATA    (bridge_HRDATA),
        .PADDR     (bridge_PADDR),
        .PPROT     (bridge_PPROT),
        .PSEL      (bridge_PSEL),
        .PENABLE   (bridge_PENABLE),
        .PWRITE    (bridge_PWRITE),
        .PWDATA    (bridge_PWDATA),
        .PSTRB     (bridge_PSTRB),
        .PREADY    (bridge_PREADY),
        .PRDATA    (bridge_PRDATA),
        .PSLVERR   (bridge_PSLVERR)
    );

    apb_decoder #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .SLAVE_NUM  (4)
    ) u_apb_decoder (
        .PADDR (bridge_PADDR),
        .PSELx (apb_slave_PSELx)
    );

    apb_perips #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .GPIO_NUM   (GPIO_NUM),
        .UART_FREQ  (UART_FREQ)
    ) u_apb_perips (
        .PCLK           (HCLK),
        .PRESETn        (HRESETn),
        .PADDR          (bridge_PADDR),
        .PPROT          (bridge_PPROT),
        .PSELx          (apb_slave_PSELx),
        .PENABLE        (bridge_PENABLE),
        .PWRITE         (bridge_PWRITE),
        .PWDATA         (bridge_PWDATA),
        .PSTRB          (bridge_PSTRB),
        .slave_PREADY   (apb_slave_PREADY),
        .slave0_PRDATA  (apb_slave0_PRDATA),
        .slave1_PRDATA  (apb_slave1_PRDATA),
        .slave2_PRDATA  (apb_slave2_PRDATA),
        .slave3_PRDATA  (apb_slave3_PRDATA),
        .slave_PSLVERR  (apb_slave_PSLVERR),
        .o_gpioCtrl     (),
        .o_gpioData     (),
        .io_gpioPin     (io_gpioPin),
        .o_timer_irq    (o_timer_irq),
        .i_uart_rx      (i_uart_rx),
        .o_uart_tx      (o_uart_tx),
        .o_spiMosi      (o_spiMosi),
        .i_spiMiso      (i_spiMiso),
        .o_spiSs        (o_spiSs),
        .o_spiClk       (o_spiClk)
    );

    always @(*) begin
        bridge_PREADY  = 1'b1;
        bridge_PSLVERR = 1'b0;
        if (apb_slave_PSELx[0] & bridge_PSEL) begin
            bridge_PREADY  = apb_slave_PREADY[0];
            bridge_PSLVERR = apb_slave_PSLVERR[0];
        end else if (apb_slave_PSELx[1] & bridge_PSEL) begin
            bridge_PREADY  = apb_slave_PREADY[1];
            bridge_PSLVERR = apb_slave_PSLVERR[1];
        end else if (apb_slave_PSELx[2] & bridge_PSEL) begin
            bridge_PREADY  = apb_slave_PREADY[2];
            bridge_PSLVERR = apb_slave_PSLVERR[2];
        end else if (apb_slave_PSELx[3] & bridge_PSEL) begin
            bridge_PREADY  = apb_slave_PREADY[3];
            bridge_PSLVERR = apb_slave_PSLVERR[3];
        end
    end

    always @(*) begin
        bridge_PRDATA = {DATA_WIDTH{1'b0}};
        if (apb_slave_PSELx[0] & bridge_PSEL) begin
            bridge_PRDATA = apb_slave0_PRDATA;
        end else if (apb_slave_PSELx[1] & bridge_PSEL) begin
            bridge_PRDATA = apb_slave1_PRDATA;
        end else if (apb_slave_PSELx[2] & bridge_PSEL) begin
            bridge_PRDATA = apb_slave2_PRDATA;
        end else if (apb_slave_PSELx[3] & bridge_PSEL) begin
            bridge_PRDATA = apb_slave3_PRDATA;
        end
    end

    assign slave_HRDATA[1]    = bridge_HRDATA;

endmodule
