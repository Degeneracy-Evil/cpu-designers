`timescale 1ns / 1ps
`include "core_bus_types.svh"

module cpu_wb(
    input              wb_valid,
    input      wb_bus_t mem_wb_bus_r,
    output             rf_wen,
    output     [4:0]   rf_waddr,
    output     [31:0]  rf_wdata,
    output             wb_done,
    output             wb_is_jal_like,
    output     [31:0]  wb_pc_plus4,
    output     [31:0]  wb_pc,
    output     [31:0]  wb_inst,
    output             fp_wen,
    output     [4:0]   fp_waddr,
    output     [63:0]  fp_wdata,
    output     [4:0]   wb_fflags
);

    wire [31:0] pc_plus4;
    wire is_jal_like;
    wire is_csr;
    wire wb_we;
    wire [4:0] wb_rd;
    wire [31:0] wb_data;
    wire [31:0] csr_rdata;
    wire [31:0] pc;
    wire [31:0] inst;
    wire        is_fpu;
    wire        is_flw;
    wire        is_fsw;
    wire        fpu_rd_is_int;
    wire [4:0]  fpu_fflags;

    assign pc_plus4      = mem_wb_bus_r.pc_plus4;
    assign is_jal_like   = mem_wb_bus_r.is_jal_like;
    assign is_csr        = mem_wb_bus_r.is_csr;
    assign wb_we         = mem_wb_bus_r.wb_we;
    assign wb_rd         = mem_wb_bus_r.wb_rd;
    assign wb_data       = mem_wb_bus_r.wb_data;
    assign csr_rdata     = mem_wb_bus_r.csr_rdata;
    assign pc            = mem_wb_bus_r.pc;
    assign inst          = mem_wb_bus_r.inst;
    assign is_fpu        = mem_wb_bus_r.is_fpu;
    assign is_flw        = mem_wb_bus_r.is_flw;
    assign is_fsw        = mem_wb_bus_r.is_fsw;
    assign fpu_rd_is_int = mem_wb_bus_r.fpu_rd_is_int;
    assign fpu_fflags    = mem_wb_bus_r.fpu_fflags;

    wire [31:0] actual_wb_data;
    assign actual_wb_data = is_csr ? csr_rdata : wb_data;

    // Integer register write: FPU rd_is_int results write to integer register
    // For FPU instructions where rd_is_int=1, the result goes to integer register
    // For FPU instructions where rd_is_int=0, the result goes to float register (fp_wen)
    // FLW writes only to float register — must NOT write integer register
    wire fpu_writes_int = is_fpu && fpu_rd_is_int;
    wire fpu_writes_fp  = is_fpu && !fpu_rd_is_int;

    assign rf_wen = wb_valid && wb_we && (fpu_writes_int || (!is_fpu && !is_flw));
    assign rf_waddr = wb_rd;
    assign rf_wdata = actual_wb_data;
    assign wb_done = wb_valid;

    // Float register write: FPU compute results (rd_is_int=0) and FLW
    // F operations and FLW produce 32-bit results; NaN-box them to 64-bit
    // for the widened regfile (upper 32=0xFFFFFFFF) per RISC-V NaN-boxing
    // spec (IS §22). This allows D operations to detect invalid F-in-D
    // reads by checking the upper 32 bits (Task 23).
    assign fp_wen   = wb_valid && (fpu_writes_fp || is_flw);
    assign fp_waddr = wb_rd;
    assign fp_wdata = {32'hFFFFFFFF, actual_wb_data[31:0]};

    // FPU exception flags for CSR accumulation
    assign wb_fflags = is_fpu ? fpu_fflags : 5'b0;

    assign wb_is_jal_like = is_jal_like;
    assign wb_pc_plus4 = pc_plus4;
    assign wb_pc = pc;
    assign wb_inst = inst;

endmodule
