`include "apb_def.vh"
`timescale 1ns / 1ps

module uart_top #(
    parameter FREQ = 100
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
    output wire                        o_tx
);

    localparam UART_CTRL   = 8'h0;
    localparam UART_STATUS = 8'h4;
    localparam UART_TXDATA = 8'h8;
    localparam UART_RXDATA = 8'hC;

    wire [7:0] rx_data;

    reg [31:0] uart_ctrl;
    reg [31:0] uart_status;
    reg [31:0] uart_tx;
    reg [31:0] uart_rx;

    wire tx_data_ready;
    wire rx_data_valid;

    wire write_access = PSEL & PENABLE & PWRITE & PREADY;
    wire read_access  = PSEL & PENABLE & !PWRITE;

    wire write_reg_ctrl_en   = write_access && (PADDR[7:0] == UART_CTRL);
    wire write_reg_status_en = write_access && (PADDR[7:0] == UART_STATUS);
    wire write_reg_txdata_en = write_access && (PADDR[7:0] == UART_TXDATA);

    wire tx_start     = write_reg_txdata_en & uart_ctrl[0] & (~uart_status[0]) & tx_data_ready;
    wire rx_recv_over = uart_ctrl[1] & rx_data_valid;

    reg r_tx_start;
    reg r_tx_data_ready;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            r_tx_start       <= 1'b0;
            r_tx_data_ready  <= 1'b0;
        end else begin
            r_tx_start      <= tx_start;
            r_tx_data_ready <= tx_data_ready;
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            uart_rx <= 32'h0;
        end else begin
            if (read_access && (PADDR[7:0] == UART_RXDATA) && rx_recv_over) begin
                uart_rx[7:0] <= rx_data;
            end
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            uart_tx <= 32'h0;
        end else begin
            if (tx_start) begin
                uart_tx[7:0] <= PWDATA[7:0];
            end
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            uart_status <= 32'h0;
        end else begin
            if (write_reg_status_en) begin
                uart_status[1] <= PWDATA[1];
            end else begin
                if (r_tx_start) begin
                    uart_status[0] <= 1'b1;
                end else if (tx_data_ready) begin
                    uart_status[0] <= 1'b0;
                end
                if (rx_recv_over) begin
                    uart_status[1] <= 1'b1;
                end
            end
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            uart_ctrl <= 32'h0;
        end else begin
            if (write_reg_ctrl_en) begin
                uart_ctrl <= {24'b0, PWDATA[7:0]};
            end
        end
    end

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    always @(*) begin
        if (read_access) begin
            case (PADDR[7:0])
                UART_CTRL:   PRDATA = uart_ctrl;
                UART_STATUS: PRDATA = uart_status;
                UART_RXDATA: PRDATA = uart_rx;
                default:     PRDATA = {`APB_DATA_WIDTH{1'b0}};
            endcase
        end else begin
            PRDATA = {`APB_DATA_WIDTH{1'b0}};
        end
    end

    uart_rx #(
        .CLK_FRE  (FREQ),
        .BAUD_RATE(115200)
    ) uart_rx_inst (
        .clk             (PCLK),
        .rst             (PRESETn),
        .o_rxData_8      (rx_data),
        .o_rxDataValid_1 (rx_data_valid),
        .i_rxDataReady_1 (uart_ctrl[1]),
        .i_rxPin_1       (i_rx)
    );

    uart_tx #(
        .CLK_FRE  (FREQ),
        .BAUD_RATE(115200)
    ) uart_tx_inst (
        .clk              (PCLK),
        .rst              (PRESETn),
        .i_txData_8       (uart_tx[7:0]),
        .i_txDataValid_1  (r_tx_start),
        .o_txDataReady_1  (tx_data_ready),
        .o_txPin_1        (o_tx)
    );

endmodule
