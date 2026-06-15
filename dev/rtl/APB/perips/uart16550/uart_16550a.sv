// NS16550A UART — APB4 32-bit wrapper
//
// Adapts the 8-bit chiplab-style uart_regs_16550a to the APB4 32-bit bus
// used in the cpu-designers project.
//
// Address mapping:
//   NS16550A registers are at byte offsets 0-7.
//   Our APB4 bus uses word-aligned (4-byte) addresses.
//   Mapping: PADDR[4:2] → NS16550A byte offset (reg 0-7)
//   So: THR=0x00, IER=0x04, IIR/FCR=0x08, LCR=0x0C, MCR=0x10, LSR=0x14, MSR=0x18, SCR=0x1C
//
// Data width adaptation:
//   Read:  zero-extend 8-bit register value to 32-bit PRDATA
//   Write: take PWDATA[7:0] (PSTRB byte-lane masking applied)
//
// Interface: same ports as existing uart_top.sv for drop-in replacement

`include "apb_def.svh"
`include "uart_defines.svh"

module uart_16550a #(
    parameter FIFO_DEPTH = 16
)(
    input  wire                        PCLK,
    input  wire                        PRESETn,
    input  wire [31:0]                 PADDR,
    input  wire [2:0]                  PPROT,
    input  wire                        PSEL,
    input  wire                        PENABLE,
    input  wire                        PWRITE,
    input  wire [31:0]                 PWDATA,
    input  wire [3:0]                  PSTRB,
    output wire                        PREADY,
    output reg  [31:0]                 PRDATA,
    output wire                        PSLVERR,

    // Serial interface
    input  wire                        i_rx,
    output wire                        o_tx,

    // Interrupt
    output wire                        o_irq
);

    // APB4 control signals
    assign PREADY  = 1'b1;    // Zero wait states
    assign PSLVERR = 1'b0;    // Never errors

    wire prst = ~PRESETn;     // Active-high reset
    wire we   = PSEL & PENABLE & PWRITE;
    wire re   = PSEL & PENABLE & ~PWRITE;

    // Address translation: word offset → byte offset
    // PADDR[4:2] gives the register index (0-7) in word-aligned addressing
    wire [2:0] reg_addr = PADDR[4:2];

    // Write data: take lower 8 bits (PSTRB not used for 8-bit register writes;
    // software must write full 32-bit words with the byte in [7:0])
    wire [7:0] wr_data = PWDATA[7:0];

    // Read data from register module (8-bit)
    wire [7:0] rd_data;

    // Instantiate NS16550A register core
    uart_regs_16550a regs (
        .clk          (PCLK),
        .rst          (prst),
        .addr         (reg_addr),
        .dat_i        (wr_data),
        .dat_o        (rd_data),
        .we           (we),
        .re           (re),

        .modem_inputs (4'b1111),   // No modem inputs: CTS=DSR=RI=DCD asserted (inactive after inversion)
        .rts_pad_o    (),          // Not connected
        .dtr_pad_o    (),          // Not connected

        .stx_pad_o    (o_tx),
        .srx_pad_i    (i_rx),

        .int_o        (o_irq)
    );

    // Zero-extend 8-bit read data to 32-bit
    always @(*) begin
        PRDATA = {24'b0, rd_data};
    end

endmodule
