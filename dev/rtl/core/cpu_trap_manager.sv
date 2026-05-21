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

    input         exe_misalign_valid,
    input  [31:0] exe_misalign_target,
    input  [31:0] exe_pc,

    input         inst_access_fault,
    input  [31:0] inst_access_fault_addr,
    input         load_access_fault,
    input  [31:0] load_access_fault_addr,
    input         store_access_fault,
    input  [31:0] store_access_fault_addr,
    input  [31:0] mem_access_fault_pc,

    output        exception_at_decode,
    output        trap_pending,
    output [31:0] trap_pc,

    output        hw_csr_wen,
    output [31:0] hw_mepc_wdata,
    output [31:0] hw_mcause_wdata,
    output [31:0] hw_mtval_wdata,
    output [31:0] hw_mstatus_wdata,

    output        inst_access_fault_pending,
    output        data_access_fault_pending
);

    assign exception_at_decode = (id_valid && id_done) && (dec_illegal || dec_is_ecall || dec_is_ebreak) && !inst_access_fault_r;

    wire [31:0] decode_exception_cause;
    assign decode_exception_cause = dec_illegal  ? 32'd2 :
                                    dec_is_ecall ? 32'd11 :
                                                   32'd3;

    wire [31:0] decode_exception_mtval;
    assign decode_exception_mtval = dec_illegal ? id_inst : 32'b0;

    reg inst_access_fault_r;
    reg [31:0] inst_access_fault_addr_r;
    reg load_access_fault_r;
    reg [31:0] load_access_fault_addr_r;
    reg store_access_fault_r;
    reg [31:0] store_access_fault_addr_r;
    reg [31:0] mem_access_fault_pc_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            inst_access_fault_r      <= 1'b0;
            inst_access_fault_addr_r <= 32'b0;
            load_access_fault_r      <= 1'b0;
            load_access_fault_addr_r <= 32'b0;
            store_access_fault_r     <= 1'b0;
            store_access_fault_addr_r<= 32'b0;
            mem_access_fault_pc_r    <= 32'b0;
        end else begin
            if (inst_access_fault && !inst_access_fault_r) begin
                inst_access_fault_r      <= 1'b1;
                inst_access_fault_addr_r <= inst_access_fault_addr;
            end
            if (load_access_fault && !load_access_fault_r && !store_access_fault_r) begin
                load_access_fault_r      <= 1'b1;
                load_access_fault_addr_r <= load_access_fault_addr;
                mem_access_fault_pc_r    <= mem_access_fault_pc;
            end
            if (store_access_fault && !store_access_fault_r && !load_access_fault_r) begin
                store_access_fault_r     <= 1'b1;
                store_access_fault_addr_r<= store_access_fault_addr;
                mem_access_fault_pc_r    <= mem_access_fault_pc;
            end
            if (trap_enter_valid || trap_return_valid) begin
                inst_access_fault_r  <= 1'b0;
                load_access_fault_r  <= 1'b0;
                store_access_fault_r <= 1'b0;
            end
        end
    end

    assign inst_access_fault_pending = inst_access_fault_r;
    assign data_access_fault_pending = load_access_fault_r || store_access_fault_r;

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

    wire exe_exception_valid;
    wire [31:0] exe_exception_cause;
    wire [31:0] exe_exception_pc;
    wire [31:0] exe_exception_mtval;

    assign exe_exception_valid = exe_misalign_valid;
    assign exe_exception_cause = 32'd0;
    assign exe_exception_pc    = exe_pc;
    assign exe_exception_mtval = exe_misalign_target;

    wire exception_valid;
    wire [31:0] exception_cause;
    wire [31:0] exception_pc;
    wire [31:0] exception_mtval;

    wire access_fault_valid;
    wire [31:0] access_fault_cause;
    wire [31:0] access_fault_pc;
    wire [31:0] access_fault_mtval;

    assign access_fault_valid = inst_access_fault_r || load_access_fault_r || store_access_fault_r;
    assign access_fault_cause = inst_access_fault_r ? 32'd1 :
                                load_access_fault_r ? 32'd5 :
                                                       32'd7;
    assign access_fault_pc   = inst_access_fault_r ? inst_access_fault_addr_r :
                                mem_access_fault_pc_r;
    assign access_fault_mtval = inst_access_fault_r ? inst_access_fault_addr_r :
                                load_access_fault_r ? load_access_fault_addr_r :
                                                       store_access_fault_addr_r;

    assign exception_valid = access_fault_valid || exception_at_decode || misalign_exception_valid || exe_exception_valid;
    assign exception_cause = access_fault_valid   ? access_fault_cause :
                             exception_at_decode  ? decode_exception_cause :
                             misalign_exception_valid ? misalign_exception_cause :
                             exe_exception_cause;
    assign exception_pc   = access_fault_valid   ? access_fault_pc :
                            exception_at_decode  ? id_pc :
                            misalign_exception_valid ? misalign_exception_pc :
                            exe_exception_pc;
    assign exception_mtval= access_fault_valid   ? access_fault_mtval :
                            exception_at_decode  ? decode_exception_mtval :
                            misalign_exception_valid ? misalign_exception_mtval :
                            exe_exception_mtval;

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
