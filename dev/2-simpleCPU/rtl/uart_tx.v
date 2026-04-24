`timescale 1ns / 1ps

module uart_tx
#(
    parameter CLK_FRE = 25,
    parameter BAUD_RATE = 115200
)
(
    input                        clk,
    input                        reset,
    input       [7:0]            i_txData_8,
    input                        i_txDataValid_1,
    output reg                   o_txDataReady_1,
    output                       o_txPin_1
);

    localparam CYCLE = CLK_FRE * 1000000 / BAUD_RATE;

    localparam S_IDLE     = 1;
    localparam S_START    = 2;
    localparam S_SEND_BYTE = 3;
    localparam S_STOP     = 4;

    reg [2:0]  state;
    reg [2:0]  next_state;
    reg [15:0] cycle_cnt;
    reg [2:0]  bit_cnt;
    reg [7:0]  tx_data_latch;
    reg        tx_reg;

    assign o_txPin_1 = tx_reg;

    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        case (state)
            S_IDLE:
                if (i_txDataValid_1 == 1'b1)
                    next_state = S_START;
                else
                    next_state = S_IDLE;
            S_START:
                if ($unsigned(cycle_cnt) == CYCLE - 1)
                    next_state = S_SEND_BYTE;
                else
                    next_state = S_START;
            S_SEND_BYTE:
                if ($unsigned(cycle_cnt) == CYCLE - 1 && bit_cnt == 3'd7)
                    next_state = S_STOP;
                else
                    next_state = S_SEND_BYTE;
            S_STOP:
                if ($unsigned(cycle_cnt) == CYCLE - 1)
                    next_state = S_IDLE;
                else
                    next_state = S_STOP;
            default:
                next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            o_txDataReady_1 <= 1'b0;
        end else if (state == S_IDLE) begin
            if (i_txDataValid_1 == 1'b1)
                o_txDataReady_1 <= 1'b0;
            else
                o_txDataReady_1 <= 1'b1;
        end else if (state == S_STOP && $unsigned(cycle_cnt) == CYCLE - 1) begin
            o_txDataReady_1 <= 1'b1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_data_latch <= 8'd0;
        end else if (state == S_IDLE && i_txDataValid_1 == 1'b1) begin
            tx_data_latch <= i_txData_8;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bit_cnt <= 3'd0;
        end else if (state == S_SEND_BYTE) begin
            if ($unsigned(cycle_cnt) == CYCLE - 1)
                bit_cnt <= bit_cnt + 3'd1;
        end else begin
            bit_cnt <= 3'd0;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cycle_cnt <= 16'd0;
        end else if ((state == S_SEND_BYTE && $unsigned(cycle_cnt) == CYCLE - 1) || next_state != state) begin
            cycle_cnt <= 16'd0;
        end else begin
            cycle_cnt <= cycle_cnt + 16'd1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_reg <= 1'b1;
        end else begin
            case (state)
                S_IDLE, S_STOP:
                    tx_reg <= 1'b1;
                S_START:
                    tx_reg <= 1'b0;
                S_SEND_BYTE:
                    tx_reg <= tx_data_latch[bit_cnt];
                default:
                    tx_reg <= 1'b1;
            endcase
        end
    end

endmodule
