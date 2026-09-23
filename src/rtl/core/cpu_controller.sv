`timescale 1ns / 1ps
`include "core_bus_types.svh"

module cpu_controller(
    input        clk,
    input        resetn,
    input        if_done,
    input        id_done,
    input        exe_done,
    input        mem_done,
    input        wb_done,
    input        dec_need_exe,
    input        dec_is_csr,
    input        dec_is_mret,
    input        dec_is_sret,
    input        dec_is_nop_like,
    input        dec_is_fencei,
    input        dec_is_sfence_vma,
    input        exe_is_branch,
    input        exe_need_mem,
    input        sync_exception_pending,
    input        interrupt_pending,
    input        init_sig,
    output       if_valid,
    output       id_valid,
    output       exe_valid,
    output       mem_valid,
    output       wb_valid,
    output       csr_valid,
    output       trap_enter_valid,
    output       trap_return_valid,
    output trap_return_kind_t trap_return_kind,
    output       exe_to_wb,
    output       fencei_req,
    input        fencei_done,
    output       sfence_vma_req,
    input        sfence_vma_done,

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
    localparam STATE_FENCEI     = 4'd9;
    localparam STATE_SFENCE_VMA = 4'd10;
    localparam STATE_RETURN_BOUNDARY = 4'd11;

    reg [3:0] state_r;
    reg [3:0] next_state;
    trap_return_kind_t trap_return_kind_r;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state_r <= STATE_IDLE;
            trap_return_kind_r <= RET_NONE;
        end else begin
            state_r <= next_state;
            if (init_sig)
                trap_return_kind_r <= RET_NONE;
            else if ((state_r == STATE_DECODE) && id_done) begin
                if (dec_is_mret)
                    trap_return_kind_r <= RET_M;
                else if (dec_is_sret)
                    trap_return_kind_r <= RET_S;
            end
        end
    end

    always_comb begin
        next_state = state_r;
        if (init_sig) begin
            next_state = STATE_IDLE;
        end else begin
            case (state_r)
                STATE_IDLE: begin
                    next_state = STATE_FETCH;
                end
                STATE_FETCH: begin
                    if (sync_exception_pending) begin
                        next_state = STATE_TRAP_ENTER;
                    end else begin
                        next_state = if_done ? STATE_DECODE : STATE_FETCH;
                    end
                end
                STATE_DECODE: begin
                    if (sync_exception_pending) begin
                        next_state = STATE_TRAP_ENTER;
                    end else if (!id_done) begin
                        next_state = STATE_DECODE;
                    end else if (dec_is_mret || dec_is_sret) begin
                        next_state = STATE_TRAP_RETURN;
                    end else if (dec_is_fencei) begin
                        next_state = STATE_FENCEI;
                    end else if (dec_is_sfence_vma) begin
                        next_state = STATE_SFENCE_VMA;
                    end else if (dec_is_nop_like) begin
                        next_state = interrupt_pending ? STATE_TRAP_ENTER : STATE_FETCH;
                    end else if (dec_is_csr) begin
                        next_state = STATE_CSR_ACCESS;
                    end else if (!dec_need_exe) begin
                        next_state = interrupt_pending ? STATE_TRAP_ENTER : STATE_FETCH;
                    end else begin
                        next_state = STATE_EXEC;
                    end
                end
                STATE_EXEC: begin
                    if (sync_exception_pending) begin
                        next_state = STATE_TRAP_ENTER;
                    end else if (!exe_done) begin
                        next_state = STATE_EXEC;
                    end else if (exe_is_branch) begin
                        next_state = interrupt_pending ? STATE_TRAP_ENTER : STATE_FETCH;
                    end else if (exe_need_mem) begin
                        next_state = STATE_MEM;
                    end else begin
                        next_state = STATE_WB;
                    end
                end
                STATE_MEM: begin
                    if (sync_exception_pending) begin
                        next_state = STATE_TRAP_ENTER;
                    end else begin
                        next_state = mem_done ? STATE_WB : STATE_MEM;
                    end
                end
                STATE_WB: begin
                    if (wb_done) begin
                        next_state = interrupt_pending ? STATE_TRAP_ENTER : STATE_FETCH;
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
                    next_state = STATE_RETURN_BOUNDARY;
                end
                STATE_RETURN_BOUNDARY: begin
                    next_state = interrupt_pending ? STATE_TRAP_ENTER : STATE_FETCH;
                end
                STATE_FENCEI: begin
                    if (fencei_done) begin
                        next_state = interrupt_pending ? STATE_TRAP_ENTER : STATE_FETCH;
                    end else begin
                        next_state = STATE_FENCEI;
                    end
                end
                STATE_SFENCE_VMA: begin
                    if (sfence_vma_done) begin
                        next_state = interrupt_pending ? STATE_TRAP_ENTER : STATE_FETCH;
                    end else begin
                        next_state = STATE_SFENCE_VMA;
                    end
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
    assign trap_return_kind = trap_return_valid ? trap_return_kind_r : RET_NONE;
    assign exe_to_wb        = (state_r == STATE_EXEC) && exe_done && !exe_is_branch && !exe_need_mem && !init_sig;
    assign fencei_req       = (state_r == STATE_FENCEI) && !init_sig;
    assign sfence_vma_req   = (state_r == STATE_SFENCE_VMA) && !init_sig;
    assign state = state_r;

endmodule
