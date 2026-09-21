`timescale 1ns / 1ps
`include "core_bus_types.svh"

module cpu_trap_manager(
    input         clk,
    input         resetn,

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

    input  priv_mode_t priv_mode,

    input  [31:0] csr_mstatus,
    input  [31:0] csr_mie,
    input  [31:0] csr_mtvec,
    input  [31:0] csr_mepc,
    input  [31:0] csr_mip,
    input  [31:0] csr_medeleg,
    input  [31:0] csr_mideleg,
    input  [31:0] csr_stvec,
    input  [31:0] csr_sepc,
    input  [31:0] current_pc,

    input         exe_misalign_valid,
    input  [31:0] exe_misalign_target,
    input  [31:0] exe_pc,

    input         inst_access_fault,
    input  [31:0] inst_access_fault_pc,
    input  [31:0] inst_access_fault_addr,
    input         load_access_fault,
    input  [31:0] load_access_fault_addr,
    input         store_access_fault,
    input  [31:0] store_access_fault_addr,
    input  [31:0] mem_access_fault_pc,

    input         inst_page_fault,
    input  [31:0] inst_page_fault_pc,
    input  [31:0] inst_page_fault_vaddr,
    input         load_page_fault,
    input  [31:0] load_page_fault_vaddr,
    input         store_page_fault,
    input  [31:0] store_page_fault_vaddr,
    input  [31:0] mem_page_fault_pc,

    output        exception_at_decode,
    output        trap_pending,
    output [31:0] trap_pc,
    output priv_mode_t target_priv,

    output        hw_csr_wen,
    output        hw_trap_is_enter,
    output priv_mode_t hw_target_priv,
    output [31:0] hw_mepc_wdata,
    output [31:0] hw_mcause_wdata,
    output [31:0] hw_mtval_wdata,
    output [31:0] hw_mstatus_wdata,
    output [31:0] hw_sepc_wdata,
    output [31:0] hw_scause_wdata,
    output [31:0] hw_stval_wdata,
    output [31:0] hw_sstatus_wdata,

    output        inst_access_fault_pending,
    output        data_access_fault_pending,

    output        inst_page_fault_pending,
    output        data_page_fault_pending
);
    wire [31:0] decode_exception_cause;
    assign decode_exception_cause = dec_illegal  ? 32'd2 :
                                    dec_is_ecall ? ((priv_mode == PRIV_U) ? 32'd8 :
                                                     (priv_mode == PRIV_S) ? 32'd9 : 32'd11) :
                                                    32'd3;

    wire [31:0] decode_exception_mtval;
    assign decode_exception_mtval = dec_illegal ? id_inst : 32'b0;

    reg inst_access_fault_r;
    reg [31:0] inst_access_fault_pc_r;
    reg [31:0] inst_access_fault_addr_r;
    reg load_access_fault_r;
    reg [31:0] load_access_fault_addr_r;
    reg store_access_fault_r;
    reg [31:0] store_access_fault_addr_r;
    reg [31:0] mem_access_fault_pc_r;

    reg inst_page_fault_r;
    reg [31:0] inst_page_fault_pc_r;
    reg [31:0] inst_page_fault_vaddr_r;
    reg load_page_fault_r;
    reg [31:0] load_page_fault_vaddr_r;
    reg store_page_fault_r;
    reg [31:0] store_page_fault_vaddr_r;
    reg [31:0] mem_page_fault_pc_r;

    assign exception_at_decode = (id_valid && id_done) &&
                                 (dec_illegal || dec_is_ecall || dec_is_ebreak) &&
                                 !inst_access_fault_r && !inst_page_fault_r;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            inst_access_fault_r      <= 1'b0;
            inst_access_fault_pc_r   <= 32'b0;
            inst_access_fault_addr_r <= 32'b0;
            load_access_fault_r      <= 1'b0;
            load_access_fault_addr_r <= 32'b0;
            store_access_fault_r     <= 1'b0;
            store_access_fault_addr_r<= 32'b0;
            mem_access_fault_pc_r    <= 32'b0;
            inst_page_fault_r        <= 1'b0;
            inst_page_fault_pc_r     <= 32'b0;
            inst_page_fault_vaddr_r  <= 32'b0;
            load_page_fault_r        <= 1'b0;
            load_page_fault_vaddr_r  <= 32'b0;
            store_page_fault_r       <= 1'b0;
            store_page_fault_vaddr_r <= 32'b0;
            mem_page_fault_pc_r      <= 32'b0;
        end else begin
            if (inst_access_fault && !inst_access_fault_r) begin
                inst_access_fault_r      <= 1'b1;
                inst_access_fault_pc_r   <= inst_access_fault_pc;
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
            if (inst_page_fault && !inst_page_fault_r) begin
                inst_page_fault_r        <= 1'b1;
                inst_page_fault_pc_r     <= inst_page_fault_pc;
                inst_page_fault_vaddr_r  <= inst_page_fault_vaddr;
            end
            if (load_page_fault && !load_page_fault_r && !store_page_fault_r) begin
                load_page_fault_r        <= 1'b1;
                load_page_fault_vaddr_r  <= load_page_fault_vaddr;
                mem_page_fault_pc_r      <= mem_page_fault_pc;
            end
            if (store_page_fault && !store_page_fault_r && !load_page_fault_r) begin
                store_page_fault_r       <= 1'b1;
                store_page_fault_vaddr_r <= store_page_fault_vaddr;
                mem_page_fault_pc_r      <= mem_page_fault_pc;
            end
            if (trap_enter_valid || trap_return_valid) begin
                inst_access_fault_r  <= 1'b0;
                load_access_fault_r  <= 1'b0;
                store_access_fault_r <= 1'b0;
                inst_page_fault_r    <= 1'b0;
                load_page_fault_r    <= 1'b0;
                store_page_fault_r   <= 1'b0;
            end
        end
    end

    assign inst_access_fault_pending = inst_access_fault_r;
    assign data_access_fault_pending = load_access_fault_r || store_access_fault_r;
    assign inst_page_fault_pending  = inst_page_fault_r;
    assign data_page_fault_pending  = load_page_fault_r || store_page_fault_r;

    exception_t access_exception;
    exception_t page_exception;
    exception_t decode_exception;
    exception_t mem_misalign_exception;
    exception_t exe_misalign_exception;
    exception_t exception_now;
    exception_t exception_r;

    always_comb begin
        access_exception = '0;
        access_exception.valid = inst_access_fault_r || load_access_fault_r ||
                                 store_access_fault_r;
        access_exception.cause = inst_access_fault_r ? 32'd1 :
                                 load_access_fault_r ? 32'd5 : 32'd7;
        access_exception.epc = inst_access_fault_r ? inst_access_fault_pc_r :
                               mem_access_fault_pc_r;
        access_exception.tval = inst_access_fault_r ? inst_access_fault_addr_r :
                                load_access_fault_r ? load_access_fault_addr_r :
                                                      store_access_fault_addr_r;

        page_exception = '0;
        page_exception.valid = inst_page_fault_r || load_page_fault_r ||
                               store_page_fault_r;
        page_exception.cause = inst_page_fault_r ? 32'd12 :
                               load_page_fault_r ? 32'd13 : 32'd15;
        page_exception.epc = inst_page_fault_r ? inst_page_fault_pc_r :
                             mem_page_fault_pc_r;
        page_exception.tval = inst_page_fault_r ? inst_page_fault_vaddr_r :
                              load_page_fault_r ? load_page_fault_vaddr_r :
                                                  store_page_fault_vaddr_r;

        decode_exception = '0;
        decode_exception.valid = exception_at_decode;
        decode_exception.cause = decode_exception_cause;
        decode_exception.epc = id_pc;
        decode_exception.tval = decode_exception_mtval;

        mem_misalign_exception = '0;
        mem_misalign_exception.valid = mem_valid && mem_done &&
                                       (mem_misalign_load || mem_misalign_store);
        mem_misalign_exception.cause = mem_misalign_load ? 32'd4 : 32'd6;
        mem_misalign_exception.epc = mem_pc;
        mem_misalign_exception.tval = mem_misalign_addr;

        exe_misalign_exception = '0;
        exe_misalign_exception.valid = exe_misalign_valid;
        exe_misalign_exception.cause = 32'd0;
        exe_misalign_exception.epc = exe_pc;
        exe_misalign_exception.tval = exe_misalign_target;

        if (access_exception.valid)
            exception_now = access_exception;
        else if (page_exception.valid)
            exception_now = page_exception;
        else if (decode_exception.valid)
            exception_now = decode_exception;
        else if (mem_misalign_exception.valid)
            exception_now = mem_misalign_exception;
        else
            exception_now = exe_misalign_exception;
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            exception_r <= '0;
        end else begin
            if (trap_enter_valid || trap_return_valid) begin
                exception_r.valid <= 1'b0;
            end else if (exception_now.valid) begin
                exception_r <= exception_now;
            end
        end
    end

    wire clint_trap_enter;
    wire [31:0] clint_trap_pc;
    priv_mode_t clint_target_priv;

    assign trap_pending = clint_trap_enter && !exception_r.valid;
    assign trap_pc = clint_trap_pc;
    assign target_priv = clint_target_priv;

    cpu_clint u_clint(
        .clk(clk),
        .resetn(resetn),
        .exception_valid(exception_r.valid),
        .exception_cause(exception_r.cause),
        .exception_pc(exception_r.epc),
        .exception_mtval(exception_r.tval),
        .mret_req(trap_return_valid && (priv_mode == PRIV_M)),
        .sret_req(trap_return_valid && (priv_mode == PRIV_S)),
        .trap_enter_valid(trap_enter_valid),
        .interrupt_pc(current_pc),
        .priv_mode(priv_mode),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mtvec(csr_mtvec),
        .csr_mepc(csr_mepc),
        .csr_mip(csr_mip),
        .csr_medeleg(csr_medeleg),
        .csr_mideleg(csr_mideleg),
        .csr_stvec(csr_stvec),
        .csr_sepc(csr_sepc),
        .trap_enter(clint_trap_enter),
        .trap_return(),
        .trap_pc(clint_trap_pc),
        .target_priv(clint_target_priv),
        .hw_csr_wen(hw_csr_wen),
        .hw_trap_is_enter(hw_trap_is_enter),
        .hw_target_priv(hw_target_priv),
        .hw_mepc_wdata(hw_mepc_wdata),
        .hw_mcause_wdata(hw_mcause_wdata),
        .hw_mtval_wdata(hw_mtval_wdata),
        .hw_mstatus_wdata(hw_mstatus_wdata),
        .hw_sepc_wdata(hw_sepc_wdata),
        .hw_scause_wdata(hw_scause_wdata),
        .hw_stval_wdata(hw_stval_wdata),
        .hw_sstatus_wdata(hw_sstatus_wdata)
    );

endmodule
