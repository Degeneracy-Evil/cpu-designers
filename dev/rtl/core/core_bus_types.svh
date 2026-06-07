// =============================================================================
// Pipeline bus type definitions (BUG-3 fix: struct-based field access)
// =============================================================================
// Packed structs replace manual bit-index extraction, making the bus layout
// self-documenting and immune to silent breakage when fields are reordered.
//
// Size verification:
//   exe_mem_bus_t : 32+1+1+1+1+1+1+5+32+3+1+32+32+32+32+1+1+1+1+5 = 216
//   wb_bus_t      : 32+1+1+1+5+32+32+32+32+1+1+1+1+5 = 177
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
} exe_mem_bus_t;

`endif // CORE_BUS_TYPES_SVH
