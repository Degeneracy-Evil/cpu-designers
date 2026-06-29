`timescale 1ns / 1ps
`include "core_bus_types.svh"

module cpu_execute(
    input              clk,
    input              resetn,
    input              exe_valid,
    input      [350:0] id_exe_bus_r,
    input      [31:0]  csr_rdata,
    input      [2:0]   csr_frm,        // CSR frm for DYN rounding mode
    input      [63:0]  frs1_value,     // float register rs1 value (64-bit regfile, lower 32 used by F)
    input      [63:0]  frs2_value,     // float register rs2 value (64-bit regfile, lower 32 used by F)
    input      [63:0]  frs3_value,     // float register rs3 value (FMA, 64-bit regfile, lower 32 used by F)
    input              trap_pending,   // BUG-16: flush MU/FPU on pending trap
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
    wire        is_fpu;
    wire        is_flw;
    wire        is_fsw;
    wire        is_fld;
    wire        is_fsd;
    wire [6:0]  fpu_funct;
    wire [2:0]  fpu_rm;
    wire        fpu_rd_is_int;
    // A extension signals
    wire        is_amo;
    wire        is_lr;
    wire        is_sc;
    wire [4:0]  amo_funct5;
    wire        amo_aq;
    wire        amo_rl;
    wire [4:0]  rs3_addr;      // FMA rs3 address

    assign {
        is_fld,
        is_fsd,
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
        is_fpu,
        is_flw,
        is_fsw,
        fpu_funct,
        fpu_rm,
        fpu_rd_is_int,
        // A extension
        is_amo,
        is_lr,
        is_sc,
        amo_funct5,
        amo_aq,
        amo_rl,
        // FMA rs3
        rs3_addr
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

    // BUG-16: flush MU/FPU when trap is pending and either is active
    wire exe_flush = trap_pending && (mu_active || fpu_active);

    mu_unit u_mu(
        .clk(clk),
        .resetn(resetn),
        .mu_funct3(mu_funct3),
        .src1(alu_src1),
        .src2(alu_src2),
        .req_valid(mu_req_valid),
        .flush(exe_flush),
        .result_got(mu_result_got),
        .result(mu_result),
        .mu_busy(mu_busy),
        .mu_ready(mu_ready),
        .result_valid(mu_result_valid),
        .div_by_zero(mu_div_by_zero)
    );

    // ===================================================================
    // FPU unit (mirrors MU handshake pattern)
    // ===================================================================
    wire [63:0] fpu_result;
    wire        fpu_busy_w;
    wire        fpu_ready_w;
    wire        fpu_result_valid;
    wire [4:0]  fpu_fflags;
    wire        fpu_rd_is_int_result;
    wire        fpu_error_w;

    reg fpu_req_valid;
    reg fpu_result_got;
    reg fpu_active;

    // Resolve DYN rounding mode: if rm==3'b111, use CSR frm
    wire [2:0] fpu_rm_resolved = (fpu_rm == 3'b111) ? csr_frm : fpu_rm;

    // Int→float instructions read integer rs1 instead of float frs1.
    //   F: 15=FMV.W.X, 18=FCVT.S.W, 19=FCVT.S.WU
    //   D: 40=FCVT.D.W, 41=FCVT.D.WU
    wire fpu_src_is_int = (fpu_funct == 7'd15) ||  // FMV.W.X
                          (fpu_funct == 7'd18) ||  // FCVT.S.W
                          (fpu_funct == 7'd19) ||  // FCVT.S.WU
                          (fpu_funct == 7'd40) ||  // FCVT.D.W
                          (fpu_funct == 7'd41);    // FCVT.D.WU

    // D operation? (fpu_funct 24..43 are D arithmetic ops; 44/45 are FLD/FSD
    // handled by LSU and never reach the FPU). D ops need NaN-box-checked
    // operands; F ops read the raw lower 32 bits regardless of upper bits.
    wire fpu_is_d_op = (fpu_funct >= 7'd24) && (fpu_funct <= 7'd43);

    // ===================================================================
    // NaN-box check for D operations (Task 13 wiring — Task 23 dispatch)
    //   Per RISC-V NaN-boxing spec (IS §22): when a D operation reads a
    //   64-bit FP register, the upper 32 bits must be all 1s. If not, the
    //   value is not a valid NaN-boxed float and is treated as a canonical
    //   NaN (F=0x7fc00000, D=0x7ff8000000000000).
    //   F operations always read the lower 32 bits regardless of upper
    //   bits, so the F path is unaffected.
    // ===================================================================
    wire nanobox_valid_src1 = (frs1_value[63:32] == 32'hFFFFFFFF);
    wire nanobox_valid_src2 = (frs2_value[63:32] == 32'hFFFFFFFF);
    wire nanobox_valid_src3 = (frs3_value[63:32] == 32'hFFFFFFFF);
    // Canonical NaN-boxed values: upper=0xFFFFFFFF, lower=canonical NaN
    //   F canonical NaN: 0x7fc00000
    //   D canonical NaN: 0x7ff8000000000000 (NaN-boxed: 0xFFFFFFFF7ff80000)
    wire [63:0] src1_d_checked = nanobox_valid_src1 ? frs1_value :
                                                     {32'hFFFFFFFF, 32'h7fc00000};
    wire [63:0] src2_d_checked = nanobox_valid_src2 ? frs2_value :
                                                     {32'hFFFFFFFF, 32'h7fc00000};
    wire [63:0] src3_d_checked = nanobox_valid_src3 ? frs3_value :
                                                     {32'hFFFFFFFF, 32'h7fc00000};

    // src1 mux:
    //   int→float ops: integer rs1 zero-extended to 64 bits
    //   D ops: NaN-box-checked 64-bit FP register value
    //   F ops: raw 64-bit FP register value (FPU uses lower 32 bits)
    wire [63:0] fpu_src1_mux = fpu_src_is_int ? {32'b0, rs1_value} :
                              fpu_is_d_op    ? src1_d_checked :
                                               frs1_value;
    // src2/src3 mux: D ops use NaN-box-checked value; F ops use raw value
    wire [63:0] fpu_src2_mux = fpu_is_d_op ? src2_d_checked : frs2_value;
    wire [63:0] fpu_src3_mux = fpu_is_d_op ? src3_d_checked : frs3_value;

    fpu_unit u_fpu(
        .clk(clk),
        .resetn(resetn),
        .fpu_funct(fpu_funct),
        .fpu_rm(fpu_rm_resolved),
        .src1(fpu_src1_mux),
        .src2(fpu_src2_mux),
        .src3(fpu_src3_mux),            // rs3 for FMA instructions
        .req_valid(fpu_req_valid),
        .flush(exe_flush),
        .result_got(fpu_result_got),
        .result(fpu_result),
        .fpu_busy(fpu_busy_w),
        .fpu_ready(fpu_ready_w),
        .result_valid(fpu_result_valid),
        .fflags(fpu_fflags),
        .rd_is_int(fpu_rd_is_int_result),
        .fpu_error(fpu_error_w)
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
            fpu_req_valid <= 1'b0;
            fpu_result_got <= 1'b0;
            fpu_active <= 1'b0;
            exe_seen_valid <= 1'b0;
            result_reg <= 32'b0;
            result_ok <= 1'b0;
            done_reg <= 1'b0;
            branch_target_reg <= 32'b0;
            branch_taken_reg <= 1'b0;
        end else begin
            done_reg <= 1'b0;
            mu_result_got <= 1'b0;
            fpu_result_got <= 1'b0;

            if (!exe_valid) begin
                exe_seen_valid <= 1'b0;
            end

            if (!mu_active && !fpu_active && exe_valid && !exe_seen_valid) begin
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
                end else if (is_fpu) begin
                    fpu_req_valid <= 1'b1;
                    fpu_active <= 1'b1;
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

            if (fpu_active) begin
                if (fpu_req_valid && fpu_ready_w) begin
                    fpu_req_valid <= 1'b0;
                end
                if (fpu_result_valid) begin
                    fpu_result_got <= 1'b1;
                    // fpu_result is 64-bit (NaN-boxed F or full D). result_reg
                    // is 32-bit; lower 32 bits hold the F result. Full 64-bit
                    // D writeback is handled by cpu_wb.sv (Task 26).
                    result_reg <= fpu_result[31:0];
                    result_ok <= valid_inst & ~fpu_error_w;  // suppress WB on FPU error
                    done_reg <= 1'b1;
                    fpu_active <= 1'b0;
                    fpu_req_valid <= 1'b0;
                    branch_target_reg <= 32'b0;
                    branch_taken_reg <= 1'b0;
                end
            end

            // BUG-16: flush MU/FPU when trap is pending — clear active flags,
            // signal done with result_ok=0 (suppress WB), unblock controller FSM
            if (exe_flush) begin
                mu_active     <= 1'b0;
                fpu_active    <= 1'b0;
                mu_req_valid  <= 1'b0;
                fpu_req_valid <= 1'b0;
                done_reg      <= 1'b1;   // unblock STATE_EXEC
                result_ok     <= 1'b0;   // suppress write-back
                result_reg    <= 32'b0;
                branch_target_reg <= 32'b0;
                branch_taken_reg  <= 1'b0;
            end
        end
    end

    wire [31:0] csr_new_val;
    wire [4:0]  csr_rs1;
    assign csr_rs1 = inst[19:15];

    assign csr_new_val = (csr_funct3 == 3'b001) ? rs1_value :
                         (csr_funct3 == 3'b010) ? (csr_rdata | rs1_value) :
                         (csr_funct3 == 3'b011) ? (csr_rdata & ~rs1_value) :
                         (csr_funct3 == 3'b101) ? {27'b0, csr_uimm} :
                         (csr_funct3 == 3'b110) ? (csr_rdata | {27'b0, csr_uimm}) :
                         (csr_funct3 == 3'b111) ? (csr_rdata & ~{27'b0, csr_uimm}) :
                         csr_rdata;

    wire csr_no_write;
    assign csr_no_write = ((csr_funct3 == 3'b010 || csr_funct3 == 3'b011) && (csr_rs1 == 5'd0)) ||
                          ((csr_funct3 == 3'b110 || csr_funct3 == 3'b111) && (csr_uimm == 5'd0));

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
    assign exe_need_mem  = is_load | is_store | is_flw | is_fsw | is_fld | is_fsd | is_amo;

    assign exe_csr_wen    = is_csr && !csr_no_write;
    assign exe_csr_waddr  = csr_addr;
    assign exe_csr_wdata  = csr_new_val;
    assign exe_csr_old_val = csr_rdata;

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
        is_fpu:        is_fpu,
        is_flw:        is_flw,
        is_fsw:        is_fsw,
        fpu_rd_is_int: fpu_rd_is_int,
        fpu_fflags:    fpu_fflags,
        is_amo:        is_amo,
        is_lr:         is_lr,
        is_sc:         is_sc,
        amo_funct5:    amo_funct5,
        amo_aq:        amo_aq,
        amo_rl:        amo_rl,
        is_fld:        is_fld,
        is_fsd:        is_fsd
    };

    assign exe_pc = pc;
    assign exe_inst = inst;

endmodule
