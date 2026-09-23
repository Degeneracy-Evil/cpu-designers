// UART Transmitter for NS16550A
// Adapted from chiplab IP/APB_DEV/URT/uart_transmitter.v
// Changes: removed USART T0/T1/IrDA extensions (repeat, error detection, guard time, tx2rx_en)

`timescale 1ns / 1ps

`include "soc/devices/uart16550/defs.svh"

module uart_transmitter (
    input  wire        clk,
    input  wire        wb_rst_i,
    input  wire [7:0]  lcr,
    input  wire        tf_push,
    input  wire [7:0]  wb_dat_i,
    input  wire        enable,
    input  wire        tx_reset,
    input  wire        lsr_mask,
    output wire        stx_pad_o,
    output wire [2:0]  tstate,
    output wire [`UART_FIFO_COUNTER_W-1:0] tf_count
);

    // TX FIFO
    wire [`UART_FIFO_WIDTH-1:0]   tf_data_in;
    wire [`UART_FIFO_WIDTH-1:0]   tf_data_out;
    wire                          tf_overrun;
    reg                           tf_pop;     // Declared before FIFO instantiation

    assign tf_data_in = wb_dat_i;

    uart_tfifo fifo_tx (
        .clk          (clk),
        .wb_rst_i     (wb_rst_i),
        .data_in      (tf_data_in),
        .data_out     (tf_data_out),
        .push         (tf_push),
        .pop          (tf_pop),
        .overrun      (tf_overrun),
        .count        (tf_count),
        .fifo_reset   (tx_reset),
        .reset_status (lsr_mask)
    );

    // State machine
    localparam S_IDLE        = 3'd0;
    localparam S_SEND_START  = 3'd1;
    localparam S_SEND_BYTE   = 3'd2;
    localparam S_SEND_PARITY = 3'd3;
    localparam S_SEND_STOP   = 3'd4;
    localparam S_POP_BYTE    = 3'd5;

    reg [2:0]  tstate_r;
    reg [4:0]  counter;
    reg [2:0]  bit_counter;
    reg [6:0]  shift_out;
    reg        stx_o_tmp;
    reg        parity_xor;
    reg        bit_out;

    assign tstate = tstate_r;

    always @(posedge clk) begin
        if (wb_rst_i) begin
            tstate_r    <= S_IDLE;
            stx_o_tmp   <= 1'b1;
            counter     <= 5'b0;
            shift_out   <= 7'b0;
            bit_out     <= 1'b0;
            parity_xor  <= 1'b0;
            tf_pop      <= 1'b0;
            bit_counter <= 3'b0;
        end else if (enable) begin
            case (tstate_r)
            S_IDLE: begin
                if (~|tf_count) begin
                    tstate_r  <= S_IDLE;
                    stx_o_tmp <= 1'b1;
                end else begin
                    tf_pop    <= 1'b0;
                    stx_o_tmp <= 1'b1;
                    tstate_r  <= S_POP_BYTE;
                end
            end
            S_POP_BYTE: begin
                tf_pop <= 1'b1;
                case (lcr[1:0])
                2'b00: begin
                    bit_counter <= 3'b100;
                    parity_xor  <= ^tf_data_out[4:0];
                end
                2'b01: begin
                    bit_counter <= 3'b101;
                    parity_xor  <= ^tf_data_out[5:0];
                end
                2'b10: begin
                    bit_counter <= 3'b110;
                    parity_xor  <= ^tf_data_out[6:0];
                end
                2'b11: begin
                    bit_counter <= 3'b111;
                    parity_xor  <= ^tf_data_out[7:0];
                end
                endcase
                {shift_out[6:0], bit_out} <= tf_data_out;
                tstate_r <= S_SEND_START;
            end
            S_SEND_START: begin
                tf_pop <= 1'b0;
                if (~|counter)
                    counter <= 5'b01111;
                else if (counter == 5'b00001) begin
                    counter <= 5'b0;
                    tstate_r <= S_SEND_BYTE;
                end else
                    counter <= counter - 1'b1;
                stx_o_tmp <= 1'b0;
            end
            S_SEND_BYTE: begin
                if (~|counter)
                    counter <= 5'b01111;
                else if (counter == 5'b00001) begin
                    if (bit_counter > 3'b0) begin
                        bit_counter <= bit_counter - 1'b1;
                        {shift_out[5:0], bit_out} <= {shift_out[6:1], shift_out[0]};
                        tstate_r <= S_SEND_BYTE;
                    end else if (~lcr[`UART_LC_PE]) begin
                        tstate_r <= S_SEND_STOP;
                    end else begin
                        case ({lcr[`UART_LC_EP], lcr[`UART_LC_SP]})
                        2'b00: bit_out <= ~parity_xor;
                        2'b01: bit_out <= 1'b1;
                        2'b10: bit_out <= parity_xor;
                        2'b11: bit_out <= 1'b0;
                        endcase
                        tstate_r <= S_SEND_PARITY;
                    end
                    counter <= 5'b0;
                end else
                    counter <= counter - 1'b1;
                stx_o_tmp <= bit_out;
            end
            S_SEND_PARITY: begin
                if (~|counter)
                    counter <= 5'b01111;
                else if (counter == 5'b00001) begin
                    counter  <= 4'b0;
                    tstate_r <= S_SEND_STOP;
                end else
                    counter <= counter - 1'b1;
                stx_o_tmp <= bit_out;
            end
            S_SEND_STOP: begin
                if (~|counter) begin
                    case ({lcr[`UART_LC_SB], lcr[`UART_LC_BITS]})
                    3'b0xx:  counter <= 5'b01101;   // 1 stop bit
                    3'b100:  counter <= 5'b10101;   // 1.5 stop bits (5-bit)
                    default: counter <= 5'b11101;   // 2 stop bits
                    endcase
                end else if (counter == 5'b00001) begin
                    counter  <= 5'b0;
                    tstate_r <= S_IDLE;
                end else
                    counter <= counter - 1'b1;
                stx_o_tmp <= 1'b1;
            end
            default: tstate_r <= S_IDLE;
            endcase
        end else begin
            tf_pop <= 1'b0;
        end
    end

    // Break control: force TX low when LCR[6]=1
    assign stx_pad_o = lcr[`UART_LC_BC] ? 1'b0 : stx_o_tmp;

endmodule
