// 2-stage synchronizer for async inputs
// Adapted from chiplab IP/APB_DEV/URT/uart_sync_flops.v

module uart_sync_flops #(
    parameter WIDTH      = 1,
    parameter INIT_VALUE = 1'b0
)(
    input  wire              rst_i,
    input  wire              clk_i,
    input  wire              stage1_rst_i,
    input  wire              stage1_clk_en_i,
    input  wire [WIDTH-1:0]  async_dat_i,
    output reg  [WIDTH-1:0]  sync_dat_o
);

    reg [WIDTH-1:0] flop_0;

    always @(posedge clk_i) begin
        if (rst_i)
            flop_0 <= {WIDTH{INIT_VALUE}};
        else
            flop_0 <= async_dat_i;
    end

    always @(posedge clk_i) begin
        if (rst_i)
            sync_dat_o <= {WIDTH{INIT_VALUE}};
        else if (stage1_rst_i)
            sync_dat_o <= {WIDTH{INIT_VALUE}};
        else if (stage1_clk_en_i)
            sync_dat_o <= flop_0;
    end

endmodule
