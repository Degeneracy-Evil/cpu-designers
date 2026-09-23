`include "soc/bus/apb/defs.svh"
`timescale 1ns / 1ps

module apb_perips #(
    parameter ADDR_WIDTH  = `APB_ADDR_WIDTH,
    parameter DATA_WIDTH  = `APB_DATA_WIDTH,
    parameter STRB_WIDTH  = `APB_STRB_WIDTH,
    parameter PROT_WIDTH  = `APB_PROT_WIDTH,
    parameter GPIO_NUM    = 16,
    parameter UART_FREQ   = 100,
    parameter UART_FIFO_DEPTH = 16
)(
    input  wire                  PCLK,
    input  wire                  PRESETn,

    input  wire  [ADDR_WIDTH-1:0] PADDR,
    input  wire  [PROT_WIDTH-1:0] PPROT,
    input  wire  [3:0]            PSELx,
    input  wire                   PENABLE,
    input  wire                   PWRITE,
    input  wire  [DATA_WIDTH-1:0] PWDATA,
    input  wire  [STRB_WIDTH-1:0] PSTRB,

    output wire [3:0]            slave_PREADY,
    output wire [DATA_WIDTH-1:0] slave0_PRDATA,
    output wire [DATA_WIDTH-1:0] slave1_PRDATA,
    output wire [DATA_WIDTH-1:0] slave2_PRDATA,
    output wire [DATA_WIDTH-1:0] slave3_PRDATA,
    output wire [3:0]            slave_PSLVERR,

    output wire [DATA_WIDTH-1:0] o_gpioCtrl,
    output wire [DATA_WIDTH-1:0] o_gpioData,
    inout  wire [GPIO_NUM-1:0]   io_gpioPin,

    output wire                   o_gpio_irq,

    input  wire                   i_uart_rx,
    output wire                   o_uart_tx,
    output wire                   o_uart_irq,

    output wire                   o_spiMosi,
    input  wire                   i_spiMiso,
    output wire                   o_spiSs,
    output wire                   o_spiClk,
    output wire                   o_spi_irq
);

    gpio #(
        .GPIO_NUM (GPIO_NUM)
    ) u_gpio (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),
        .PADDR     (PADDR),
        .PPROT     (PPROT),
        .PSEL      (PSELx[0]),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PWDATA    (PWDATA),
        .PSTRB     (PSTRB),
        .PREADY    (slave_PREADY[0]),
        .PRDATA    (slave0_PRDATA),
        .PSLVERR   (slave_PSLVERR[0]),
        .o_gpioCtrl(o_gpioCtrl),
        .o_gpioData(o_gpioData),
        .io_gpioPin(io_gpioPin),
        .o_irq     (o_gpio_irq)
    );

    // Slot 1 remains physically present only to preserve UART/SPI slot numbering.

    uart_16550a #(
        .FIFO_DEPTH (UART_FIFO_DEPTH)
    ) u_uart (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PADDR   (PADDR),
        .PPROT   (PPROT),
        .PSEL    (PSELx[2]),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PWDATA  (PWDATA),
        .PSTRB   (PSTRB),
        .PREADY  (slave_PREADY[2]),
        .PRDATA  (slave2_PRDATA),
        .PSLVERR (slave_PSLVERR[2]),
        .i_rx    (i_uart_rx),
        .o_tx    (o_uart_tx),
        .o_irq   (o_uart_irq)
    );

    spi u_spi (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),
        .PADDR    (PADDR),
        .PPROT    (PPROT),
        .PSEL     (PSELx[3]),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PWDATA   (PWDATA),
        .PSTRB    (PSTRB),
        .PREADY   (slave_PREADY[3]),
        .PRDATA   (slave3_PRDATA),
        .PSLVERR  (slave_PSLVERR[3]),
        .o_spiMosi(o_spiMosi),
        .i_spiMiso(i_spiMiso),
        .o_spiSs  (o_spiSs),
        .o_spiClk (o_spiClk),
        .o_irq    (o_spi_irq)
    );

    // The top-level exact decoder cannot route the removed timer window here.
    // Return an error defensively if another master ever reaches this slot.
    assign slave_PREADY [1] = 1'b1;
    assign slave_PSLVERR[1] = 1'b1;
    assign slave1_PRDATA    = 32'd0;

endmodule
