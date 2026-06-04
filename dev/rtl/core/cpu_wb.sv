`timescale 1ns / 1ps

module cpu_wb(
    input              wb_valid,
    input      [176:0] mem_wb_bus_r,
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
    output     [31:0]  fp_wdata,
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

    assign {pc_plus4, is_jal_like, is_csr, wb_we, wb_rd, wb_data, csr_rdata, pc, inst,
            is_fpu, is_flw, is_fsw, fpu_rd_is_int, fpu_fflags} = mem_wb_bus_r;

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
    assign fp_wen   = wb_valid && (fpu_writes_fp || is_flw);
    assign fp_waddr = wb_rd;
    assign fp_wdata = actual_wb_data;

    // FPU exception flags for CSR accumulation
    assign wb_fflags = is_fpu ? fpu_fflags : 5'b0;

    assign wb_is_jal_like = is_jal_like;
    assign wb_pc_plus4 = pc_plus4;
    assign wb_pc = pc;
    assign wb_inst = inst;

endmodule
