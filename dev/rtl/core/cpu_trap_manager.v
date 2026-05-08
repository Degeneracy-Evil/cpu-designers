`timescale 1ns / 1ps

module cpu_trap_manager(
    input         clk,
    input         reset,

    input         id_valid,
    input         id_done,
    input         dec_illegal,
    input         dec_is_ecall,
    input         dec_is_ebreak,
    input  [31:0] id_pc,
    input  [31:0] id_inst,

    input         mem_valid,
    input         mem_done,
    input         mem_misalign_load,
    input         mem_misalign_store,
    input  [31:0] mem_misalign_addr,
    input  [31:0] mem_pc,

    input         trap_enter_valid,
    input         trap_return_valid,

    input  [31:0] csr_mstatus,
    input  [31:0] csr_mie,
    input  [31:0] csr_mtvec,
    input  [31:0] csr_mepc,
    input  [31:0] csr_mip,

    input         timer_irq,
    input  [31:0] current_pc,

    output        exception_at_decode,
    output        trap_pending,
    output [31:0] trap_pc,

    output        hw_csr_wen,
    output [31:0] hw_mepc_wdata,
    output [31:0] hw_mcause_wdata,
    output [31:0] hw_mtval_wdata,
    output [31:0] hw_mstatus_wdata
);

    assign exception_at_decode = (id_valid && id_done) && (dec_illegal || dec_is_ecall || dec_is_ebreak);

    wire [31:0] decode_exception_cause;
    assign decode_exception_cause = dec_illegal  ? 32'd2 :
                                    dec_is_ecall ? 32'd11 :
                                                   32'd3;

    wire [31:0] decode_exception_mtval;
    assign decode_exception_mtval = dec_illegal ? id_inst : 32'b0;

    reg exception_valid_r;
    reg [31:0] exception_cause_r;
    reg [31:0] exception_pc_r;
    reg [31:0] exception_mtval_r;

    wire misalign_exception_valid;
    wire [31:0] misalign_exception_cause;
    wire [31:0] misalign_exception_pc;
    wire [31:0] misalign_exception_mtval;

    assign misalign_exception_valid = mem_valid && mem_done && (mem_misalign_load || mem_misalign_store);
    assign misalign_exception_cause = mem_misalign_load ? 32'd4 : 32'd6;
    assign misalign_exception_pc    = mem_pc;
    assign misalign_exception_mtval = mem_misalign_addr;

    wire exception_valid;
    wire [31:0] exception_cause;
    wire [31:0] exception_pc;
    wire [31:0] exception_mtval;

    assign exception_valid = exception_at_decode || misalign_exception_valid;
    assign exception_cause = exception_at_decode ? decode_exception_cause : misalign_exception_cause;
    assign exception_pc   = exception_at_decode ? id_pc : misalign_exception_pc;
    assign exception_mtval= exception_at_decode ? decode_exception_mtval : misalign_exception_mtval;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            exception_valid_r <= 1'b0;
            exception_cause_r <= 32'b0;
            exception_pc_r    <= 32'b0;
            exception_mtval_r <= 32'b0;
        end else begin
            if (exception_valid) begin
                exception_valid_r <= 1'b1;
                exception_cause_r <= exception_cause;
                exception_pc_r    <= exception_pc;
                exception_mtval_r <= exception_mtval;
            end else if (trap_enter_valid || trap_return_valid) begin
                exception_valid_r <= 1'b0;
            end
        end
    end

    wire clint_trap_enter;
    wire [31:0] clint_trap_pc;

    assign trap_pending = clint_trap_enter && !exception_valid_r;
    assign trap_pc = clint_trap_pc;

    cpu_clint u_clint(
        .clk(clk),
        .reset(reset),
        .exception_valid(exception_valid_r),
        .exception_cause(exception_cause_r),
        .exception_pc(exception_pc_r),
        .exception_mtval(exception_mtval_r),
        .mret_req(trap_return_valid),
        .trap_enter_valid(trap_enter_valid),
        .interrupt_pc(current_pc),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mtvec(csr_mtvec),
        .csr_mepc(csr_mepc),
        .csr_mip(csr_mip),
        .ext_mtip(timer_irq),
        .trap_enter(clint_trap_enter),
        .trap_return(),
        .trap_pc(clint_trap_pc),
        .hw_csr_wen(hw_csr_wen),
        .hw_mepc_wdata(hw_mepc_wdata),
        .hw_mcause_wdata(hw_mcause_wdata),
        .hw_mtval_wdata(hw_mtval_wdata),
        .hw_mstatus_wdata(hw_mstatus_wdata)
    );

endmodule
