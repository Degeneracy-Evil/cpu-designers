`timescale 1ns / 1ps
`include "ahb_def.svh"

module ahb_lite_bus #(
    parameter ADDR_WIDTH  = `AHB_ADDR_WIDTH,
    parameter DATA_WIDTH  = `AHB_DATA_WIDTH,
    parameter SLAVE_NUM   = 4,
    parameter MEM_DEPTH   = 8192,
    parameter WAIT_STATES = 0,
    parameter GPIO_NUM    = 16,
    parameter UART_FREQ   = 100
)(
    input  wire                    HCLK,
    input  wire                    HRESETn,

    input  wire  [ADDR_WIDTH-1:0]  HADDR,
    input  wire  [1:0]             HTRANS,
    input  wire                    HWRITE,
    input  wire  [2:0]             HSIZE,
    input  wire  [2:0]             HBURST,
    input  wire  [3:0]             HPROT,
    input  wire                    HMASTLOCK,
    input  wire  [DATA_WIDTH-1:0]  HWDATA,
    output wire  [DATA_WIDTH-1:0]  HRDATA,
    output wire                    HREADY,
    output wire                    HRESP,

    output wire                    o_plic_eip,
    output wire                    o_clint_mtip,
    output wire                    o_clint_msip,

    output wire                    o_timer_irq,
    inout  wire [GPIO_NUM-1:0]     io_gpioPin,
    input  wire                    i_uart_rx,
    output wire                    o_uart_tx,
    output wire                    o_spiMosi,
    input  wire                    i_spiMiso,
    output wire                    o_spiSs,
    output wire                    o_spiClk
);

    wire [SLAVE_NUM-1:0]   slave_HSELx;

    wire [DATA_WIDTH-1:0]  sram_HRDATA;
    wire [DATA_WIDTH-1:0]  plic_HRDATA;
    wire [DATA_WIDTH-1:0]  clint_HRDATA;
    wire [DATA_WIDTH-1:0]  bridge_HRDATA;
    wire [DATA_WIDTH*SLAVE_NUM-1:0] slave_HRDATA;
    wire [SLAVE_NUM-1:0]   slave_HREADYOUT;
    wire [SLAVE_NUM-1:0]   slave_HRESP;

    assign slave_HSELx[0] = (HADDR[31:24] == 8'h80);
    assign slave_HSELx[1] = (HADDR[31:24] == 8'h0C);
    assign slave_HSELx[2] = (HADDR[31:24] == 8'h02);
    assign slave_HSELx[3] = (HADDR[31:24] == 8'h10);

    ahb_mux #(
        .DATA_WIDTH (DATA_WIDTH),
        .SLAVE_NUM  (SLAVE_NUM)
    ) u_ahb_mux (
        .HSELx          (slave_HSELx),
        .slave_HRDATA   (slave_HRDATA),
        .slave_HREADYOUT(slave_HREADYOUT),
        .slave_HRESP    (slave_HRESP),
        .HRDATA         (HRDATA),
        .HREADY         (HREADY),
        .HRESP          (HRESP)
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
        .HADDR     (HADDR),
        .HTRANS    (HTRANS),
        .HWRITE    (HWRITE),
        .HSIZE     (HSIZE),
        .HBURST    (HBURST),
        .HPROT     (HPROT),
        .HWDATA    (HWDATA),
        .HREADY    (HREADY),
        .HREADYOUT (slave_HREADYOUT[0]),
        .HRESP     (slave_HRESP[0]),
        .HRDATA    (sram_HRDATA)
    );

    wire [7:0] plic_src_irq;
    assign plic_src_irq[0] = 1'b0;
    assign plic_src_irq[1] = o_timer_irq;
    assign plic_src_irq[2] = 1'b0;
    assign plic_src_irq[3] = 1'b0;
    assign plic_src_irq[4] = 1'b0;
    assign plic_src_irq[5] = 1'b0;
    assign plic_src_irq[6] = 1'b0;
    assign plic_src_irq[7] = 1'b0;

    ahb_plic #(
        .NUM_SRC (8)
    ) u_ahb_plic (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HSEL      (slave_HSELx[1]),
        .HADDR     (HADDR),
        .HTRANS    (HTRANS),
        .HWRITE    (HWRITE),
        .HSIZE     (HSIZE),
        .HWDATA    (HWDATA),
        .HREADY    (HREADY),
        .HREADYOUT (slave_HREADYOUT[1]),
        .HRESP     (slave_HRESP[1]),
        .HRDATA    (plic_HRDATA),
        .src_irq   (plic_src_irq),
        .o_eip     (o_plic_eip)
    );

    ahb_clint u_ahb_clint (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HSEL      (slave_HSELx[2]),
        .HADDR     (HADDR),
        .HTRANS    (HTRANS),
        .HWRITE    (HWRITE),
        .HSIZE     (HSIZE),
        .HWDATA    (HWDATA),
        .HREADY    (HREADY),
        .HREADYOUT (slave_HREADYOUT[2]),
        .HRESP     (slave_HRESP[2]),
        .HRDATA    (clint_HRDATA),
        .o_mtip    (o_clint_mtip),
        .o_msip    (o_clint_msip)
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

    ahb_lite_to_apb #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_ahb_lite_to_apb (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HADDR     (HADDR),
        .HTRANS    (HTRANS),
        .HWRITE    (HWRITE),
        .HSIZE     (HSIZE),
        .HBURST    (HBURST),
        .HPROT     (HPROT),
        .HWDATA    (HWDATA),
        .HSEL      (slave_HSELx[3]),
        .HREADY    (HREADY),
        .HREADYOUT (slave_HREADYOUT[3]),
        .HRESP     (slave_HRESP[3]),
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

    assign slave_HRDATA = {bridge_HRDATA, clint_HRDATA, plic_HRDATA, sram_HRDATA};

endmodule
