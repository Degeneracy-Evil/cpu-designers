`timescale 1ns / 1ps

module cpu_controller(
    input        clk,
    input        reset,
    input        if_done,
    input        id_done,
    input        exe_done,
    input        mem_done,
    input        wb_done,
    input        dec_is_branch,
    input        dec_need_exe,
    input        dec_illegal,
    input        exe_is_branch,
    output       if_valid,
    output       id_valid,
    output       exe_valid,
    output       mem_valid,
    output       wb_valid,

    output [2:0] state
);
    localparam STATE_IDLE   = 3'd0;
    localparam STATE_FETCH  = 3'd1;
    localparam STATE_DECODE = 3'd2;
    localparam STATE_EXEC   = 3'd3;
    localparam STATE_MEM    = 3'd4;
    localparam STATE_WB     = 3'd5;

    reg [2:0] state_r;
    reg [2:0] next_state;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_r <= STATE_IDLE;
        end else begin
            state_r <= next_state;
        end
    end

    always @(*) begin
        case (state_r)
            STATE_IDLE: begin
                next_state = STATE_FETCH;
            end
            STATE_FETCH: begin
                next_state = if_done ? STATE_DECODE : STATE_FETCH;
            end
            STATE_DECODE: begin
                if (!id_done) begin
                    next_state = STATE_DECODE;
                end else if (dec_illegal) begin
                    next_state = STATE_FETCH;
                end else if (dec_need_exe) begin
                    next_state = STATE_EXEC;
                end else begin
                    next_state = STATE_FETCH;
                end
            end
            STATE_EXEC: begin
                if (!exe_done) begin
                    next_state = STATE_EXEC;
                end else if (exe_is_branch) begin
                    next_state = STATE_FETCH;
                end else begin
                    next_state = STATE_MEM;
                end
            end
            STATE_MEM: begin
                next_state = mem_done ? STATE_WB : STATE_MEM;
            end
            STATE_WB: begin
                next_state = wb_done ? STATE_FETCH : STATE_WB;
            end
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

    assign if_valid = (state_r == STATE_FETCH);
    assign id_valid = (state_r == STATE_DECODE);
    assign exe_valid = (state_r == STATE_EXEC);
    assign mem_valid = (state_r == STATE_MEM);
    assign wb_valid = (state_r == STATE_WB);
    assign state = state_r;

endmodule
