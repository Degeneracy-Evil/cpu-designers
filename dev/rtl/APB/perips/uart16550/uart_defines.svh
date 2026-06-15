// NS16550A UART register and parameter definitions
// Adapted from chiplab IP/APB_DEV/URT/uart_defines.h
// Changes: none (definitions are NS16550A-compatible as-is)

`ifndef UART_DEFINES_SVH
`define UART_DEFINES_SVH

`define UART_ADDR_WIDTH 3
`define UART_DATA_WIDTH 8

// Register addresses (byte offset)
`define UART_REG_RB  `UART_ADDR_WIDTH'd0  // Receiver Buffer (read)
`define UART_REG_TR  `UART_ADDR_WIDTH'd0  // Transmitter Holding (write)
`define UART_REG_IE  `UART_ADDR_WIDTH'd1  // Interrupt Enable
`define UART_REG_II  `UART_ADDR_WIDTH'd2  // Interrupt Identification (read)
`define UART_REG_FC  `UART_ADDR_WIDTH'd2  // FIFO Control (write)
`define UART_REG_LC  `UART_ADDR_WIDTH'd3  // Line Control
`define UART_REG_MC  `UART_ADDR_WIDTH'd4  // Modem Control
`define UART_REG_LS  `UART_ADDR_WIDTH'd5  // Line Status
`define UART_REG_MS  `UART_ADDR_WIDTH'd6  // Modem Status
`define UART_REG_SR  `UART_ADDR_WIDTH'd7  // Scratch Register
`define UART_REG_DL1 `UART_ADDR_WIDTH'd0  // Divisor Latch LSB (DLAB=1)
`define UART_REG_DL2 `UART_ADDR_WIDTH'd1  // Divisor Latch MSB (DLAB=1)

// Interrupt Enable register bits
`define UART_IE_RDA  0   // Received Data Available
`define UART_IE_THRE 1   // Transmitter Holding Register Empty
`define UART_IE_RLS  2   // Receiver Line Status
`define UART_IE_MS   3   // Modem Status

// Interrupt Identification register bits
`define UART_II_IP   0   // Interrupt Pending (0=pending)
`define UART_II_II   3:1 // Interrupt identification

// Interrupt identification values for bits 3:1
`define UART_II_RLS  3'b011  // Receiver Line Status (highest priority)
`define UART_II_RDA  3'b010  // Receiver Data Available
`define UART_II_TI   3'b110  // Timeout Indication
`define UART_II_THRE 3'b001  // Transmitter Holding Register Empty
`define UART_II_MS   3'b000  // Modem Status (lowest priority)

// FIFO Control Register bits
`define UART_FC_TL   1:0  // Trigger level

// FIFO trigger level values
`define UART_FC_1   2'b00
`define UART_FC_4   2'b01
`define UART_FC_8   2'b10
`define UART_FC_14  2'b11

// Line Control register bits
`define UART_LC_BITS 1:0  // Character length
`define UART_LC_SB   2    // Stop bits
`define UART_LC_PE   3    // Parity enable
`define UART_LC_EP   4    // Even parity
`define UART_LC_SP   5    // Stick parity
`define UART_LC_BC   6    // Break control
`define UART_LC_DL   7    // Divisor Latch Access Bit

// Modem Control register bits
`define UART_MC_DTR  0
`define UART_MC_RTS  1
`define UART_MC_OUT1 2
`define UART_MC_OUT2 3
`define UART_MC_LB   4    // Loopback mode

// Line Status Register bits
`define UART_LS_DR   0    // Data Ready
`define UART_LS_OE   1    // Overrun Error
`define UART_LS_PE   2    // Parity Error
`define UART_LS_FE   3    // Framing Error
`define UART_LS_BI   4    // Break Interrupt
`define UART_LS_TFE  5    // Transmit FIFO Empty (THRE)
`define UART_LS_TE   6    // Transmitter Empty
`define UART_LS_EI   7    // Error Indicator

// Modem Status Register bits
`define UART_MS_DCTS 0    // Delta Clear To Send
`define UART_MS_DDSR 1    // Delta Data Set Ready
`define UART_MS_TERI 2    // Trailing Edge Ring Indicator
`define UART_MS_DDCD 3    // Delta Data Carrier Detect
`define UART_MS_CCTS 4    // Complement CTS
`define UART_MS_CDSR 5    // Complement DSR
`define UART_MS_CRI  6    // Complement RI
`define UART_MS_CDCD 7    // Complement DCD

// FIFO parameter defines
`define UART_FIFO_WIDTH     8
`define UART_FIFO_DEPTH     16
`define UART_FIFO_POINTER_W 4
`define UART_FIFO_COUNTER_W 5
`define UART_FIFO_REC_WIDTH 11

`endif // UART_DEFINES_SVH
