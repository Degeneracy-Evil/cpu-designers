`timescale 1ns / 1ps
`include "core_bus_types.svh"

module cpu_execute(
    input              clk,
    input              resetn,
    input              exe_valid,
    input      [329:0] id_exe_bus_r,
    input      [31:0]  csr_rdata,
    output             exe_done,
    output     exe_mem_bus_t exe_mem_bus,
    output             exe_branch_taken,
    output     [31:0]  exe_branch_target,
    output             exe_is_ctrl_flow,
    output             exe_is_branch,
    output             exe_need_mem,

    output     [31:0]  exe_pc,
    output     [31:0]  exe_inst,

    output             exe_misalign_valid,
    output     [31:0]  exe_misalign_target,

    output             exe_csr_wen,
    output     [11:0]  exe_csr_waddr,
    output     [31:0]  exe_csr_wdata,
    output     [31:0]  exe_csr_old_val,
    output             dbg_mu_active,
    output             dbg_mu_req_valid,
    output             dbg_mu_ready,
    output             dbg_mu_busy,
    output             dbg_mu_result_valid,
    output     [2:0]   dbg_mu_funct3,
    output             dbg_exe_is_mu
);

    wire valid_inst;
    wire is_alu;
    wire is_load;
    wire is_store;
    wire is_jal_like;
    wire is_branch;
    wire use_fixed_wb;
    wire wb_we;
    wire [4:0] wb_rd;
    wire [31:0] wb_fixed_data;
    wire [2:0] mem_size;
    wire mem_unsigned;
    wire [15:0] alu_control;
    wire [31:0] alu_src1;
    wire [31:0] alu_src2;
    wire [31:0] rs1_value;
    wire [31:0] rs2_value;
    wire [2:0]  branch_funct3;
    wire is_csr;
    wire is_ecall;
    wire is_ebreak;
    wire is_mret;
    wire is_mu;
    wire [2:0]  mu_funct3;
    wire [11:0] csr_addr;
    wire [2:0]  csr_funct3;
    wire [4:0]  csr_uimm;
    wire [31:0] pc_plus4;
    wire [31:0] pc;
    wire [31:0] inst;
    // A extension signals
    wire        is_amo;
    wire        is_lr;
    wire        is_sc;
    wire [4:0]  amo_funct5;
    wire        amo_aq;
    wire        amo_rl;

    assign {
        pc_plus4,
        valid_inst,
        is_alu,
        is_load,
        is_store,
        is_jal_like,
        is_branch,
        use_fixed_wb,
        wb_we,
        wb_rd,
        wb_fixed_data,
        mem_size,
        mem_unsigned,
        alu_control,
        is_mu,
        mu_funct3,
        alu_src1,
        alu_src2,
        rs1_value,
        rs2_value,
        branch_funct3,
        is_csr,
        is_ecall,
        is_ebreak,
        is_mret,
        csr_addr,
        csr_funct3,
        csr_uimm,
        pc,
        inst,
        // A extension
        is_amo,
        is_lr,
        is_sc,
        amo_funct5,
        amo_aq,
        amo_rl
    } = id_exe_bus_r;

    wire is_jalr;
    assign is_jalr = (inst[6:0] == 7'b1100111) && (inst[14:12] == 3'b000);

    wire branch_cond_true;
    branch_comparator u_cmp(
        .rs1_value(rs1_value),
        .rs2_value(rs2_value),
        .branch_funct3(branch_funct3),
        .branch_cond_true(branch_cond_true)
    );

    wire [31:0] alu_result;

    alu_32bit u_alu(
        .alu_control(alu_control),
        .src1(alu_src1),
        .src2(alu_src2),
        .result(alu_result)
    );

    wire [31:0] mu_result;
    wire        mu_busy;
    wire        mu_ready;
    wire        mu_result_valid;
    wire        mu_div_by_zero;

    reg mu_req_valid;
    reg mu_result_got;
    reg mu_active;

    mu_unit u_mu(
        .clk(clk),
        .resetn(resetn),
        .mu_funct3(mu_funct3),
        .src1(alu_src1),
        .src2(alu_src2),
        .req_valid(mu_req_valid),
        .result_got(mu_result_got),
        .result(mu_result),
        .mu_busy(mu_busy),
        .mu_ready(mu_ready),
        .result_valid(mu_result_valid),
        .div_by_zero(mu_div_by_zero)
    );

    reg [31:0] result_reg;
    reg        result_ok;
    reg        done_reg;
    reg [31:0] branch_target_reg;
    reg        branch_taken_reg;
    reg        exe_seen_valid;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            mu_req_valid <= 1'b0;
            mu_result_got <= 1'b0;
            mu_active <= 1'b0;
            exe_seen_valid <= 1'b0;
            result_reg <= 32'b0;
            result_ok <= 1'b0;
            done_reg <= 1'b0;
            branch_target_reg <= 32'b0;
            branch_taken_reg <= 1'b0;
        end else begin
            done_reg <= 1'b0;
            mu_result_got <= 1'b0;

            if (!exe_valid) begin
                exe_seen_valid <= 1'b0;
            end

            if (!mu_active && exe_valid && !exe_seen_valid) begin
                exe_seen_valid <= 1'b1;
                if (use_fixed_wb) begin
                    result_reg <= wb_fixed_data;
                    result_ok <= valid_inst;
                    done_reg <= 1'b1;
                    branch_target_reg <= 32'b0;
                    branch_taken_reg <= 1'b0;
                end else if (is_mu) begin
                    mu_req_valid <= 1'b1;
                    mu_active <= 1'b1;
                end else begin
                    result_reg <= alu_result;
                    result_ok <= valid_inst;
                    done_reg <= 1'b1;
                    branch_target_reg <= is_jalr ? (alu_result & 32'hffff_fffe) : alu_result;
                    branch_taken_reg <= is_branch ? branch_cond_true : is_jal_like;
                end
            end

            if (mu_active) begin
                if (mu_req_valid && mu_ready) begin
                    mu_req_valid <= 1'b0;
                end
                if (mu_result_valid) begin
                    mu_result_got <= 1'b1;
                    result_reg <= mu_result;
                    result_ok <= valid_inst;
                    done_reg <= 1'b1;
                    mu_active <= 1'b0;
                    mu_req_valid <= 1'b0;
                    // MU 指令 (MUL/DIV) 不是分支/JAL，无需设置 branch 信号
                    branch_target_reg <= 32'b0;
                    branch_taken_reg <= 1'b0;
                end
            end

        end
    end

    assign exe_done = done_reg;
    assign exe_branch_taken = branch_taken_reg;
    assign exe_branch_target = branch_target_reg;
    assign dbg_mu_active = mu_active;
    assign dbg_mu_req_valid = mu_req_valid;
    assign dbg_mu_ready = mu_ready;
    assign dbg_mu_busy = mu_busy;
    assign dbg_mu_result_valid = mu_result_valid;
    assign dbg_mu_funct3 = mu_funct3;
    assign dbg_exe_is_mu = is_mu;
    assign exe_is_ctrl_flow = is_branch | is_jal_like;
    assign exe_is_branch = is_branch;
    assign exe_need_mem  = is_load | is_store | is_amo;

    assign exe_misalign_valid = done_reg && exe_is_ctrl_flow && branch_taken_reg && (branch_target_reg[1:0] != 2'b00);
    assign exe_misalign_target = branch_target_reg;

    assign exe_mem_bus = '{
        pc_plus4:      pc_plus4,
        result_ok:     result_ok,
        is_jal_like:   is_jal_like,
        is_load:       is_load,
        is_store:      is_store,
        is_csr:        is_csr,
        wb_we:         wb_we,
        wb_rd:         wb_rd,
        result_reg:    result_reg,
        mem_size:      mem_size,
        mem_unsigned:  mem_unsigned,
        rs2_value:     rs2_value,
        csr_rdata:     csr_rdata,
        pc:            pc,
        inst:          inst,
        is_amo:        is_amo,
        is_lr:         is_lr,
        is_sc:         is_sc,
        amo_funct5:    amo_funct5,
        amo_aq:        amo_aq,
        amo_rl:        amo_rl
    };

    assign exe_pc = pc;
    assign exe_inst = inst;

endmodule
