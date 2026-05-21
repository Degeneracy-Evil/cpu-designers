`timescale 1ns / 1ps
// tree_PLRU状态转换
module tree_plru(
    input  wire [2:0] plru_state,
    output wire [1:0] victim_way,
    input  wire [1:0] access_way,
    output wire [2:0] next_state
);

    assign victim_way[1] = plru_state[0];
    assign victim_way[0] = plru_state[0] ? plru_state[2] : plru_state[1];

    reg [2:0] next_state_r;
    assign next_state = next_state_r;

    always @(*) begin
        case (access_way)
            2'd0: next_state_r = {1'b1, 1'b1, plru_state[2]};
            2'd1: next_state_r = {1'b1, 1'b0, plru_state[2]};
            2'd2: next_state_r = {1'b0, plru_state[1], 1'b1};
            2'd3: next_state_r = {1'b0, plru_state[1], 1'b0};
            default: next_state_r = plru_state;
        endcase
    end

endmodule
