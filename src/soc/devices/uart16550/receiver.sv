// UART Receiver for NS16550A
// Adapted from chiplab IP/APB_DEV/URT/uart_receiver.v
// Changes: none (receiver had no USART-specific logic)

`timescale 1ns / 1ps

`include "soc/devices/uart16550/defs.svh"

module uart_receiver (
    input  wire        clk,
    input  wire        wb_rst_i,
    input  wire [7:0]  lcr,
    input  wire        rf_pop,
    input  wire        srx_pad_i,
    input  wire        enable,
    input  wire        rx_reset,
    input  wire        lsr_mask,
    output reg  [9:0]  counter_t,
    output wire [`UART_FIFO_COUNTER_W-1:0] rf_count,
    output wire [`UART_FIFO_REC_WIDTH-1:0] rf_data_out,
    output wire        rf_overrun,
    output wire        rf_error_bit,
    output reg  [3:0]  rstate,
    output wire        rf_push_pulse
);

    reg [3:0]  rcounter16;
    reg [2:0]  rbit_counter;
    reg [7:0]  rshift;
    reg        rparity;
    reg        rparity_error;
    reg        rframing_error;
    reg        rbit_in;
    reg        rparity_xor;
    reg [7:0]  counter_b;
    reg        rf_push_q;

    reg [`UART_FIFO_REC_WIDTH-1:0] rf_data_in;
    reg  rf_push;
    wire break_error = (counter_b == 8'b0);

    uart_rfifo #(
        .FIFO_WIDTH (`UART_FIFO_REC_WIDTH)
    ) fifo_rx (
        .clk          (clk),
        .wb_rst_i     (wb_rst_i),
        .data_in      (rf_data_in),
        .data_out     (rf_data_out),
        .push         (rf_push_pulse),
        .pop          (rf_pop),
        .overrun      (rf_overrun),
        .count        (rf_count),
        .error_bit    (rf_error_bit),
        .fifo_reset   (rx_reset),
        .reset_status (lsr_mask)
    );

    wire rcounter16_eq_7 = (rcounter16 == 4'd7);
    wire rcounter16_eq_0 = (rcounter16 == 4'd0);
    wire [3:0] rcounter16_minus_1 = rcounter16 - 1'b1;

    localparam SR_IDLE         = 4'd0;
    localparam SR_REC_START   = 4'd1;
    localparam SR_REC_BIT     = 4'd2;
    localparam SR_REC_PARITY  = 4'd3;
    localparam SR_REC_STOP    = 4'd4;
    localparam SR_CHECK_PARITY = 4'd5;
    localparam SR_REC_PREPARE = 4'd6;
    localparam SR_END_BIT     = 4'd7;
    localparam SR_CA_LC_PARITY = 4'd8;
    localparam SR_WAIT1       = 4'd9;
    localparam SR_PUSH        = 4'd10;

    always @(posedge clk) begin
        if (wb_rst_i) begin
            rstate          <= SR_IDLE;
            rbit_in         <= 1'b0;
            rcounter16      <= 4'b0;
            rbit_counter    <= 3'b0;
            rparity_xor     <= 1'b0;
            rframing_error  <= 1'b0;
            rparity_error   <= 1'b0;
            rparity         <= 1'b0;
            rshift          <= 8'b0;
            rf_push         <= 1'b0;
            rf_data_in      <= 11'b0;
        end else if (enable) begin
            case (rstate)
            SR_IDLE: begin
                rf_push   <= 1'b0;
                rf_data_in <= 11'b0;
                rcounter16 <= 4'b1110;
                if (srx_pad_i == 1'b0 & ~break_error)
                    rstate <= SR_REC_START;
            end
            SR_REC_START: begin
                rf_push <= 1'b0;
                if (rcounter16_eq_7) begin
                    if (srx_pad_i == 1'b1)
                        rstate <= SR_IDLE;
                    else
                        rstate <= SR_REC_PREPARE;
                end
                rcounter16 <= rcounter16_minus_1;
            end
            SR_REC_PREPARE: begin
                case (lcr[1:0])
                2'b00: rbit_counter <= 3'b100;
                2'b01: rbit_counter <= 3'b101;
                2'b10: rbit_counter <= 3'b110;
                2'b11: rbit_counter <= 3'b111;
                endcase
                if (rcounter16_eq_0) begin
                    rstate     <= SR_REC_BIT;
                    rcounter16 <= 4'b1110;
                    rshift     <= 8'b0;
                end else begin
                    rstate     <= SR_REC_PREPARE;
                    rcounter16 <= rcounter16_minus_1;
                end
            end
            SR_REC_BIT: begin
                if (rcounter16_eq_0)
                    rstate <= SR_END_BIT;
                if (rcounter16_eq_7)
                    case (lcr[1:0])
                    2'b00: rshift[4:0] <= {srx_pad_i, rshift[4:1]};
                    2'b01: rshift[5:0] <= {srx_pad_i, rshift[5:1]};
                    2'b10: rshift[6:0] <= {srx_pad_i, rshift[6:1]};
                    2'b11: rshift[7:0] <= {srx_pad_i, rshift[7:1]};
                    endcase
                rcounter16 <= rcounter16_minus_1;
            end
            SR_END_BIT: begin
                if (rbit_counter == 3'b0) begin
                    if (lcr[`UART_LC_PE])
                        rstate <= SR_REC_PARITY;
                    else begin
                        rstate        <= SR_REC_STOP;
                        rparity_error <= 1'b0;
                    end
                end else begin
                    rstate        <= SR_REC_BIT;
                    rbit_counter  <= rbit_counter - 1'b1;
                end
                rcounter16 <= 4'b1110;
            end
            SR_REC_PARITY: begin
                if (rcounter16_eq_7) begin
                    rparity <= srx_pad_i;
                    rstate  <= SR_CA_LC_PARITY;
                end
                rcounter16 <= rcounter16_minus_1;
            end
            SR_CA_LC_PARITY: begin
                rcounter16  <= rcounter16_minus_1;
                rparity_xor <= ^{rshift, rparity};
                rstate      <= SR_CHECK_PARITY;
            end
            SR_CHECK_PARITY: begin
                case ({lcr[`UART_LC_EP], lcr[`UART_LC_SP]})
                2'b00: rparity_error <= (rparity_xor == 1'b0);
                2'b01: rparity_error <= ~rparity;
                2'b10: rparity_error <= (rparity_xor == 1'b1);
                2'b11: rparity_error <= rparity;
                endcase
                rcounter16 <= rcounter16_minus_1;
                rstate     <= SR_WAIT1;
            end
            SR_WAIT1: begin
                if (rcounter16_eq_0) begin
                    rstate     <= SR_REC_STOP;
                    rcounter16 <= 4'b1110;
                end else
                    rcounter16 <= rcounter16_minus_1;
            end
            SR_REC_STOP: begin
                if (rcounter16_eq_7) begin
                    rframing_error <= !srx_pad_i;
                    rstate         <= SR_PUSH;
                end
                rcounter16 <= rcounter16_minus_1;
            end
            SR_PUSH: begin
                if (srx_pad_i | break_error) begin
                    if (break_error)
                        rf_data_in <= {8'b0, 3'b100};  // break error flag
                    else
                        rf_data_in <= {rshift, 1'b0, rparity_error, rframing_error};
                    rf_push <= 1'b1;
                    rstate  <= SR_IDLE;
                end else if (~rframing_error) begin
                    rf_data_in  <= {rshift, 1'b0, rparity_error, rframing_error};
                    rf_push     <= 1'b1;
                    rcounter16  <= 4'b1110;
                    rstate      <= SR_REC_START;
                end
            end
            default: rstate <= SR_IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (wb_rst_i)
            rf_push_q <= 1'b0;
        else
            rf_push_q <= rf_push;
    end

    assign rf_push_pulse = rf_push & ~rf_push_q;

    // Timeout counter for character timeout indication
    reg [9:0] toc_value;

    always @(*) begin
        case (lcr[3:0])
        4'b0000:                            toc_value = 447;
        4'b0100:                            toc_value = 479;
        4'b0001, 4'b1000:                   toc_value = 511;
        4'b1100:                            toc_value = 543;
        4'b0010, 4'b0101, 4'b1001:          toc_value = 575;
        4'b0011, 4'b0110, 4'b1010, 4'b1101: toc_value = 639;
        4'b0111, 4'b1011, 4'b1110:          toc_value = 703;
        4'b1111:                            toc_value = 767;
        default:                            toc_value = 511;
        endcase
    end

    wire [7:0] brc_value = toc_value[9:2];

    always @(posedge clk) begin
        if (wb_rst_i)
            counter_b <= 8'd159;
        else if (srx_pad_i)
            counter_b <= brc_value;
        else if (enable & counter_b != 8'b0)
            counter_b <= counter_b - 1'b1;
    end

    always @(posedge clk) begin
        if (wb_rst_i)
            counter_t <= 10'd639;
        else if (rf_push_pulse || rf_pop || rf_count == 0)
            counter_t <= toc_value;
        else if (enable && counter_t != 10'b0)
            counter_t <= counter_t - 1'b1;
    end

endmodule
