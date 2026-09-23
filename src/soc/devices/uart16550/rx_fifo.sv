// RX FIFO for NS16550A UART
// Adapted from chiplab IP/APB_DEV/URT/uart_rfifo.v
// Fix: parameterized error_bit computation (generate loop instead of hardcoded 16 entries)

`timescale 1ns / 1ps

`include "soc/devices/uart16550/defs.svh"

module uart_rfifo #(
    parameter FIFO_WIDTH     = `UART_FIFO_REC_WIDTH,
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
    output reg  [FIFO_COUNTER_W-1:0]   count,
    output wire                        error_bit
);

    reg [FIFO_POINTER_W-1:0] top;
    reg [FIFO_POINTER_W-1:0] bottom;
    reg [2:0]                 fifo [FIFO_DEPTH-1:0];

    wire [FIFO_POINTER_W-1:0] top_plus_1 = top + 1'b1;

    // 8-bit data stored in dual-port RAM
    wire [7:0] data8_out;

    raminfr #(
        .ADDR_W (FIFO_POINTER_W),
        .DATA_W (8),
        .DEPTH  (FIFO_DEPTH)
    ) rfifo (
        .clk  (clk),
        .we   (push),
        .a    (top),
        .dpra (bottom),
        .di   (data_in[FIFO_WIDTH-1:FIFO_WIDTH-8]),
        .dpo  (data8_out)
    );

    // Error flags per entry: [0]=framing, [1]=parity, [2]=break
    integer i;
    always @(posedge clk) begin
        if (wb_rst_i) begin
            top    <= 0;
            bottom <= 0;
            count  <= 0;
            for (i = 0; i < FIFO_DEPTH; i = i + 1)
                fifo[i] <= 3'b0;
        end else if (fifo_reset) begin
            top    <= 0;
            bottom <= 0;
            count  <= 0;
            for (i = 0; i < FIFO_DEPTH; i = i + 1)
                fifo[i] <= 3'b0;
        end else begin
            case ({push, pop})
            2'b10: if (count < FIFO_DEPTH) begin
                top       <= top_plus_1;
                fifo[top] <= data_in[2:0];
                count     <= count + 1'b1;
            end
            2'b01: if (count > 0) begin
                fifo[bottom] <= 3'b0;
                bottom       <= bottom + 1'b1;
                count        <= count - 1'b1;
            end
            2'b11: begin
                bottom       <= bottom + 1'b1;
                top          <= top_plus_1;
                fifo[top]    <= data_in[2:0];
            end
            default: ;
            endcase
        end
    end

    // Output: {8-bit data, 3-bit error flags from current read position}
    assign data_out = {data8_out, fifo[bottom]};

    // OR-reduction of all error flags (parameterized via generate)
    reg [2:0] error_or;
    always @(*) begin
        error_or = 3'b0;
        for (i = 0; i < FIFO_DEPTH; i = i + 1)
            error_or = error_or | fifo[i];
    end
    assign error_bit = |error_or;

    always @(posedge clk) begin
        if (wb_rst_i)
            overrun <= 1'b0;
        else if (fifo_reset | reset_status)
            overrun <= 1'b0;
        else if (push & ~pop & (count == FIFO_DEPTH))
            overrun <= 1'b1;
    end

endmodule
