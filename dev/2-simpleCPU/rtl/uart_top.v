`timescale 1ns / 1ps

module uart_top
(
    input  wire         clk,
    input  wire         reset,
    input  wire [15:0]  i_clkCnt_16,
    input  wire         i_cs_1,
    input  wire         i_rw_1,
    input  wire [31:0]  i_addr_32,
    input  wire [31:0]  i_wrData_32,
    input  wire         i_rx_1,
    output wire [31:0]  o_rdData_32,
    output wire         o_rxDataValid_1,
    output wire         o_tx_1
);

    localparam UART_CTRL   = 8'h0;
    localparam UART_STATUS = 8'h4;
    localparam UART_TXDATA = 8'h8;
    localparam UART_RXDATA = 8'hc;

    reg [31:0] uart_ctrl;
    reg [31:0] uart_status;
    reg [31:0] uart_tx;
    reg [31:0] uart_rx;

    wire [7:0] rx_data;
    wire       rx_data_valid;
    wire       tx_data_ready;

    wire wen = ~i_rw_1;
    wire write_reg_ctrl_en   = wen & (i_addr_32[7:0] == UART_CTRL);
    wire write_reg_status_en = wen & (i_addr_32[7:0] == UART_STATUS);
    wire write_reg_txdata_en = wen & (i_addr_32[7:0] == UART_TXDATA);
    wire tx_start = write_reg_txdata_en & uart_ctrl[0] & (~uart_status[0]) & tx_data_ready;
    wire rx_recv_over = uart_ctrl[1] & rx_data_valid;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            uart_rx <= 32'h0;
        end else begin
            if (i_cs_1 && i_rw_1 == 1'b0) begin
                if (rx_recv_over) begin
                    uart_rx[7:0] <= rx_data;
                end
            end
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            uart_tx <= 32'h0;
        end else begin
            if (i_cs_1 && i_rw_1 == 1'b1) begin
                if (tx_start) begin
                    uart_tx[7:0] <= i_wrData_32[7:0];
                end
            end
        end
    end

    reg r_tx_start;
    reg r_tx_data_ready;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_tx_start <= 1'b0;
            r_tx_data_ready <= 1'b0;
        end else begin
            r_tx_start <= tx_start;
            r_tx_data_ready <= tx_data_ready;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            uart_status <= 32'h0;
        end else begin
            if (write_reg_status_en) begin
                uart_status[1] <= i_wrData_32[1];
            end else begin
                if (r_tx_start) begin
                    uart_status[0] <= 1'b1;
                end else if (tx_data_ready == 1'b1) begin
                    uart_status[0] <= 1'b0;
                end
                if (rx_recv_over) begin
                    uart_status[1] <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            uart_ctrl <= 32'h0;
        end else begin
            if (write_reg_ctrl_en) begin
                uart_ctrl <= {24'b0, i_wrData_32[7:0]};
            end
        end
    end

    assign o_rdData_32 = (i_addr_32[7:0] == UART_CTRL)   ? uart_ctrl   :
                         (i_addr_32[7:0] == UART_STATUS) ? uart_status :
                         (i_addr_32[7:0] == UART_RXDATA) ? uart_rx     : 32'b0;

    assign o_rxDataValid_1 = rx_data_valid;

    simple_uart_rx uart_rx_inst (
        .clk              (clk),
        .reset            (reset),
        .i_clkCnt_16      (i_clkCnt_16),
        .o_rxData_8       (rx_data),
        .o_rxDataValid_1  (rx_data_valid),
        .i_rxDataReady_1  (uart_ctrl[1]),
        .i_rxPin_1        (i_rx_1)
    );

    simple_uart_tx uart_tx_inst (
        .clk              (clk),
        .reset            (reset),
        .i_clkCnt_16      (i_clkCnt_16),
        .i_txData_8       (uart_tx[7:0]),
        .i_txDataValid_1  (r_tx_start),
        .o_txDataReady_1  (tx_data_ready),
        .o_txPin_1        (o_tx_1)
    );

endmodule
