// =============================================================================
// Core architectural contracts
// =============================================================================

`ifndef CORE_BUS_TYPES_SVH
`define CORE_BUS_TYPES_SVH

typedef enum logic [1:0] {
    PRIV_U = 2'b00,
    PRIV_S = 2'b01,
    PRIV_M = 2'b11
} priv_mode_t;

typedef enum logic [1:0] {
    RET_NONE = 2'd0,
    RET_M    = 2'd1,
    RET_S    = 2'd2
} trap_return_kind_t;

function automatic logic priv_at_least(
    input priv_mode_t current,
    input priv_mode_t required
);
    case (current)
        PRIV_M: priv_at_least = (required == PRIV_M) ||
                                (required == PRIV_S) ||
                                (required == PRIV_U);
        PRIV_S: priv_at_least = (required == PRIV_S) ||
                                (required == PRIV_U);
        PRIV_U: priv_at_least = (required == PRIV_U);
        default: priv_at_least = 1'b0;
    endcase
endfunction

typedef enum logic [2:0] {
    MEM_NONE  = 3'd0,
    MEM_LOAD  = 3'd1,
    MEM_STORE = 3'd2,
    MEM_LR    = 3'd3,
    MEM_SC    = 3'd4,
    MEM_AMO   = 3'd5
} mem_kind_t;

typedef enum logic [1:0] {
    ACCESS_FETCH = 2'd0,
    ACCESS_LOAD  = 2'd1,
    ACCESS_STORE = 2'd2
} access_class_t;

function automatic priv_mode_t effective_data_priv(
    input priv_mode_t current_priv,
    input logic       mstatus_mprv,
    input priv_mode_t mstatus_mpp
);
    effective_data_priv = ((current_priv == PRIV_M) && mstatus_mprv) ?
                          mstatus_mpp : current_priv;
endfunction

function automatic access_class_t mem_access_class(input mem_kind_t kind);
    case (kind)
        MEM_LOAD, MEM_LR: mem_access_class = ACCESS_LOAD;
        MEM_STORE, MEM_SC, MEM_AMO: mem_access_class = ACCESS_STORE;
        default:          mem_access_class = ACCESS_LOAD;
    endcase
endfunction

typedef struct packed {
    logic        valid;
    logic [31:0] cause;
    logic [31:0] epc;
    logic [31:0] tval;
} exception_t;

typedef struct packed {
    logic [31:0] pc_plus4;
    logic [31:0] pc;
    logic [31:0] inst;
} if_id_bus_t;

typedef struct packed {
    logic [31:0] pc;
    logic [31:0] pc_plus4;
    logic [31:0] inst;
    logic [15:0] alu_control;
    logic [31:0] alu_src1;
    logic [31:0] alu_src2;
    logic        is_branch;
    logic        is_jal_like;
    logic [2:0]  branch_funct3;
    logic        use_fixed_wb;
    logic [31:0] fixed_wb_data;
    logic        wb_we;
    logic [4:0]  wb_rd;
    logic        is_mu;
    logic [2:0]  mu_funct3;
    mem_kind_t   mem_kind;
    logic [2:0]  mem_size;
    logic        mem_unsigned;
    logic [31:0] rs1_value;
    logic [31:0] rs2_value;
    logic [4:0]  amo_funct5;
    logic [11:0] csr_addr;
    logic [2:0]  csr_funct3;
    logic [4:0]  csr_uimm;
    logic [4:0]  csr_rs1;
} id_exe_bus_t;

typedef struct packed {
    logic [31:0] pc;
    logic [31:0] pc_plus4;
    logic [31:0] inst;
    logic [31:0] result;
    logic        wb_we;
    logic [4:0]  wb_rd;
    mem_kind_t   mem_kind;
    logic [2:0]  mem_size;
    logic        mem_unsigned;
    logic [31:0] store_data;
    logic [4:0]  amo_funct5;
} exe_mem_bus_t;

typedef struct packed {
    logic        wb_we;
    logic [4:0]  wb_rd;
    logic [31:0] wb_data;
    logic [31:0] pc;
    logic [31:0] inst;
} wb_bus_t;

`endif // CORE_BUS_TYPES_SVH
