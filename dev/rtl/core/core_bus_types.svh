// =============================================================================
// Pipeline bus type definitions (BUG-3 fix: struct-based field access)
// =============================================================================
// Packed structs replace manual bit-index extraction, making the bus layout
// self-documenting and immune to silent breakage when fields are reordered.
//
// Size verification:
//   exe_mem_bus_t : 32+1+1+1+1+1+1+5+32+3+1+32+32+32+32+1+1+1+1+5 + 1+1+1+5+1+1 + 1+1 = 228
//   wb_bus_t      : 32+1+1+1+5+32+32+32+32+1+1+1+1+5 + 1+1+1 + 1+1+64 = 246
// =============================================================================

`ifndef CORE_BUS_TYPES_SVH
`define CORE_BUS_TYPES_SVH

// WB-stage bus struct (shared between exe_wb_bus, mem_wb_bus, csr_wb_bus)
typedef struct packed {
    logic [31:0] pc_plus4;
    logic        is_jal_like;
    logic        is_csr;
    logic        wb_we;
    logic [4:0]  wb_rd;
    logic [31:0] wb_data;
    logic [31:0] csr_rdata;
    logic [31:0] pc;
    logic [31:0] inst;
    logic        is_fpu;
    logic        is_flw;
    logic        is_fsw;
    logic        fpu_rd_is_int;
    logic [4:0]  fpu_fflags;
    // --- A extension ---
    logic        is_amo;    // AMO instruction (including LR/SC)
    logic        is_lr;     // LR.W
    logic        is_sc;     // SC.W
    // --- D extension (FLD/FSD 64-bit load/store — Task 25) ---
    logic        is_fld;    // FLD (double-precision FP load)
    logic        is_fsd;    // FSD (double-precision FP store)
    logic [63:0] fp_wdata64;// 64-bit FP writeback data (FLD result; D arithmetic via Task 26)
} wb_bus_t;

// EXE→MEM bus struct
typedef struct packed {
    logic [31:0] pc_plus4;
    logic        result_ok;
    logic        is_jal_like;
    logic        is_load;
    logic        is_store;
    logic        is_csr;
    logic        wb_we;
    logic [4:0]  wb_rd;
    logic [31:0] result_reg;
    logic [2:0]  mem_size;
    logic        mem_unsigned;
    logic [31:0] rs2_value;
    logic [31:0] csr_rdata;
    logic [31:0] pc;
    logic [31:0] inst;
    logic        is_fpu;
    logic        is_flw;
    logic        is_fsw;
    logic        fpu_rd_is_int;
    logic [4:0]  fpu_fflags;
    // --- A extension ---
    logic        is_amo;      // AMO instruction (including LR/SC)
    logic        is_lr;       // LR.W
    logic        is_sc;       // SC.W
    logic [4:0]  amo_funct5;  // AMO operation code (inst[31:27])
    logic        amo_aq;      // acquire ordering bit
    logic        amo_rl;      // release ordering bit
    // --- D extension ---
    logic        is_fld;      // FLD (double-precision FP load)
    logic        is_fsd;      // FSD (double-precision FP store)
} exe_mem_bus_t;

`endif // CORE_BUS_TYPES_SVH
