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
    input        dec_is_csr,
    input        dec_is_ecall,
    input        dec_is_ebreak,
    input        dec_is_mret,
    input        dec_is_fence,
    input        exe_is_branch,
    input        trap_pending,
    input        exception_at_decode,
    input        init_sig,
    output       if_valid,
    output       id_valid,
    output       exe_valid,
    output       mem_valid,
    output       wb_valid,
    output       csr_valid,
    output       trap_enter_valid,
    output       trap_return_valid,

    output [3:0] state
);
    localparam STATE_IDLE       = 4'd0;
    localparam STATE_FETCH      = 4'd1;
    localparam STATE_DECODE     = 4'd2;
    localparam STATE_EXEC       = 4'd3;
    localparam STATE_MEM        = 4'd4;
    localparam STATE_WB         = 4'd5;
    localparam STATE_CSR_ACCESS = 4'd6;
    localparam STATE_TRAP_ENTER = 4'd7;
    localparam STATE_TRAP_RETURN= 4'd8;

    reg [3:0] state_r;
    reg [3:0] next_state;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_r <= STATE_IDLE;
        end else begin
            state_r <= next_state;
        end
    end

    always @(*) begin
        if (init_sig) begin
            next_state = STATE_IDLE;
        end else begin
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
                    end else if (exception_at_decode) begin
                        next_state = STATE_TRAP_ENTER;
                    end else if (dec_is_mret) begin
                        next_state = STATE_TRAP_RETURN;
                    end else if (dec_is_fence) begin
                        next_state = STATE_FETCH;
                    end else if (dec_is_csr) begin
                        next_state = STATE_CSR_ACCESS;
                    end else if (!dec_need_exe) begin
                        next_state = STATE_FETCH;
                    end else begin
                        next_state = STATE_EXEC;
                    end
                end
                STATE_EXEC: begin
                    if (!exe_done) begin
                        next_state = STATE_EXEC;
                    end else if (exe_is_branch) begin
                        next_state = trap_pending ? STATE_TRAP_ENTER : STATE_FETCH;
                    end else begin
                        next_state = STATE_MEM;
                    end
                end
                STATE_MEM: begin
                    next_state = mem_done ? STATE_WB : STATE_MEM;
                end
                STATE_WB: begin
                    if (wb_done) begin
                        next_state = trap_pending ? STATE_TRAP_ENTER : STATE_FETCH;
                    end else begin
                        next_state = STATE_WB;
                    end
                end
                STATE_CSR_ACCESS: begin
                    next_state = STATE_WB;
                end
                STATE_TRAP_ENTER: begin
                    next_state = STATE_FETCH;
                end
                STATE_TRAP_RETURN: begin
                    next_state = STATE_FETCH;
                end
                default: begin
                    next_state = STATE_IDLE;
                end
            endcase
        end
    end

    assign if_valid         = (state_r == STATE_FETCH) && !init_sig;
    assign id_valid         = (state_r == STATE_DECODE) && !init_sig;
    assign exe_valid        = (state_r == STATE_EXEC) && !init_sig;
    assign mem_valid        = (state_r == STATE_MEM) && !init_sig;
    assign wb_valid         = (state_r == STATE_WB) && !init_sig;
    assign csr_valid        = (state_r == STATE_CSR_ACCESS) && !init_sig;
    assign trap_enter_valid = (state_r == STATE_TRAP_ENTER) && !init_sig;
    assign trap_return_valid= (state_r == STATE_TRAP_RETURN) && !init_sig;
    assign state = state_r;

endmodule
