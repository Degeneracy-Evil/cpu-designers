`timescale 1ns / 1ps

module simple_uart_rx
(
    input                        clk,
    input                        reset,
    input       [15:0]           i_clkCnt_16,
    output reg [7:0]             o_rxData_8,
    output reg                   o_rxDataValid_1,
    input                        i_rxDataReady_1,
    input                        i_rxPin_1
);

    localparam S_IDLE     = 1;
    localparam S_START    = 2;
    localparam S_REC_BYTE = 3;
    localparam S_STOP     = 4;
    localparam S_DATA     = 5;

    reg [2:0]  state;
    reg [2:0]  next_state;
    reg        rx_d0;
    reg        rx_d1;
    wire       rx_negedge;
    reg [7:0]  rx_bits;
    reg [15:0] cycle_cnt;
    reg [2:0]  bit_cnt;

    assign rx_negedge = rx_d1 && ~rx_d0;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_d0 <= 1'b0;
            rx_d1 <= 1'b0;
        end else begin
            rx_d0 <= i_rxPin_1;
            rx_d1 <= rx_d0;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        case (state)
            S_IDLE:
                if (rx_negedge)
                    next_state = S_START;
                else
                    next_state = S_IDLE;
            S_START:
                if (cycle_cnt == i_clkCnt_16 - 1)
                    next_state = S_REC_BYTE;
                else
                    next_state = S_START;
            S_REC_BYTE:
                if (cycle_cnt == i_clkCnt_16 - 1 && bit_cnt == 3'd7)
                    next_state = S_STOP;
                else
                    next_state = S_REC_BYTE;
            S_STOP:
                if (cycle_cnt == ({1'b0, i_clkCnt_16[15:1]} - 1))
                    next_state = S_DATA;
                else
                    next_state = S_STOP;
            S_DATA:
                if (i_rxDataReady_1)
                    next_state = S_IDLE;
                else
                    next_state = S_DATA;
            default:
                next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            o_rxDataValid_1 <= 1'b0;
        end else if (state == S_STOP && next_state != state) begin
            o_rxDataValid_1 <= 1'b1;
        end else if (state == S_DATA && i_rxDataReady_1) begin
            o_rxDataValid_1 <= 1'b0;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            o_rxData_8 <= 8'd0;
        end else if (state == S_STOP && next_state != state) begin
            o_rxData_8 <= rx_bits;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bit_cnt <= 3'd0;
        end else if (state == S_REC_BYTE) begin
            if (cycle_cnt == i_clkCnt_16 - 1)
                bit_cnt <= bit_cnt + 3'd1;
        end else begin
            bit_cnt <= 3'd0;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cycle_cnt <= 16'd0;
        end else if ((state == S_REC_BYTE && cycle_cnt == i_clkCnt_16 - 1) || next_state != state) begin
            cycle_cnt <= 16'd0;
        end else begin
            cycle_cnt <= cycle_cnt + 16'd1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_bits <= 8'd0;
        end else if (state == S_REC_BYTE && cycle_cnt == {1'b0, i_clkCnt_16[15:1]} - 1) begin
            rx_bits[bit_cnt] <= i_rxPin_1;
        end
    end

endmodule
