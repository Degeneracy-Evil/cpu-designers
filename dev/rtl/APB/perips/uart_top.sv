`include "apb_def.svh"
`timescale 1ns / 1ps

module uart_top #(
    parameter FREQ = 100,
    parameter FIFO_DEPTH = 16
)(
    input  wire                        PCLK,
    input  wire                        PRESETn,

    input  wire  [`APB_ADDR_WIDTH-1:0] PADDR,
    input  wire  [`APB_PROT_WIDTH-1:0] PPROT,
    input  wire                        PSEL,
    input  wire                        PENABLE,
    input  wire                        PWRITE,
    input  wire  [`APB_DATA_WIDTH-1:0] PWDATA,
    input  wire  [`APB_STRB_WIDTH-1:0] PSTRB,

    output wire                        PREADY,
    output reg  [`APB_DATA_WIDTH-1:0]  PRDATA,
    output wire                        PSLVERR,

    input  wire                        i_rx,
    output wire                        o_tx,

    output wire                        o_irq
);

    // -----------------------------------------------------------------------
    // Register offsets (backward compatible)
    // -----------------------------------------------------------------------
    localparam UART_CTRL     = 8'h00;  // [0]=TX_EN, [1]=RX_EN, [2]=TX_IE, [3]=RX_IE
    localparam UART_STATUS   = 8'h04;  // [0]=TX_BUSY, [1]=RX_VALID,
                                       // [2]=TX_FIFO_FULL, [3]=RX_FIFO_EMPTY,
                                       // [4]=TX_FIFO_EMPTY, [5]=RX_FIFO_FULL
    localparam UART_TXDATA   = 8'h08;  // Write: push to TX FIFO
    localparam UART_RXDATA   = 8'h0C;  // Read: pop from RX FIFO
    localparam UART_BAUD     = 8'h10;  // Baud rate divider (0 = default 115200)
    localparam UART_IRQ_STAT = 8'h14;  // [0]=TX_DONE_IRQ, [1]=RX_VALID_IRQ (W1C)

    // -----------------------------------------------------------------------
    // APB access signals (declared early for use throughout)
    // -----------------------------------------------------------------------
    wire write_access = PSEL & PENABLE & PWRITE & PREADY;
    wire read_access  = PSEL & PENABLE & !PWRITE;

    // -----------------------------------------------------------------------
    // Control & status registers
    // -----------------------------------------------------------------------
    reg [31:0] uart_ctrl;       // CTRL register
    reg [31:0] uart_baud;       // BAUD divider register
    reg [1:0]  uart_irq_stat;   // IRQ pending bits

    // Derived control bits
    wire tx_en  = uart_ctrl[0]; // TX enable
    wire rx_en  = uart_ctrl[1]; // RX enable
    wire tx_ie  = uart_ctrl[2]; // TX interrupt enable
    wire rx_ie  = uart_ctrl[3]; // RX interrupt enable

    // -----------------------------------------------------------------------
    // TX FIFO
    // -----------------------------------------------------------------------
    wire       tx_fifo_full;
    wire       tx_fifo_empty;
    wire [4:0] tx_fifo_count;
    wire [7:0] tx_fifo_rd_data;

    reg  tx_fifo_rd_en;
    wire tx_fifo_wr_en;

    // CPU writes to TXDATA register → push into TX FIFO
    assign tx_fifo_wr_en = write_access && (PADDR[7:0] == UART_TXDATA) && !tx_fifo_full;

    sync_fifo #(
        .WIDTH (8),
        .DEPTH (FIFO_DEPTH)
    ) u_tx_fifo (
        .clk     (PCLK),
        .rst_n   (PRESETn),
        .wr_en   (tx_fifo_wr_en),
        .wr_data (PWDATA[7:0]),
        .rd_en   (tx_fifo_rd_en),
        .rd_data (tx_fifo_rd_data),
        .full    (tx_fifo_full),
        .empty   (tx_fifo_empty),
        .count   (tx_fifo_count)
    );

    // -----------------------------------------------------------------------
    // RX FIFO
    // -----------------------------------------------------------------------
    wire       rx_fifo_full;
    wire       rx_fifo_empty;
    wire [4:0] rx_fifo_count;
    wire [7:0] rx_fifo_rd_data;

    wire rx_fifo_wr_en;
    reg  rx_fifo_rd_en;

    // RX engine outputs (declared here before FIFO instantiation)
    wire [7:0] rx_data_from_engine;
    wire       rx_data_valid;

    // CPU reads RXDATA register → pop from RX FIFO
    // Note: pop happens on read_access (combinational), but actual read enable
    // is gated to only pop when FIFO is not empty
    always @(*) begin
        rx_fifo_rd_en = 1'b0;
        if (read_access && (PADDR[7:0] == UART_RXDATA) && !rx_fifo_empty) begin
            rx_fifo_rd_en = 1'b1;
        end
    end

    sync_fifo #(
        .WIDTH (8),
        .DEPTH (FIFO_DEPTH)
    ) u_rx_fifo (
        .clk     (PCLK),
        .rst_n   (PRESETn),
        .wr_en   (rx_fifo_wr_en),
        .wr_data (rx_data_from_engine),
        .rd_en   (rx_fifo_rd_en),
        .rd_data (rx_fifo_rd_data),
        .full    (rx_fifo_full),
        .empty   (rx_fifo_empty),
        .count   (rx_fifo_count)
    );

    // -----------------------------------------------------------------------
    // UART TX engine
    // -----------------------------------------------------------------------
    wire tx_data_ready;  // TX engine ready for next byte

    // Feed TX FIFO data to TX engine
    // Pop from FIFO when TX engine accepts the data
    always @(*) begin
        tx_fifo_rd_en = 1'b0;
        if (tx_en && !tx_fifo_empty && tx_data_ready) begin
            tx_fifo_rd_en = 1'b1;
        end
    end

    uart_tx #(
        .CLK_FRE  (FREQ),
        .BAUD_RATE(115200)
    ) uart_tx_inst (
        .clk              (PCLK),
        .rst              (PRESETn),
        .i_baud_div       (uart_baud[15:0]),
        .i_txData_8       (tx_fifo_rd_data),
        .i_txDataValid_1  (tx_fifo_rd_en),
        .o_txDataReady_1  (tx_data_ready),
        .o_txPin_1        (o_tx)
    );

    // -----------------------------------------------------------------------
    // UART RX engine
    // -----------------------------------------------------------------------
    assign rx_fifo_wr_en = rx_en && rx_data_valid && !rx_fifo_full;

    uart_rx #(
        .CLK_FRE  (FREQ),
        .BAUD_RATE(115200)
    ) uart_rx_inst (
        .clk             (PCLK),
        .rst             (PRESETn),
        .o_rxData_8      (rx_data_from_engine),
        .o_rxDataValid_1 (rx_data_valid),
        .i_rxDataReady_1 (rx_en && !rx_fifo_full),
        .i_rxPin_1       (i_rx),
        .i_baud_div      (uart_baud[15:0])
    );

    // -----------------------------------------------------------------------
    // Interrupt logic
    // -----------------------------------------------------------------------
    // TX_DONE_IRQ: TX FIFO transitions from non-empty to empty
    //   (i.e., all queued bytes have been sent)
    reg tx_fifo_was_nonempty;
    wire tx_done_event = tx_fifo_was_nonempty && tx_fifo_empty;

    // RX_VALID_IRQ: RX FIFO transitions from empty to non-empty
    //   (i.e., new data available to read)
    reg rx_fifo_was_empty;
    wire rx_valid_event = rx_fifo_was_empty && !rx_fifo_empty;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_fifo_was_nonempty <= 1'b0;
            rx_fifo_was_empty    <= 1'b1;
        end else begin
            tx_fifo_was_nonempty <= !tx_fifo_empty;
            rx_fifo_was_empty    <= rx_fifo_empty;
        end
    end

    // IRQ pending bits: set on event, write-1-to-clear
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            uart_irq_stat <= 2'b0;
        end else begin
            // TX done event
            if (tx_done_event) begin
                uart_irq_stat[0] <= 1'b1;
            end
            // RX valid event
            if (rx_valid_event) begin
                uart_irq_stat[1] <= 1'b1;
            end
            // Write-1-to-clear via IRQ_STAT register
            if (write_access && (PADDR[7:0] == UART_IRQ_STAT)) begin
                if (PWDATA[0]) uart_irq_stat[0] <= 1'b0;
                if (PWDATA[1]) uart_irq_stat[1] <= 1'b0;
            end
        end
    end

    // Combined IRQ output
    assign o_irq = (tx_ie & uart_irq_stat[0]) | (rx_ie & uart_irq_stat[1]);

    // -----------------------------------------------------------------------
    // APB register write logic
    // -----------------------------------------------------------------------
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            uart_ctrl <= 32'h0;
            uart_baud <= 32'h0;
        end else begin
            if (write_access) begin
                case (PADDR[7:0])
                    UART_CTRL: begin
                        uart_ctrl <= {24'b0, PWDATA[7:0]};
                    end
                    UART_BAUD: begin
                        uart_baud <= PWDATA;
                    end
                    default: ;
                endcase
            end
        end
    end

    // -----------------------------------------------------------------------
    // APB register read logic
    // -----------------------------------------------------------------------
    // TX busy: TX engine is not idle (not ready) OR TX FIFO is not empty
    wire tx_busy = !tx_data_ready || !tx_fifo_empty;

    always @(*) begin
        if (read_access) begin
            case (PADDR[7:0])
                UART_CTRL: begin
                    PRDATA = uart_ctrl;
                end
                UART_STATUS: begin
                    PRDATA = {26'b0,
                              rx_fifo_full,    // [5]
                              tx_fifo_empty,   // [4]
                              rx_fifo_empty,   // [3]
                              tx_fifo_full,    // [2]
                              !rx_fifo_empty,  // [1] RX valid (backward compat)
                              tx_busy          // [0] TX busy  (backward compat)
                             };
                end
                UART_RXDATA: begin
                    PRDATA = {24'b0, rx_fifo_rd_data};
                end
                UART_BAUD: begin
                    PRDATA = uart_baud;
                end
                UART_IRQ_STAT: begin
                    PRDATA = {30'b0, uart_irq_stat};
                end
                default: begin
                    PRDATA = {`APB_DATA_WIDTH{1'b0}};
                end
            endcase
        end else begin
            PRDATA = {`APB_DATA_WIDTH{1'b0}};
        end
    end

endmodule
