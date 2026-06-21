// TX FIFO for NS16550A UART
// Adapted from chiplab IP/APB_DEV/URT/uart_tfifo.v
// Fix: overrun condition changed to push & ~pop & (count==fifo_depth)

`timescale 1ns / 1ps

`include "uart_defines.svh"

module uart_tfifo #(
    parameter FIFO_WIDTH     = `UART_FIFO_WIDTH,
    parameter FIFO_DEPTH     = `UART_FIFO_DEPTH,
    parameter FIFO_POINTER_W = `UART_FIFO_POINTER_W,
    parameter FIFO_COUNTER_W = `UART_FIFO_COUNTER_W
)(
    input  wire                        clk,
    input  wire                        wb_rst_i,
    input  wire [FIFO_WIDTH-1:0]       data_in,
    input  wire                        push,
    input  wire                        pop,
    input  wire                        fifo_reset,
    input  wire                        reset_status,
    output wire [FIFO_WIDTH-1:0]       data_out,
    output reg                         overrun,
    output reg  [FIFO_COUNTER_W-1:0]   count
);

    reg [FIFO_POINTER_W-1:0] top;
    reg [FIFO_POINTER_W-1:0] bottom;

    wire [FIFO_POINTER_W-1:0] top_plus_1 = top + 1'b1;

    raminfr #(
        .ADDR_W (FIFO_POINTER_W),
        .DATA_W (FIFO_WIDTH),
        .DEPTH  (FIFO_DEPTH)
    ) tfifo (
        .clk  (clk),
        .we   (push),
        .a    (top),
        .dpra (bottom),
        .di   (data_in),
        .dpo  (data_out)
    );

    always @(posedge clk) begin
        if (wb_rst_i) begin
            top    <= 0;
            bottom <= 0;
            count  <= 0;
        end else if (fifo_reset) begin
            top    <= 0;
            bottom <= 0;
            count  <= 0;
        end else begin
            case ({push, pop})
            2'b10: if (count < FIFO_DEPTH) begin
                top   <= top_plus_1;
                count <= count + 1'b1;
            end
            2'b01: if (count > 0) begin
                bottom <= bottom + 1'b1;
                count  <= count - 1'b1;
            end
            2'b11: begin
                bottom <= bottom + 1'b1;
                top    <= top_plus_1;
            end
            default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        if (wb_rst_i)
            overrun <= 1'b0;
        else if (fifo_reset | reset_status)
            overrun <= 1'b0;
        else if (push & ~pop & (count == FIFO_DEPTH))
            overrun <= 1'b1;
    end

endmodule
