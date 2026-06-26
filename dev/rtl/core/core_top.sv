`timescale 1ns / 1ps
`include "core_bus_types.svh"
`include "axi4_def.svh"

module core_top(
    input         clk,
    input         resetn,

    input  [4:0]  rf_addr,
    output [31:0] rf_data,
    output [31:0] if_pc,
    output [31:0] if_inst,
    output [31:0] id_pc,
    output [31:0] id_inst,
    output [31:0] exe_pc,
    output [31:0] exe_inst,
    output [31:0] mem_pc,
    output [31:0] mem_inst,
    output [31:0] wb_pc,
    output [31:0] wb_inst,
    output [31:0] display_state,

    // ---------- Trap/CSR debug outputs ----------
    output        trap_enter_valid,
    output        trap_return_valid,
    output [31:0] trap_csr_pc,
    output [31:0] csr_mtvec,
    output [31:0] csr_mepc,
    output [31:0] csr_mcause,
    output [31:0] csr_stvec,
    output [31:0] csr_sepc,
    output [31:0] csr_scause,
    output [1:0]  priv_mode,
    output [1:0]  target_priv,

    // ---------- Extended debug outputs ----------
    output [31:0] csr_sstatus,       // S-mode status
    output [31:0] csr_sscratch,      // S-mode scratch
    output [31:0] csr_stval,         // S-mode trap value
    output [31:0] csr_satp,          // S-mode address translation
    output [31:0] hw_trap_epc,       // faulting PC at trap entry
    output [31:0] hw_trap_cause,     // raw cause at trap entry
    output [31:0] hw_trap_tval,      // trap value at trap entry
    output [31:0] exe_mem_vaddr,     // load/store virtual address
    output        exe_is_store,      // memory write flag
    output        exe_is_load,       // memory read flag
    output [31:0] gpr_tp,            // x4 (tp) value
    output [31:0] gpr_sp,            // x2 (sp) value
    output [31:0] gpr_ra,            // x1 (ra) value
    output [31:0] gpr_s1,            // x9 (s1) value
    output [31:0] gpr_a0,            // x10 (a0) value
    output [31:0] gpr_a1,            // x11 (a1) value
    output [31:0] gpr_a2,            // x12 (a2) value
    output [31:0] gpr_a3,            // x13 (a3) value
    output [31:0] gpr_a4,            // x14 (a4) value
    output [31:0] gpr_a5,            // x15 (a5) value
    output [31:0] gpr_a6,            // x16 (a6) value
    output [31:0] gpr_a7,            // x17 (a7) value
    output [31:0] gpr_s2,            // x18 (s2) value
    output [31:0] gpr_s3,            // x19 (s3) value
    output        dbg_watch_valid,
    output [31:0] dbg_watch_pc,
    output [31:0] dbg_watch_inst,
    output [31:0] dbg_watch_vaddr,
    output [31:0] dbg_watch_paddr,
    output [31:0] dbg_watch_wdata,
    output [31:0] dbg_watch_count,
    output        dbg_dcache_lh_valid,
    output [31:0] dbg_dcache_lh_data,
    output [31:0] dbg_dcache_lh_count,
    output        dbg_dcache_rf_valid,
    output [31:0] dbg_dcache_rf_data,
    output [31:0] dbg_dcache_rf_count,
    output        dbg_dcache_wb_valid,
    output [31:0] dbg_dcache_wb_data,
    output [31:0] dbg_dcache_wb_count,
    output        dbg_watch_load_valid,
    output [31:0] dbg_watch_load_pc,
    output [31:0] dbg_watch_load_rdata,
    output [31:0] dbg_watch_load_wbdata,
    output [31:0] dbg_watch_load_count,
    output [31:0] dbg_watch_load_status,
    output        dbg_focus_store_valid,
    output [31:0] dbg_focus_store_pc,
    output [31:0] dbg_focus_store_inst,
    output [31:0] dbg_focus_store_vaddr,
    output [31:0] dbg_focus_store_paddr,
    output [31:0] dbg_focus_store_wdata,
    output [31:0] dbg_focus_store_status,
    output        dbg_focus_load_valid,
    output [31:0] dbg_focus_load_pc,
    output [31:0] dbg_focus_load_inst,
    output [31:0] dbg_focus_load_paddr,
    output [31:0] dbg_focus_load_rdata,
    output [31:0] dbg_focus_load_status,
    output        dbg_focus_load_wb_valid,
    output [31:0] dbg_focus_load_wb_pc,
    output [31:0] dbg_focus_load_wb_status,
    output [31:0] dbg_focus_load_wb_rfdata,
    output [31:0] dbg_focus_load_wb_s2,
    output        dbg_if_done,
    output        dbg_inst_valid,
    output        dbg_mmu_i_ready,
    output        dbg_mmu_i_miss,
    output        dbg_i_page_fault,
    output [2:0]  dbg_icache_state,
    output        dbg_icache_refill_req,
    output        dbg_icache_refill_valid,
    output        dbg_ptw_walk_active,
    output        dbg_pending_i_walk,
    output [2:0]  dbg_mmu_i_state,
    output        dbg_mmu_i_input_changed,
    output [31:0] dbg_mmu_i_latched_vaddr,
    output        dbg_mmu_i_sv32,
    output        dbg_mmu_i_tlb_hit,
    output        dbg_mmu_i_tlb_valid,
    output        dbg_mmu_i_tlb_perm_fault,
    output [1:0]  dbg_mmu_walk_state,
    output [2:0]  dbg_mmu_d_state,
    output        dbg_mmu_d_tlb_hit,
    output        dbg_mmu_d_tlb_valid,
    output        dbg_mmu_d_tlb_perm_fault,
    output        dbg_mmu_d_input_changed,
    output [31:0] dbg_mmu_d_latched_vaddr,
    output        dbg_mmu_d_latched_sv32,
    output        dbg_mmu_d_pf_from_ptw,
    output        dbg_mmu_d_tlb_miss,
    output        dbg_mu_active,
    output        dbg_mu_req_valid,
    output        dbg_mu_ready,
    output        dbg_mu_busy,
    output        dbg_mu_result_valid,
    output [2:0]  dbg_mu_funct3,
    output        dbg_exe_is_mu,
    output        dbg_dmmio_req,
    output        dbg_dmmio_we,
    output [31:0] dbg_dmmio_addr,
    output [2:0]  dbg_dmmio_hsize,
    output        dbg_dmmio_valid,
    output [31:0] dbg_dmmio_rdata,
    output        dbg_last_mmio_valid,
    output [31:0] dbg_last_mmio_pc,
    output        dbg_last_mmio_we,
    output [31:0] dbg_last_mmio_addr,
    output [2:0]  dbg_last_mmio_hsize,
    output [31:0] dbg_last_mmio_wdata,
    output [31:0] dbg_last_mmio_rdata,
    output [31:0] dbg_last_mmio_caller_pc,
    output [31:0] dbg_last_mmio_count,

    // ---------- AXI4 Master — AW Channel ----------
    output [3:0]  awid,
    output [31:0] awaddr,
    output [7:0]  awlen,
    output [2:0]  awsize,
    output [1:0]  awburst,
    output        awlock,
    output [3:0]  awcache,
    output [2:0]  awprot,
    output [3:0]  awqos,
    output [3:0]  awregion,
    output        awvalid,
    input         awready,

    // ---------- AXI4 Master — W Channel ----------
    output [31:0] wdata,
    output [3:0]  wstrb,
    output        wlast,
    output        wvalid,
    input         wready,

    // ---------- AXI4 Master — B Channel ----------
    input  [1:0]  bresp,
    input         bvalid,
    output        bready,

    // ---------- AXI4 Master — AR Channel ----------
    output [3:0]  arid,
    output [31:0] araddr,
    output [7:0]  arlen,
    output [2:0]  arsize,
    output [1:0]  arburst,
    output        arlock,
    output [3:0]  arcache,
    output [2:0]  arprot,
    output [3:0]  arqos,
    output [3:0]  arregion,
    output        arvalid,
    input         arready,

    // ---------- AXI4 Master — R Channel ----------
    input  [31:0] rdata,
    input  [1:0]  rresp,
    input         rlast,
    input         rvalid,
    output        rready,

    input         init_sig,
    input         timer_irq,
    input         ext_meip_in,
    input         ext_seip_in,
    input         ext_msip_in,
    input  [63:0] ext_mtime
);

    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;
    localparam PRIV_M = 2'b11;

    reg [31:0] pc;
    reg [1:0]  priv_mode;

    wire if_done;
    wire id_done;
    wire exe_done;
    wire mem_done;
    wire wb_done;

    wire if_valid;
    wire id_valid;
    wire exe_valid;
    wire mem_valid;
    wire wb_valid;
    wire csr_valid;
    wire trap_enter_valid;
    wire trap_return_valid;
    wire exe_to_wb;
    wire [3:0] fsm_state;

    wire        fencei_req;
    wire        fencei_done;
    wire        sfence_vma_req;
    wire        sfence_vma_done;

    wire dec_is_branch;
    wire dec_need_exe;
    wire dec_illegal;
    wire dec_is_csr;
    wire dec_is_ecall;
    wire dec_is_ebreak;
    wire dec_is_mret;
    wire dec_is_sret;
    wire dec_is_nop_like;
    wire dec_is_fencei;
    wire dec_is_sfence_vma;
    wire [11:0] dec_csr_addr;
    wire [2:0]  dec_csr_funct3;
    // Debug: CSR decode results (used internally in cpu_decode for illegal_inst; not consumed at core_top)
    wire dec_csr_addr_valid;
    wire dec_csr_access_ok;

    wire exe_branch_taken;
    wire [31:0] exe_branch_target;
    wire exe_is_ctrl_flow;
    wire exe_is_branch;
    wire exe_need_mem;

    wire exe_misalign_valid;
    wire [31:0] exe_misalign_target;

    wire [95:0]  if_id_bus;
    wire [348:0] id_exe_bus;
    exe_mem_bus_t exe_mem_bus;
    wb_bus_t      mem_wb_bus;

    reg [95:0]  if_id_bus_r;
    reg [348:0] id_exe_bus_r;
    exe_mem_bus_t exe_mem_bus_r;
    wb_bus_t      mem_wb_bus_r;

    wire mem_en;

    wire        mem_data_access;   // Combinational: is_load||is_store||is_flw||is_fsw (consumed by cpu_controller)
    wire        mmu_inst_page_fault;
    wire        mmu_data_page_fault;
    wire [3:0]  mmu_inst_pf_cause;
    wire [3:0]  mmu_data_pf_cause;
    wire [31:0] mmu_inst_pf_vaddr;
    wire [31:0] mmu_data_pf_vaddr;

    wire        mmu_inst_ready;
    wire        mmu_data_ready;

    // ── Unified MMU translate interface wires ──
    wire        mmu_translate_req;
    wire [31:0] mmu_translate_vaddr;
    wire [1:0]  mmu_translate_access;
    wire        mmu_translate_done;
    wire [31:0] mmu_translate_paddr;
    wire        mmu_translate_fault;
    wire [3:0]  mmu_translate_cause;
    wire [31:0] mmu_translate_vaddr_out;

    // ── Unified MMU: translate request logic ──
    // CPU requests translation when in FETCH or MEM with a memory access.
    // translate_req is held until translate_done returns (CPU blocks in that state).
    // T_COMPLETE state holds translate_done high until !translate_req
    assign mmu_translate_req    = if_valid || (mem_valid && mem_en);
    assign mmu_translate_vaddr  = if_valid ? fetch_vaddr : mem_dataAddr_32;
    assign mmu_translate_access = if_valid ? 2'b00 : (mem_hwrite ? 2'b10 : 2'b01);  // FETCH : (STORE : LOAD)

    // ── Route translate results to i-side and d-side ──
    // i-side and d-side never overlap, so paddr can be shared directly.
    wire [31:0] mmu_inst_paddr;
    wire [31:0] mmu_data_paddr;
    assign mmu_inst_paddr       = mmu_translate_paddr;
    assign mmu_data_paddr       = mmu_translate_paddr;
    assign mmu_inst_ready       = mmu_translate_done && !mmu_translate_fault;
    assign mmu_data_ready       = mmu_translate_done && !mmu_translate_fault;

    // ── Page fault routing with state gating ──
    // Only report i-side fault in FETCH, d-side fault in MEM.
    assign mmu_inst_page_fault  = mmu_translate_fault && if_valid;
    assign mmu_data_page_fault  = mmu_translate_fault && mem_valid;
    assign mmu_inst_pf_cause    = mmu_translate_cause;
    assign mmu_data_pf_cause    = mmu_translate_cause;
    assign mmu_inst_pf_vaddr    = mmu_translate_vaddr_out;
    assign mmu_data_pf_vaddr    = mmu_translate_vaddr_out;

    // ── MMU miss signals: always 0 in unified MMU (no autonomous miss) ──
    wire mmu_inst_miss  = 1'b0;
    wire mmu_data_miss  = 1'b0;
    wire        mmu_dbg_i_walk_active;
    wire        mmu_dbg_pending_i_walk;
    wire [2:0]  mmu_dbg_i_state;
    wire        mmu_dbg_i_input_changed;
    wire [31:0] mmu_dbg_i_latched_vaddr;
    wire        mmu_dbg_i_sv32;
    wire        mmu_dbg_i_tlb_hit;
    wire        mmu_dbg_i_tlb_valid;
    wire        mmu_dbg_i_tlb_perm_fault;
    wire [1:0]  mmu_dbg_walk_state;
    wire [2:0]  mmu_dbg_d_state;
    wire        mmu_dbg_d_tlb_hit;
    wire        mmu_dbg_d_tlb_valid;
    wire        mmu_dbg_d_tlb_perm_fault;
    wire        mmu_dbg_d_input_changed;
    wire [31:0] mmu_dbg_d_latched_vaddr;
    wire        mmu_dbg_d_latched_sv32;
    wire        mmu_dbg_pending_d_walk;
    wire        mmu_dbg_d_pf_from_ptw;
    wire        mmu_dbg_d_tlb_miss;

    // PTW cache interface (unified MMU → dcache_ctrl)
    wire        ptw_cache_req;
    wire [31:0] ptw_cache_addr;
    wire        ptw_cache_ready;
    wire [31:0] ptw_cache_rdata;
    wire        ptw_cache_fault;

    // PMP check interface for PTW (pass-through to MMU/PTW)
    wire        ptw_pmp_grant;
    wire [1:0]  ptw_pmp_fault_type;

    wire        mmu_sfence_done;

    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [31:0] rs1_value;
    wire [31:0] rs2_value;

    wire rf_wen;
    wire [4:0] rf_waddr;
    wire [31:0] rf_wdata;
    wire wb_is_jal_like;

    // Float register file
  wire [4:0]  frs1_addr;
  wire [4:0]  frs2_addr;
  wire [4:0]  frs3_addr;
  wire [31:0] frs1_value;
  wire [31:0] frs2_value;
  wire [31:0] frs3_value;
    wire        fp_wen;
    wire [4:0]  fp_waddr;
    wire [31:0] fp_wdata;
    wire [31:0] fp_dbg_data;

    // FPU CSR signals
    wire [4:0]  wb_fflags;
    wire [2:0]  csr_frm;

    wire [31:0] id_pc_plus4;
    wire [31:0] exe_pc_plus4;
    wire [31:0] wb_pc_plus4;

    assign id_pc_plus4  = if_id_bus_r[95:64];
    assign exe_pc_plus4 = id_exe_bus_r[348:317];
    assign wb_pc_plus4  = mem_wb_bus_r.pc_plus4;

    wire [31:0] actual_rf_wdata;
    assign actual_rf_wdata = wb_is_jal_like ? wb_pc_plus4 : rf_wdata;

    wb_bus_t      exe_wb_bus;
    assign exe_wb_bus = '{
        pc_plus4:      exe_mem_bus.pc_plus4,
        is_jal_like:   exe_mem_bus.is_jal_like,
        is_csr:        exe_mem_bus.is_csr,
        wb_we:         exe_mem_bus.wb_we & exe_mem_bus.result_ok,
        wb_rd:         exe_mem_bus.wb_rd,
        wb_data:       exe_mem_bus.result_reg,
        csr_rdata:     exe_mem_bus.csr_rdata,
        pc:            exe_mem_bus.pc,
        inst:          exe_mem_bus.inst,
        is_fpu:        exe_mem_bus.is_fpu,
        is_flw:        exe_mem_bus.is_flw,
        is_fsw:        exe_mem_bus.is_fsw,
        fpu_rd_is_int: exe_mem_bus.fpu_rd_is_int,
        fpu_fflags:    exe_mem_bus.fpu_fflags,
        is_amo:        exe_mem_bus.is_amo,
        is_lr:         exe_mem_bus.is_lr,
        is_sc:         exe_mem_bus.is_sc
    };

    wire mem_misalign_load;
    wire mem_misalign_store;
    wire [31:0] mem_misalign_addr;

    wire [31:0] id_pc_wire;
    wire [31:0] id_inst_wire;

    wire exception_at_decode;
    wire trap_pending;
    wire [31:0] csr_read_data;
    wb_bus_t      csr_wb_bus;
    wire [31:0] trap_csr_pc;
    wire [31:0] csr_pc_plus4_out;
    wire [1:0]  target_priv;

    wire inst_access_fault_pending;
    wire data_access_fault_pending;
    wire inst_page_fault_pending;
    wire data_page_fault_pending;

    wire cycle_en;
    assign cycle_en = ~init_sig;
    wire inst_retire;
    assign inst_retire = wb_done;

    wire [31:0] csr_mstatus;
    wire [31:0] csr_mie;
    wire [31:0] csr_mtvec;
    wire [31:0] csr_mepc;
    wire [31:0] csr_mcause;
    wire [31:0] csr_mip;
    wire [31:0] csr_medeleg;
    wire [31:0] csr_mideleg;
    wire [31:0] csr_sstatus;
    wire [31:0] csr_sie;
    wire [31:0] csr_stvec;
    wire [31:0] csr_sscratch;
    wire [31:0] csr_sepc;
    wire [31:0] csr_scause;
    wire [31:0] csr_stval;
    wire [31:0] csr_sip;
    wire [31:0] csr_satp;
    wire [31:0] csr_mcounteren;
    wire [31:0] csr_scounteren;
    // PMP CSR wires
    wire [31:0] csr_pmpcfg0, csr_pmpcfg1, csr_pmpcfg2, csr_pmpcfg3;
    wire [31:0] csr_pmpaddr0,  csr_pmpaddr1,  csr_pmpaddr2,  csr_pmpaddr3;
    wire [31:0] csr_pmpaddr4,  csr_pmpaddr5,  csr_pmpaddr6,  csr_pmpaddr7;
    wire [31:0] csr_pmpaddr8,  csr_pmpaddr9,  csr_pmpaddr10, csr_pmpaddr11;
    wire [31:0] csr_pmpaddr12, csr_pmpaddr13, csr_pmpaddr14, csr_pmpaddr15;
    // PMP violation flags
    wire pmp_data_violation;
    // Debug: CSR access permission from trap_csr (used internally; not consumed at core_top)
    wire csr_access_ok;

    // Extended debug wires
    wire [31:0] hw_trap_epc_w;
    wire [31:0] hw_trap_cause_w;
    wire [31:0] hw_trap_tval_w;
    wire [31:0] gpr_tp_w;
    wire [31:0] gpr_sp_w;
    wire [31:0] gpr_ra_w;
    wire [31:0] gpr_s1_w;
    wire [31:0] gpr_a0_w;
    wire [31:0] gpr_a1_w;
    wire [31:0] gpr_a2_w;
    wire [31:0] gpr_a3_w;
    wire [31:0] gpr_a4_w;
    wire [31:0] gpr_a5_w;
    wire [31:0] gpr_a6_w;
    wire [31:0] gpr_a7_w;
    wire [31:0] gpr_s2_w;
    wire [31:0] gpr_s3_w;
    wire [2:0]  dbg_load_mem_size_w;
    wire        dbg_load_mem_unsigned_w;
    wire [31:0] dbg_load_addr_w;
    wire [31:0] dbg_load_raw_rdata_w;
    wire [31:0] dbg_load_value_w;
    reg         dbg_watch_valid_r;
    reg [31:0] dbg_watch_pc_r;
    reg [31:0] dbg_watch_inst_r;
    reg [31:0] dbg_watch_vaddr_r;
    reg [31:0] dbg_watch_paddr_r;
    reg [31:0] dbg_watch_wdata_r;
    reg [31:0] dbg_watch_count_r;
    reg        dbg_watch_load_valid_r;
    reg [31:0] dbg_watch_load_pc_r;
    reg [31:0] dbg_watch_load_rdata_r;
    reg [31:0] dbg_watch_load_wbdata_r;
    reg [31:0] dbg_watch_load_count_r;
    reg [31:0] dbg_watch_load_status_r;
    reg        dbg_focus_store_valid_r;
    reg [31:0] dbg_focus_store_pc_r;
    reg [31:0] dbg_focus_store_inst_r;
    reg [31:0] dbg_focus_store_vaddr_r;
    reg [31:0] dbg_focus_store_paddr_r;
    reg [31:0] dbg_focus_store_wdata_r;
    reg [31:0] dbg_focus_store_status_r;
    reg        dbg_focus_load_valid_r;
    reg [31:0] dbg_focus_load_pc_r;
    reg [31:0] dbg_focus_load_inst_r;
    reg [31:0] dbg_focus_load_paddr_r;
    reg [31:0] dbg_focus_load_rdata_r;
    reg [31:0] dbg_focus_load_status_r;
    reg        dbg_focus_load_wb_valid_r;
    reg [31:0] dbg_focus_load_wb_pc_r;
    reg [31:0] dbg_focus_load_wb_status_r;
    reg [31:0] dbg_focus_load_wb_rfdata_r;
    reg [31:0] dbg_focus_load_wb_s2_r;

    assign hw_trap_epc   = hw_trap_epc_w;
    assign hw_trap_cause = hw_trap_cause_w;
    assign hw_trap_tval  = hw_trap_tval_w;
    assign gpr_tp        = gpr_tp_w;
    assign gpr_sp        = gpr_sp_w;
    assign gpr_ra        = gpr_ra_w;
    assign gpr_s1        = gpr_s1_w;
    assign gpr_a0        = gpr_a0_w;
    assign gpr_a1        = gpr_a1_w;
    assign gpr_a2        = gpr_a2_w;
    assign gpr_a3        = gpr_a3_w;
    assign gpr_a4        = gpr_a4_w;
    assign gpr_a5        = gpr_a5_w;
    assign gpr_a6        = gpr_a6_w;
    assign gpr_a7        = gpr_a7_w;
    assign gpr_s2        = gpr_s2_w;
    assign gpr_s3        = gpr_s3_w;
    assign dbg_watch_valid = dbg_watch_valid_r;
    assign dbg_watch_pc    = dbg_watch_pc_r;
    assign dbg_watch_inst  = dbg_watch_inst_r;
    assign dbg_watch_vaddr = dbg_watch_vaddr_r;
    assign dbg_watch_paddr = dbg_watch_paddr_r;
    assign dbg_watch_wdata = dbg_watch_wdata_r;
    assign dbg_watch_count = dbg_watch_count_r;
    assign dbg_dcache_lh_valid = dbg_dcache_lh_valid_w;
    assign dbg_dcache_lh_data  = dbg_dcache_lh_data_w;
    assign dbg_dcache_lh_count = dbg_dcache_lh_count_w;
    assign dbg_dcache_rf_valid = dbg_dcache_rf_valid_w;
    assign dbg_dcache_rf_data  = dbg_dcache_rf_data_w;
    assign dbg_dcache_rf_count = dbg_dcache_rf_count_w;
    assign dbg_dcache_wb_valid = dbg_dcache_wb_valid_w;
    assign dbg_dcache_wb_data  = dbg_dcache_wb_data_w;
    assign dbg_dcache_wb_count = dbg_dcache_wb_count_w;
    assign dbg_watch_load_valid  = dbg_watch_load_valid_r;
    assign dbg_watch_load_pc     = dbg_watch_load_pc_r;
    assign dbg_watch_load_rdata  = dbg_watch_load_rdata_r;
    assign dbg_watch_load_wbdata = dbg_watch_load_wbdata_r;
    assign dbg_watch_load_count  = dbg_watch_load_count_r;
    assign dbg_watch_load_status = dbg_watch_load_status_r;
    assign dbg_focus_store_valid  = dbg_focus_store_valid_r;
    assign dbg_focus_store_pc     = dbg_focus_store_pc_r;
    assign dbg_focus_store_inst   = dbg_focus_store_inst_r;
    assign dbg_focus_store_vaddr  = dbg_focus_store_vaddr_r;
    assign dbg_focus_store_paddr  = dbg_focus_store_paddr_r;
    assign dbg_focus_store_wdata  = dbg_focus_store_wdata_r;
    assign dbg_focus_store_status = dbg_focus_store_status_r;
    assign dbg_focus_load_valid   = dbg_focus_load_valid_r;
    assign dbg_focus_load_pc      = dbg_focus_load_pc_r;
    assign dbg_focus_load_inst    = dbg_focus_load_inst_r;
    assign dbg_focus_load_paddr   = dbg_focus_load_paddr_r;
    assign dbg_focus_load_rdata   = dbg_focus_load_rdata_r;
    assign dbg_focus_load_status  = dbg_focus_load_status_r;
    assign dbg_focus_load_wb_valid  = dbg_focus_load_wb_valid_r;
    assign dbg_focus_load_wb_pc     = dbg_focus_load_wb_pc_r;
    assign dbg_focus_load_wb_status = dbg_focus_load_wb_status_r;
    assign dbg_focus_load_wb_rfdata = dbg_focus_load_wb_rfdata_r;
    assign dbg_focus_load_wb_s2     = dbg_focus_load_wb_s2_r;
    assign exe_mem_vaddr = mem_dataAddr_32;
    assign exe_is_store  = exe_mem_bus.is_store;
    assign exe_is_load   = exe_mem_bus.is_load;

    wire [1:0] mpp_field;
    assign mpp_field = csr_mstatus[12:11];
    wire spp_field;
    assign spp_field = csr_mstatus[8];

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            pc <= 32'hFC000000;  // Boot ROM @ 0xFC00_0000 (both sim and FPGA)
            priv_mode <= PRIV_M;
            if_id_bus_r <= 96'b0;
            id_exe_bus_r <= 349'b0;
            exe_mem_bus_r <= '0;
            mem_wb_bus_r <= '0;
        end else begin
            if (if_done) begin
                if_id_bus_r <= if_id_bus;
            end
            if (id_done && (dec_need_exe || dec_is_csr)) begin
                id_exe_bus_r <= id_exe_bus;
            end
            if (exe_done) begin
                exe_mem_bus_r <= exe_mem_bus;
            end
            if (exe_to_wb) begin
                mem_wb_bus_r <= exe_wb_bus;
            end else if (mem_done) begin
                mem_wb_bus_r <= mem_wb_bus;
            end else if (csr_valid) begin
                mem_wb_bus_r <= csr_wb_bus;
            end

            if (trap_enter_valid) begin
                if_id_bus_r <= 96'b0;
                id_exe_bus_r <= 349'b0;
                pc <= trap_csr_pc;
                priv_mode <= target_priv;
            end else if (trap_return_valid) begin
                if_id_bus_r <= 96'b0;
                id_exe_bus_r <= 349'b0;
                pc <= trap_csr_pc;
                if (priv_mode == PRIV_M) begin
                    priv_mode <= mpp_field;
                end else begin
                    priv_mode <= spp_field ? PRIV_S : PRIV_U;
                end
            end else if (exe_valid && exe_done) begin
                if (exe_is_ctrl_flow && exe_branch_taken) begin
                    if_id_bus_r <= 96'b0;
                    id_exe_bus_r <= 349'b0;
                    pc <= exe_branch_target;
                end else begin
                    pc <= exe_pc_plus4;
                end
            end else if (csr_valid) begin
                pc <= csr_pc_plus4_out;
            end else if (id_valid && id_done && (dec_is_nop_like || dec_is_fencei || dec_is_sfence_vma)) begin
                pc <= id_pc_plus4;
            end
        end
    end

    cpu_controller u_ctrl(
        .clk(clk),
        .resetn(resetn),
        .if_done(if_done),
        .id_done(id_done),
        .exe_done(exe_done),
        .mem_done(mem_done),
        .wb_done(wb_done),
        .dec_is_branch(dec_is_branch),
        .dec_need_exe(dec_need_exe),
        .dec_illegal(dec_illegal),
        .dec_is_csr(dec_is_csr),
        .dec_is_ecall(dec_is_ecall),
        .dec_is_ebreak(dec_is_ebreak),
        .dec_is_mret(dec_is_mret),
        .dec_is_sret(dec_is_sret),
        .dec_is_nop_like(dec_is_nop_like),
        .dec_is_fencei(dec_is_fencei),
        .dec_is_sfence_vma(dec_is_sfence_vma),
        .fencei_done(fencei_done),
        .sfence_vma_done(sfence_vma_done),
        .exe_is_branch(exe_is_branch),
        .exe_need_mem(exe_need_mem),
        .trap_pending(trap_pending),
        .exception_at_decode(exception_at_decode),
        .inst_access_fault_pending(inst_access_fault_pending),
        .data_access_fault_pending(data_access_fault_pending),
        .inst_page_fault_pending(inst_page_fault_pending),
        .data_page_fault_pending(data_page_fault_pending),
        .mem_data_access(mem_data_access),  // Combinational: instruction is load/store (not mem_en which is registered bus-active)
        .init_sig(init_sig),
        .if_valid(if_valid),
        .id_valid(id_valid),
        .exe_valid(exe_valid),
        .mem_valid(mem_valid),
        .wb_valid(wb_valid),
        .csr_valid(csr_valid),
        .trap_enter_valid(trap_enter_valid),
        .trap_return_valid(trap_return_valid),
        .exe_to_wb(exe_to_wb),
        .fencei_req(fencei_req),
        .sfence_vma_req(sfence_vma_req),
        .state(fsm_state)
    );

    wire [31:0] fetch_vaddr;

    wire [31:0] instData_32_mux;
    wire        inst_valid_mux;
    wire        icache_mmio_req;
    wire        icache_mmio_accept;

    wire [31:0] ahb_inst_data;
    wire        ahb_inst_valid;

    wire        icache_refill_req;
    wire [31:0] icache_refill_addr;
    wire [255:0] icache_refill_data;
    wire        icache_refill_valid;
    wire [31:0] icache_refill_resp_addr;
    wire [2:0]  icache_dbg_state;

    wire        dcache_flush_req;
    wire        dcache_flush_done;
    wire        icache_invalidate_req;
    wire        icache_invalidate_done;
    wire        icache_flush_req;

    // ── fence.i sequencing ──
    // Sequence: dcache flush (writeback+invalidate) → icache invalidate → done
    reg fencei_dcache_flush_sent_r;
    reg fencei_icache_inv_sent_r;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            fencei_dcache_flush_sent_r  <= 1'b0;
            fencei_icache_inv_sent_r    <= 1'b0;
        end else begin
            if (!fencei_req) begin
                fencei_dcache_flush_sent_r  <= 1'b0;
                fencei_icache_inv_sent_r    <= 1'b0;
            end else begin
                if (dcache_flush_done && !fencei_dcache_flush_sent_r)
                    fencei_dcache_flush_sent_r <= 1'b1;
                if (icache_invalidate_done && fencei_dcache_flush_sent_r && !fencei_icache_inv_sent_r)
                    fencei_icache_inv_sent_r <= 1'b1;
            end
        end
    end

    // ── sfence.vma sequencing ──
    // Sequence: dcache flush (writeback+invalidate) → icache invalidate → TLB flush → done
    // The dcache writeback ensures all previous stores (including page table writes)
    // are globally visible in main memory before the TLB is invalidated.
    reg sfence_dcache_flush_sent_r;
    reg sfence_icache_inv_sent_r;
    reg sfence_tlb_flush_sent_r;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            sfence_dcache_flush_sent_r  <= 1'b0;
            sfence_icache_inv_sent_r    <= 1'b0;
            sfence_tlb_flush_sent_r     <= 1'b0;
        end else begin
            if (!sfence_vma_req) begin
                sfence_dcache_flush_sent_r  <= 1'b0;
                sfence_icache_inv_sent_r    <= 1'b0;
                sfence_tlb_flush_sent_r     <= 1'b0;
            end else begin
                if (dcache_flush_done && !sfence_dcache_flush_sent_r)
                    sfence_dcache_flush_sent_r <= 1'b1;
                if (icache_invalidate_done && sfence_dcache_flush_sent_r && !sfence_icache_inv_sent_r)
                    sfence_icache_inv_sent_r <= 1'b1;
                if (mmu_sfence_done && sfence_dcache_flush_sent_r && sfence_icache_inv_sent_r && !sfence_tlb_flush_sent_r)
                    sfence_tlb_flush_sent_r <= 1'b1;
            end
        end
    end

    // ── Combined cache maintenance requests ──
    // fencei and sfence_vma are mutually exclusive (controller is in one state at a time),
    // so OR-ing their requests is safe.
    assign dcache_flush_req      = (fencei_req && !fencei_dcache_flush_sent_r) ||
                                   (sfence_vma_req && !sfence_dcache_flush_sent_r);
    assign icache_invalidate_req = (fencei_req && fencei_dcache_flush_sent_r && !fencei_icache_inv_sent_r) ||
                                   (sfence_vma_req && sfence_dcache_flush_sent_r && !sfence_icache_inv_sent_r);
    assign icache_flush_req      = trap_enter_valid ||
                                   trap_return_valid ||
                                   (exe_valid && exe_done && exe_is_ctrl_flow && exe_branch_taken);

    assign fencei_done     = fencei_dcache_flush_sent_r && fencei_icache_inv_sent_r;
    assign sfence_vma_done = sfence_dcache_flush_sent_r && sfence_icache_inv_sent_r && sfence_tlb_flush_sent_r;

    // ── sfence.vma pulse to MMU ──
    // Send a one-cycle pulse to the MMU to trigger TLB flush ONLY after
    // dcache flush and icache invalidate are complete.  This ensures all
    // previous stores are globally visible before TLB entries are discarded.
    reg sfence_tlb_pulse_sent_r;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            sfence_tlb_pulse_sent_r <= 1'b0;
        else if (!sfence_vma_req)
            sfence_tlb_pulse_sent_r <= 1'b0;
        else if (sfence_dcache_flush_sent_r && sfence_icache_inv_sent_r && !sfence_tlb_pulse_sent_r)
            sfence_tlb_pulse_sent_r <= 1'b1;
    end
    wire sfence_vma_to_mmu_pulse = sfence_vma_req && sfence_dcache_flush_sent_r && sfence_icache_inv_sent_r && !sfence_tlb_pulse_sent_r;

    // PTW A/D bit writeback coherency removed — PTW no longer writes PTEs
    // (A/D bits are handled by software page fault path). No dcache line
    // invalidation is needed after PTW completes.



    icache_ctrl u_icache_wrap (
        .clk(clk),
        .resetn(resetn),

        .cpu_req_valid(if_valid),
        .cpu_req_addr(mmu_inst_paddr),
        .cpu_req_vaddr(fetch_vaddr),
        .mmu_ready(mmu_inst_ready),
        .flush_req(icache_flush_req),
        .cpu_req_data(instData_32_mux),
        .cpu_req_ready(inst_valid_mux),

        .mmio_req(icache_mmio_req),
        .mmio_accept(icache_mmio_accept),
        .mmio_addr(),
        .mmio_data(ahb_inst_data),
        .mmio_valid(ahb_inst_valid),

        .refill_req(icache_refill_req),
        .refill_addr(icache_refill_addr),
        .refill_data(icache_refill_data),
        .refill_valid(icache_refill_valid),
        .refill_resp_addr(icache_refill_resp_addr),

        .invalidate_req(icache_invalidate_req),
        .invalidate_done(icache_invalidate_done),
        .dbg_state(icache_dbg_state)
    );

    cpu_fetch u_fetch(
        .clk(clk),
        .resetn(resetn),
        .if_valid(if_valid),
        .init_sig(init_sig),
        .pc(pc),
        .instData_32(instData_32_mux),
        .inst_valid(inst_valid_mux),
        .instAddr_32(fetch_vaddr),
        .if_done(if_done),
        .if_id_bus(if_id_bus),
        .if_pc(if_pc),
        .if_inst(if_inst)
    );

    cpu_decode u_decode(
        .id_valid(id_valid),
        .if_id_bus_r(if_id_bus_r),
        .rs1_value(rs1_value),
        .rs2_value(rs2_value),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs3_addr(frs3_addr),
        .id_done(id_done),
        .illegal_inst(dec_illegal),
        .dec_is_branch(dec_is_branch),
        .dec_need_exe(dec_need_exe),
        .id_exe_bus(id_exe_bus),
        .id_pc(id_pc_wire),
        .id_inst(id_inst_wire),
        .dec_is_csr(dec_is_csr),
        .dec_is_ecall(dec_is_ecall),
        .dec_is_ebreak(dec_is_ebreak),
        .dec_is_mret(dec_is_mret),
        .dec_is_sret(dec_is_sret),
        .dec_is_nop_like(dec_is_nop_like),
        .dec_is_fencei(dec_is_fencei),
        .dec_is_sfence_vma(dec_is_sfence_vma),
        .dec_csr_addr(dec_csr_addr),
        .dec_csr_funct3(dec_csr_funct3),
        .dec_csr_addr_valid(dec_csr_addr_valid),
        .dec_csr_access_ok(dec_csr_access_ok),
        .priv_mode(priv_mode),
        .csr_mstatus(csr_mstatus)
    );

    // Float register addresses: same as integer rs1/rs2 for FPU instructions
    // frs3_addr comes from cpu_decode rs3 output (inst[31:27] for FMA R4 format)
    assign frs1_addr = rs1_addr;
    assign frs2_addr = rs2_addr;

    // dbg_mu wires must be declared before cpu_execute instantiation
    wire        dbg_mu_active_w;
    wire        dbg_mu_req_valid_w;
    wire        dbg_mu_ready_w;
    wire        dbg_mu_busy_w;
    wire        dbg_mu_result_valid_w;
    wire [2:0]  dbg_mu_funct3_w;
    wire        dbg_exe_is_mu_w;

    cpu_execute u_execute(
        .clk(clk),
        .resetn(resetn),
        .exe_valid(exe_valid),
        .id_exe_bus_r(id_exe_bus_r),
        .csr_rdata(csr_read_data),
        .csr_frm(csr_frm),
        .frs1_value(frs1_value),
        .frs2_value(frs2_value),
        .frs3_value(frs3_value),
        .trap_pending(trap_pending),
        .exe_done(exe_done),
        .exe_mem_bus(exe_mem_bus),
        .exe_branch_taken(exe_branch_taken),
        .exe_branch_target(exe_branch_target),
        .exe_is_ctrl_flow(exe_is_ctrl_flow),
        .exe_is_branch(exe_is_branch),
        .exe_need_mem(exe_need_mem),
        .exe_pc(exe_pc),
        .exe_inst(exe_inst),
        .exe_misalign_valid(exe_misalign_valid),
        .exe_misalign_target(exe_misalign_target),
        .exe_csr_wen(),
        .exe_csr_waddr(),
        .exe_csr_wdata(),
        .exe_csr_old_val(),
        .dbg_mu_active(dbg_mu_active_w),
        .dbg_mu_req_valid(dbg_mu_req_valid_w),
        .dbg_mu_ready(dbg_mu_ready_w),
        .dbg_mu_busy(dbg_mu_busy_w),
        .dbg_mu_result_valid(dbg_mu_result_valid_w),
        .dbg_mu_funct3(dbg_mu_funct3_w),
        .dbg_exe_is_mu(dbg_exe_is_mu_w)
    );

    wire        mem_hwrite;
    wire [2:0]  mem_hsize;
    wire [31:0] mem_dataAddr_32;
    wire [31:0] mem_writeData_32;

    wire [31:0] readData_32_mux;
    wire        data_valid_mux;

    wire [31:0] dcache_mmio_addr;
    wire [31:0] dcache_mmio_wdata;
    wire        dcache_mmio_hwrite;
    wire [2:0]  dcache_mmio_hsize;
    wire        dcache_mmio_req;
    wire        dcache_mmio_accept;

    wire [31:0] ahb_data_rdata;
    wire        ahb_data_valid;
    wire        dcache_refill_req;
    wire [31:0] dcache_refill_addr;
    wire [255:0] dcache_refill_data;
    wire        dcache_refill_valid;
    wire        dcache_refill_done;
    wire        dcache_refill_error;

    wire        dcache_wb_req;
    wire [31:0] dcache_wb_addr;
    wire [255:0] dcache_wb_data;
    wire        dcache_wb_valid;
    wire        dcache_wb_done;
    wire        dcache_wb_error;
    wire        dbg_dcache_lh_valid_w;
    wire [31:0] dbg_dcache_lh_data_w;
    wire [31:0] dbg_dcache_lh_count_w;
    wire        dbg_dcache_rf_valid_w;
    wire [31:0] dbg_dcache_rf_data_w;
    wire [31:0] dbg_dcache_rf_count_w;
    wire        dbg_dcache_wb_valid_w;
    wire [31:0] dbg_dcache_wb_data_w;
    wire [31:0] dbg_dcache_wb_count_w;

    wire        bridge_icache_error;
    wire        bridge_dcache_error;
    wire        bridge_dcache_error_is_store;
    wire [31:0] bridge_bus_error_addr;

`ifdef SIMULATION
    localparam [31:0] DBG_WATCH_PADDR = 32'h8000_21FC;
    localparam [31:0] DBG_FOCUS_STORE_PC0 = 32'h8000_00E0;
    localparam [31:0] DBG_FOCUS_STORE_PC1 = 32'h8000_0108;
    localparam [31:0] DBG_FOCUS_LOAD_PC0  = 32'h8000_00F8;
`else
    localparam [31:0] DBG_WATCH_PADDR = 32'h807B_21FC;
    localparam [31:0] DBG_FOCUS_STORE_PC0 = 32'hC00F_E334;
    localparam [31:0] DBG_FOCUS_STORE_PC1 = 32'hC00F_E580;
    localparam [31:0] DBG_FOCUS_LOAD_PC0  = 32'hC00F_E570;
`endif
    wire dbg_focus_store_pc_match = (exe_pc == DBG_FOCUS_STORE_PC0) || (exe_pc == DBG_FOCUS_STORE_PC1);
    wire dbg_focus_load_pc_match  = (exe_pc == DBG_FOCUS_LOAD_PC0);
    wire dbg_focus_load_mem_pc_match = (mem_pc == DBG_FOCUS_LOAD_PC0);
    wire dbg_focus_load_wb_pc_match = (wb_pc == DBG_FOCUS_LOAD_PC0);
    wire dbg_focus_store_hit = exe_valid && dbg_focus_store_pc_match;
    wire dbg_focus_load_hit  = exe_valid && dbg_focus_load_pc_match;
    wire dbg_focus_load_wb_hit = wb_valid && dbg_focus_load_wb_pc_match;
    wire [31:0] dbg_focus_store_status_w = {
        14'b0,
        exe_mem_bus.wb_rd,
        priv_mode,
        exe_mem_bus.wb_we,
        exe_mem_bus.is_store,
        exe_mem_bus.is_load,
        exe_need_mem,
        exe_done,
        exe_valid
    };
    wire [31:0] dbg_focus_load_status_w = {
        14'b0,
        exe_mem_bus.wb_rd,
        priv_mode,
        exe_mem_bus.wb_we,
        exe_mem_bus.is_store,
        exe_mem_bus.is_load,
        exe_need_mem,
        exe_done,
        exe_valid
    };
    wire [31:0] dbg_focus_load_wb_status_w = {
        22'b0,
        rf_waddr,
        rf_wen,
        mem_wb_bus_r.wb_we,
        wb_valid,
        mem_wb_bus_r.is_csr,
        mem_wb_bus_r.is_jal_like
    };
    wire dbg_watch_store_commit = data_valid_mux && mem_en && mem_hwrite &&
                                  mmu_data_ready &&
                                  ((mmu_data_paddr == DBG_WATCH_PADDR) || dbg_focus_store_pc_match);
    wire dbg_watch_load_commit = data_valid_mux && mem_en && !mem_hwrite &&
                                 dbg_focus_load_mem_pc_match;
    wire [31:0] dbg_watch_load_status_w = {
        26'b0,
        dbg_load_mem_unsigned_w,
        dbg_load_mem_size_w,
        dbg_load_addr_w[1:0]
    };
    wire dbg_last_mmio_fire = dcache_mmio_req && dcache_mmio_accept;
    reg        dbg_last_mmio_valid_r;
    reg [31:0] dbg_last_mmio_pc_r;
    reg        dbg_last_mmio_we_r;
    reg [31:0] dbg_last_mmio_addr_r;
    reg [2:0]  dbg_last_mmio_hsize_r;
    reg [31:0] dbg_last_mmio_wdata_r;
    reg [31:0] dbg_last_mmio_rdata_r;
    reg [31:0] dbg_last_mmio_caller_pc_r;
    reg [31:0] dbg_last_mmio_count_r;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            dbg_watch_valid_r <= 1'b0;
            dbg_watch_pc_r    <= 32'b0;
            dbg_watch_inst_r  <= 32'b0;
            dbg_watch_vaddr_r <= 32'b0;
            dbg_watch_paddr_r <= 32'b0;
            dbg_watch_wdata_r <= 32'b0;
            dbg_watch_count_r <= 32'b0;
            dbg_watch_load_valid_r  <= 1'b0;
            dbg_watch_load_pc_r     <= 32'b0;
            dbg_watch_load_rdata_r  <= 32'b0;
            dbg_watch_load_wbdata_r <= 32'b0;
            dbg_watch_load_count_r  <= 32'b0;
            dbg_watch_load_status_r <= 32'b0;
            dbg_focus_store_valid_r  <= 1'b0;
            dbg_focus_store_pc_r     <= 32'b0;
            dbg_focus_store_inst_r   <= 32'b0;
            dbg_focus_store_vaddr_r  <= 32'b0;
            dbg_focus_store_paddr_r  <= 32'b0;
            dbg_focus_store_wdata_r  <= 32'b0;
            dbg_focus_store_status_r <= 32'b0;
            dbg_focus_load_valid_r   <= 1'b0;
            dbg_focus_load_pc_r      <= 32'b0;
            dbg_focus_load_inst_r    <= 32'b0;
            dbg_focus_load_paddr_r   <= 32'b0;
            dbg_focus_load_rdata_r   <= 32'b0;
            dbg_focus_load_status_r  <= 32'b0;
            dbg_focus_load_wb_valid_r  <= 1'b0;
            dbg_focus_load_wb_pc_r     <= 32'b0;
            dbg_focus_load_wb_status_r <= 32'b0;
            dbg_focus_load_wb_rfdata_r <= 32'b0;
            dbg_focus_load_wb_s2_r     <= 32'b0;
            dbg_last_mmio_valid_r      <= 1'b0;
            dbg_last_mmio_pc_r         <= 32'b0;
            dbg_last_mmio_we_r         <= 1'b0;
            dbg_last_mmio_addr_r       <= 32'b0;
            dbg_last_mmio_hsize_r      <= 3'b0;
            dbg_last_mmio_wdata_r      <= 32'b0;
            dbg_last_mmio_rdata_r      <= 32'b0;
            dbg_last_mmio_caller_pc_r  <= 32'b0;
            dbg_last_mmio_count_r      <= 32'b0;
        end else begin
            if (dbg_focus_store_hit) begin
                dbg_focus_store_valid_r  <= 1'b1;
                dbg_focus_store_pc_r     <= exe_pc;
                dbg_focus_store_inst_r   <= exe_inst;
                dbg_focus_store_vaddr_r  <= exe_mem_bus.result_reg;
                dbg_focus_store_paddr_r  <= gpr_s2_w;
                dbg_focus_store_wdata_r  <= exe_mem_bus.rs2_value;
                dbg_focus_store_status_r <= dbg_focus_store_status_w;
            end
            if (dbg_focus_load_hit) begin
                dbg_focus_load_valid_r  <= 1'b1;
                dbg_focus_load_pc_r     <= exe_pc;
                dbg_focus_load_inst_r   <= exe_inst;
                dbg_focus_load_paddr_r  <= exe_mem_bus.result_reg;
                dbg_focus_load_rdata_r  <= gpr_s1_w;
                dbg_focus_load_status_r <= dbg_focus_load_status_w;
            end
            if (dbg_focus_load_wb_hit) begin
                dbg_focus_load_wb_valid_r  <= 1'b1;
                dbg_focus_load_wb_pc_r     <= wb_pc;
                dbg_focus_load_wb_status_r <= dbg_focus_load_wb_status_w;
                dbg_focus_load_wb_rfdata_r <= actual_rf_wdata;
                dbg_focus_load_wb_s2_r     <= gpr_s2_w;
            end
            if (dbg_watch_store_commit) begin
                dbg_watch_valid_r <= 1'b1;
                dbg_watch_pc_r    <= mem_pc;
                dbg_watch_inst_r  <= mem_inst;
                dbg_watch_vaddr_r <= mem_dataAddr_32;
                dbg_watch_paddr_r <= mmu_data_paddr;
                dbg_watch_wdata_r <= mem_writeData_32;
                dbg_watch_count_r <= dbg_watch_count_r + 32'd1;
            end else if (dbg_watch_load_commit) begin
                dbg_watch_load_valid_r  <= 1'b1;
                dbg_watch_load_pc_r     <= mem_pc;
                dbg_watch_load_rdata_r  <= dbg_load_raw_rdata_w;
                dbg_watch_load_wbdata_r <= dbg_load_value_w;
                dbg_watch_load_count_r  <= dbg_watch_load_count_r + 32'd1;
                dbg_watch_load_status_r <= dbg_watch_load_status_w;
            end
            if (dbg_last_mmio_fire) begin
                dbg_last_mmio_valid_r <= 1'b1;
                dbg_last_mmio_pc_r    <= mem_pc;
                dbg_last_mmio_we_r    <= dcache_mmio_hwrite;
                dbg_last_mmio_addr_r  <= dcache_mmio_addr;
                dbg_last_mmio_hsize_r <= dcache_mmio_hsize;
                dbg_last_mmio_wdata_r <= dcache_mmio_wdata;
                dbg_last_mmio_rdata_r <= ahb_data_rdata;
                dbg_last_mmio_caller_pc_r <= gpr_ra;
                dbg_last_mmio_count_r <= dbg_last_mmio_count_r + 32'd1;
            end
        end
    end

    dcache_ctrl u_dcache_wrap (
        .clk(clk),
        .resetn(resetn),

        .cpu_req_valid(mem_en),
        .cpu_req_addr(mmu_data_paddr),
        .cpu_req_vaddr(mem_dataAddr_32),
        .mmu_ready(mmu_data_ready),
        .cpu_req_wdata(mem_writeData_32),
        .cpu_req_hwrite(mem_hwrite),
        .cpu_req_hsize(mem_hsize),
        .cpu_req_rdata(readData_32_mux),
        .cpu_req_ready(data_valid_mux),

        .mmio_req(dcache_mmio_req),
        .mmio_accept(dcache_mmio_accept),
        .mmio_addr(dcache_mmio_addr),
        .mmio_wdata(dcache_mmio_wdata),
        .mmio_hwrite(dcache_mmio_hwrite),
        .mmio_hsize(dcache_mmio_hsize),
        .mmio_rdata(ahb_data_rdata),
        .mmio_valid(ahb_data_valid),

        .refill_req(dcache_refill_req),
        .refill_addr(dcache_refill_addr),
        .refill_data(dcache_refill_data),
        .refill_valid(dcache_refill_valid),
        .refill_done(dcache_refill_done),
        .refill_error(dcache_refill_error),

        .wb_req(dcache_wb_req),
        .wb_addr(dcache_wb_addr),
        .wb_data(dcache_wb_data),
        .wb_valid(dcache_wb_valid),
        .wb_done(dcache_wb_done),
        .wb_error(dcache_wb_error),

        .flush_req(dcache_flush_req),
        .flush_done(dcache_flush_done),

        // PTW request port (priority over CPU requests)
        .ptw_req_valid(ptw_cache_req),
        .ptw_req_addr(ptw_cache_addr),
        .ptw_req_vaddr(ptw_cache_addr),  // PIPT: PTW uses physical address for both index and tag
        .ptw_req_ready(ptw_cache_ready),
        .ptw_req_rdata(ptw_cache_rdata),
        .ptw_req_fault(ptw_cache_fault),

        .dbg_watch_lh_valid(dbg_dcache_lh_valid_w),
        .dbg_watch_lh_data(dbg_dcache_lh_data_w),
        .dbg_watch_lh_count(dbg_dcache_lh_count_w),
        .dbg_watch_rf_valid(dbg_dcache_rf_valid_w),
        .dbg_watch_rf_data(dbg_dcache_rf_data_w),
        .dbg_watch_rf_count(dbg_dcache_rf_count_w),
        .dbg_watch_wb_valid(dbg_dcache_wb_valid_w),
        .dbg_watch_wb_data(dbg_dcache_wb_data_w),
        .dbg_watch_wb_count(dbg_dcache_wb_count_w)
    );

    cpu_mem u_mem(
        .clk(clk),
        .resetn(resetn),
        .mem_valid(mem_valid),
        .exe_mem_bus_r(exe_mem_bus_r),
        .frs2_value(frs2_value),
        .trap_enter(trap_enter_valid),
        .mem_en(mem_en),
        .mem_hwrite(mem_hwrite),
        .mem_hsize(mem_hsize),
        .dataAddr_32(mem_dataAddr_32),
        .writeData_32(mem_writeData_32),
        .readData_32(readData_32_mux),
        .data_valid(data_valid_mux),
        .mem_done(mem_done),
        .mem_wb_bus(mem_wb_bus),
        .mem_pc(mem_pc),
        .mem_inst(mem_inst),
        .mem_misalign_load(mem_misalign_load),
        .mem_misalign_store(mem_misalign_store),
        .mem_misalign_addr(mem_misalign_addr),
        .mem_data_access(mem_data_access),
        .dbg_load_mem_size(dbg_load_mem_size_w),
        .dbg_load_mem_unsigned(dbg_load_mem_unsigned_w),
        .dbg_load_addr(dbg_load_addr_w),
        .dbg_load_raw_rdata(dbg_load_raw_rdata_w),
        .dbg_load_value(dbg_load_value_w)
    );

    cpu_wb u_wb(
        .wb_valid(wb_valid),
        .mem_wb_bus_r(mem_wb_bus_r),
        .rf_wen(rf_wen),
        .rf_waddr(rf_waddr),
        .rf_wdata(rf_wdata),
        .wb_done(wb_done),
        .wb_is_jal_like(wb_is_jal_like),
        .wb_pc_plus4(wb_pc_plus4),
        .wb_pc(wb_pc),
        .wb_inst(wb_inst),
        .fp_wen(fp_wen),
        .fp_waddr(fp_waddr),
        .fp_wdata(fp_wdata),
        .wb_fflags(wb_fflags)
    );

    cpu_regfile u_regfile(
        .clk(clk),
        .resetn(resetn),
        .wen(rf_wen),
        .raddr1(rs1_addr),
        .raddr2(rs2_addr),
        .waddr(rf_waddr),
        .wdata(actual_rf_wdata),
        .rdata1(rs1_value),
        .rdata2(rs2_value),
        .dbg_raddr(rf_addr),
        .dbg_rdata(rf_data),
        .dbg_raddr2(5'd4),       // tp = x4
        .dbg_rdata2(gpr_tp_w),
        .dbg_raddr3(5'd2),       // sp = x2
        .dbg_rdata3(gpr_sp_w),
        .dbg_x1(gpr_ra_w),
        .dbg_x9(gpr_s1_w),
        .dbg_x10(gpr_a0_w),
        .dbg_x11(gpr_a1_w),
        .dbg_x12(gpr_a2_w),
        .dbg_x13(gpr_a3_w),
        .dbg_x14(gpr_a4_w),
        .dbg_x15(gpr_a5_w),
        .dbg_x16(gpr_a6_w),
        .dbg_x17(gpr_a7_w),
        .dbg_x18(gpr_s2_w),
        .dbg_x19(gpr_s3_w)
    );

    fpu_regfile u_fregfile(
        .clk(clk),
        .resetn(resetn),
        .wen(fp_wen),
        .raddr1(frs1_addr),
        .raddr2(frs2_addr),
        .raddr3(frs3_addr),
        .waddr(fp_waddr),
        .wdata(fp_wdata),
        .rdata1(frs1_value),
        .rdata2(frs2_value),
        .rdata3(frs3_value),
        .dbg_faddr(rf_addr),
        .dbg_fdata(fp_dbg_data)
    );

    cpu_trap_csr u_trap_csr(
        .clk              (clk),
        .resetn            (resetn),
        .id_valid         (id_valid),
        .id_done          (id_done),
        .dec_illegal      (dec_illegal),
        .dec_is_ecall     (dec_is_ecall),
        .dec_is_ebreak    (dec_is_ebreak),
        .id_pc            (id_pc_wire),
        .id_inst          (id_inst_wire),
        .dec_csr_addr     (dec_csr_addr),
        .mem_valid        (mem_valid),
        .mem_done         (mem_done),
        .mem_misalign_load(mem_misalign_load),
        .mem_misalign_store(mem_misalign_store),
        .mem_misalign_addr(mem_misalign_addr),
        .mem_pc           (mem_pc),
        .id_exe_bus_r     (id_exe_bus_r),
        .csr_valid        (csr_valid),
        .trap_enter_valid (trap_enter_valid),
        .trap_return_valid(trap_return_valid),
        .priv_mode        (priv_mode),
        .timer_irq        (timer_irq),
        .ext_meip_in      (ext_meip_in),
        .ext_seip_in      (ext_seip_in),
        .ext_msip_in      (ext_msip_in),
        .ext_mtime        (ext_mtime),
        .current_pc       (pc),
        .exe_misalign_valid(exe_misalign_valid),
        .exe_misalign_target(exe_misalign_target),
        .exe_pc           (exe_pc),
        // BUG-MMU-3 REVERTED: PTW access faults (cause 1/5/7) routed as page faults
        // to S-mode (kernel handles them). Original fix routed them as access faults
        // to M-mode, but MEDELEG doesn't delegate bits 1/5/7, so OpenSBI received
        // them and couldn't handle them → MMU translation errors → kernel jump to BSS.
        .inst_access_fault(bridge_icache_error || (mmu_inst_page_fault && (mmu_inst_pf_cause == 4'd1))),
        .inst_access_fault_addr(bridge_icache_error ? bridge_bus_error_addr : mmu_inst_pf_vaddr),
        .load_access_fault((bridge_dcache_error && !bridge_dcache_error_is_store) ||
                           (mmu_data_page_fault && (mmu_data_pf_cause == 4'd5))),
        .load_access_fault_addr(bridge_dcache_error ? bridge_bus_error_addr : mmu_data_pf_vaddr),
        .store_access_fault((bridge_dcache_error && bridge_dcache_error_is_store) ||
                            (mmu_data_page_fault && (mmu_data_pf_cause == 4'd7)) ||
                            pmp_data_violation),
        .store_access_fault_addr(bridge_dcache_error ? bridge_bus_error_addr : mmu_data_pf_vaddr),
        .mem_access_fault_pc(exe_pc),
        .inst_page_fault(mmu_inst_page_fault && (mmu_inst_pf_cause == 4'd12)),
        .inst_page_fault_vaddr(mmu_inst_pf_vaddr),
        // BUG-10 fix: 移除 mem_en 门控 — unified MMU uses translate_req gating instead,
        // so page faults are only generated when CPU is in the correct state.
        // d_page_fault 不会产生，因此 mem_en 门控是冗余的。保留 mem_en 会在 PTW 完成
        // 后 mem_en 已变 0 时吞掉 PF 信号。
        .load_page_fault(mmu_data_page_fault && (mmu_data_pf_cause == 4'd13)),
        .load_page_fault_vaddr(mmu_data_pf_vaddr),
        .store_page_fault(mmu_data_page_fault && (mmu_data_pf_cause == 4'd15)),
        .store_page_fault_vaddr(mmu_data_pf_vaddr),
        .mem_page_fault_pc(mem_pc),
        .cycle_en         (cycle_en),
        .inst_retire      (inst_retire),
        .exception_at_decode(exception_at_decode),
        .trap_pending     (trap_pending),
        .csr_read_data    (csr_read_data),
        .csr_wb_bus       (csr_wb_bus),
        .trap_pc          (trap_csr_pc),
        .csr_pc_plus4     (csr_pc_plus4_out),
        .target_priv      (target_priv),
        .inst_access_fault_pending(inst_access_fault_pending),
        .data_access_fault_pending(data_access_fault_pending),
        .inst_page_fault_pending(inst_page_fault_pending),
        .data_page_fault_pending(data_page_fault_pending),
        .csr_mstatus      (csr_mstatus),
        .csr_mie          (csr_mie),
        .csr_mtvec        (csr_mtvec),
        .csr_mepc         (csr_mepc),
        .csr_mcause       (csr_mcause),
        .csr_mip          (csr_mip),
        .csr_medeleg      (csr_medeleg),
        .csr_mideleg      (csr_mideleg),
        .csr_sstatus      (csr_sstatus),
        .csr_sie          (csr_sie),
        .csr_stvec        (csr_stvec),
        .csr_sscratch     (csr_sscratch),
        .csr_sepc         (csr_sepc),
        .csr_scause       (csr_scause),
        .csr_stval        (csr_stval),
        .csr_sip          (csr_sip),
        .csr_satp         (csr_satp),
        .csr_mcounteren   (csr_mcounteren),
        .csr_scounteren   (csr_scounteren),
        .csr_access_ok    (csr_access_ok),
        .csr_fflags       (),
        .csr_frm          (csr_frm),
        .csr_pmpcfg0      (csr_pmpcfg0),
        .csr_pmpcfg1      (csr_pmpcfg1),
        .csr_pmpcfg2      (csr_pmpcfg2),
        .csr_pmpcfg3      (csr_pmpcfg3),
        .csr_pmpaddr0     (csr_pmpaddr0),
        .csr_pmpaddr1     (csr_pmpaddr1),
        .csr_pmpaddr2     (csr_pmpaddr2),
        .csr_pmpaddr3     (csr_pmpaddr3),
        .csr_pmpaddr4     (csr_pmpaddr4),
        .csr_pmpaddr5     (csr_pmpaddr5),
        .csr_pmpaddr6     (csr_pmpaddr6),
        .csr_pmpaddr7     (csr_pmpaddr7),
        .csr_pmpaddr8     (csr_pmpaddr8),
        .csr_pmpaddr9     (csr_pmpaddr9),
        .csr_pmpaddr10    (csr_pmpaddr10),
        .csr_pmpaddr11    (csr_pmpaddr11),
        .csr_pmpaddr12    (csr_pmpaddr12),
        .csr_pmpaddr13    (csr_pmpaddr13),
        .csr_pmpaddr14    (csr_pmpaddr14),
        .csr_pmpaddr15    (csr_pmpaddr15),
        .fflags_wdata     (wb_fflags),
        .fflags_wen       (wb_valid && (wb_fflags != 5'b0)),
        // Extended debug outputs
        .hw_trap_epc      (hw_trap_epc_w),
        .hw_trap_cause    (hw_trap_cause_w),
        .hw_trap_tval     (hw_trap_tval_w)
    );

    // Unified MMU: single instance with unified translate interface
    MMU u_mmu(
        .clk(clk),
        .resetn(resetn),
        // Unified translate request interface
        .translate_req(mmu_translate_req),
        .translate_vaddr(mmu_translate_vaddr),
        .translate_access(mmu_translate_access),
        .translate_priv(priv_mode),
        .translate_satp(csr_satp),
        .translate_sum(csr_mstatus[18]),       // mstatus.SUM
        .translate_mxr(csr_mstatus[19]),       // mstatus.MXR
        // Unified translate result
        .translate_done(mmu_translate_done),
        .translate_paddr(mmu_translate_paddr),
        .translate_fault(mmu_translate_fault),
        .translate_cause(mmu_translate_cause),
        .translate_vaddr_out(mmu_translate_vaddr_out),
        // Backward-compat i-side outputs (not used — core_top drives mmu_inst_* directly)
        .i_paddr(),
        .i_ready(),
        .i_miss(),
        .i_page_fault(),
        .i_pf_cause(),
        .i_pf_vaddr(),
        // Backward-compat d-side outputs (not used — core_top drives mmu_data_* directly)
        .d_paddr(),
        .d_ready(),
        .d_miss(),
        .d_page_fault(),
        .d_pf_cause(),
        .d_pf_vaddr(),
        // shared CSR
        .priv_mode(priv_mode),
        .satp(csr_satp),
        .mstatus_sum(csr_mstatus[18]),
        .mstatus_mxr(csr_mstatus[19]),
        // single PTW cache interface
        .ptw_cache_req(ptw_cache_req),
        .ptw_cache_addr(ptw_cache_addr),
        .ptw_cache_ready(ptw_cache_ready),
        .ptw_cache_rdata(ptw_cache_rdata),
        .ptw_cache_fault(ptw_cache_fault),
        // PMP check interface (pass-through to PTW)
        .pmp_grant(ptw_pmp_grant),
        .pmp_fault_type(ptw_pmp_fault_type),
        // flush
        .sfence_vma(sfence_vma_to_mmu_pulse),
        // sfence completion
        .sfence_done(mmu_sfence_done),
        .dbg_i_walk_active(mmu_dbg_i_walk_active),
        .dbg_pending_i_walk(mmu_dbg_pending_i_walk),
        .dbg_nb_i_state(mmu_dbg_i_state),
        .dbg_nb_i_input_changed(mmu_dbg_i_input_changed),
        .dbg_nb_i_latched_vaddr(mmu_dbg_i_latched_vaddr),
        .dbg_nb_i_latched_sv32(mmu_dbg_i_sv32),
        .dbg_i_tlb_hit(mmu_dbg_i_tlb_hit),
        .dbg_i_tlb_valid(mmu_dbg_i_tlb_valid),
        .dbg_i_tlb_perm_fault(mmu_dbg_i_tlb_perm_fault),
        .dbg_walk_state(mmu_dbg_walk_state),
        .dbg_nb_d_state(mmu_dbg_d_state),
        .dbg_d_tlb_hit(mmu_dbg_d_tlb_hit),
        .dbg_d_tlb_valid(mmu_dbg_d_tlb_valid),
        .dbg_d_tlb_perm_fault(mmu_dbg_d_tlb_perm_fault),
        .dbg_d_input_changed(mmu_dbg_d_input_changed),
        .dbg_d_latched_vaddr(mmu_dbg_d_latched_vaddr),
        .dbg_d_latched_sv32(mmu_dbg_d_latched_sv32),
        .dbg_pending_d_walk(mmu_dbg_pending_d_walk),
        .dbg_d_pf_from_ptw(mmu_dbg_d_pf_from_ptw),
        .dbg_d_tlb_miss(mmu_dbg_d_tlb_miss)
    );

    // ===================================================================
    // Firmware Region Protection — block S/U-mode writes to OpenSBI code
    // ===================================================================
    // Simple hardcoded check: deny S/U-mode stores to 0x80000000-0x803fffff
    // (4MB firmware region). This prevents kernel memory init from overwriting
    // OpenSBI's trap handler at 0x80000418.
    // M-mode has full access. Loads and instruction fetches are always allowed.
    assign pmp_data_violation = 1'b0; // DISABLED for testing

    // PTW PMP check — placeholder: grant all accesses until PMP is fully implemented.
    // TODO: Connect ptw_pmp_grant to actual PMP CSR check (csr_pmpcfg0-3, csr_pmpaddr0-15)
    //       against ptw_cache_addr. PMP check should use S-mode privilege for read access.
    //       If no PMP entries are configured (all zero), grant=1 (no PMP restriction).
    assign ptw_pmp_grant     = 1'b1;  // Placeholder: always grant
    assign ptw_pmp_fault_type = 2'b00; // Placeholder: no fault type

    cpu_bus_bridge u_bus_bridge(
        .clk              (clk),
        .resetn            (resetn),
        .icache_mmio_req  (icache_mmio_req),
        .icache_mmio_accept(icache_mmio_accept),
        .icache_mmio_addr (mmu_inst_paddr),
        .dcache_mmio_req  (dcache_mmio_req),
        .dcache_mmio_accept(dcache_mmio_accept),
        .dcache_mmio_addr (dcache_mmio_addr),
        .dcache_mmio_wdata(dcache_mmio_wdata),
        .dcache_mmio_hwrite(dcache_mmio_hwrite),
        .dcache_mmio_hsize(dcache_mmio_hsize),
        .ahb_inst_data    (ahb_inst_data),
        .ahb_inst_valid   (ahb_inst_valid),
        .ahb_data_rdata   (ahb_data_rdata),
        .ahb_data_valid   (ahb_data_valid),
        .icache_refill_req  (icache_refill_req),
        .icache_refill_addr (icache_refill_addr),
        .icache_refill_data (icache_refill_data),
        .icache_refill_valid (icache_refill_valid),
        .icache_refill_resp_addr (icache_refill_resp_addr),
        .dcache_refill_req  (dcache_refill_req),
        .dcache_refill_addr (dcache_refill_addr),
        .dcache_refill_data (dcache_refill_data),
        .dcache_refill_valid (dcache_refill_valid),
        .dcache_refill_done (dcache_refill_done),
        .dcache_refill_error(dcache_refill_error),
        .dcache_wb_req      (dcache_wb_req),
        .dcache_wb_addr     (dcache_wb_addr),
        .dcache_wb_data     (dcache_wb_data),
        .dcache_wb_valid    (dcache_wb_valid),
        .dcache_wb_done     (dcache_wb_done),
        .dcache_wb_error    (dcache_wb_error),
        .awid              (awid),
        .awaddr            (awaddr),
        .awlen             (awlen),
        .awsize            (awsize),
        .awburst           (awburst),
        .awlock            (awlock),
        .awcache           (awcache),
        .awprot            (awprot),
        .awqos             (awqos),
        .awregion          (awregion),
        .awvalid           (awvalid),
        .awready           (awready),
        .wdata             (wdata),
        .wstrb             (wstrb),
        .wlast             (wlast),
        .wvalid            (wvalid),
        .wready            (wready),
        .bresp             (bresp),
        .bvalid            (bvalid),
        .bready            (bready),
        .arid              (arid),
        .araddr            (araddr),
        .arlen             (arlen),
        .arsize            (arsize),
        .arburst           (arburst),
        .arlock            (arlock),
        .arcache           (arcache),
        .arprot            (arprot),
        .arqos             (arqos),
        .arregion          (arregion),
        .arvalid           (arvalid),
        .arready           (arready),
        .rdata             (rdata),
        .rresp             (rresp),
        .rlast             (rlast),
        .rvalid            (rvalid),
        .rready            (rready),
        .icache_error     (bridge_icache_error),
        .dcache_error     (bridge_dcache_error),
        .dcache_error_is_store(bridge_dcache_error_is_store),
        .bus_error_addr   (bridge_bus_error_addr)
    );

    assign display_state = {28'b0, fsm_state};
    assign dbg_if_done = if_done;
    assign dbg_inst_valid = inst_valid_mux;
    assign dbg_mmu_i_ready = mmu_inst_ready;
    assign dbg_mmu_i_miss = mmu_inst_miss;
    assign dbg_i_page_fault = mmu_inst_page_fault;
    assign dbg_icache_state = icache_dbg_state;
    assign dbg_icache_refill_req = icache_refill_req;
    assign dbg_icache_refill_valid = icache_refill_valid;
    assign dbg_ptw_walk_active = mmu_dbg_i_walk_active;
    assign dbg_pending_i_walk = mmu_dbg_pending_i_walk;
    assign dbg_mmu_i_state = mmu_dbg_i_state;
    assign dbg_mmu_i_input_changed = mmu_dbg_i_input_changed;
    assign dbg_mmu_i_latched_vaddr = mmu_dbg_i_latched_vaddr;
    assign dbg_mmu_i_sv32 = mmu_dbg_i_sv32;
    assign dbg_mmu_i_tlb_hit = mmu_dbg_i_tlb_hit;
    assign dbg_mmu_i_tlb_valid = mmu_dbg_i_tlb_valid;
    assign dbg_mmu_i_tlb_perm_fault = mmu_dbg_i_tlb_perm_fault;
    assign dbg_mmu_walk_state = mmu_dbg_walk_state;
    assign dbg_mmu_d_state          = mmu_dbg_d_state;
    assign dbg_mmu_d_tlb_hit        = mmu_dbg_d_tlb_hit;
    assign dbg_mmu_d_tlb_valid      = mmu_dbg_d_tlb_valid;
    assign dbg_mmu_d_tlb_perm_fault = mmu_dbg_d_tlb_perm_fault;
    assign dbg_mmu_d_input_changed  = mmu_dbg_d_input_changed;
    assign dbg_mmu_d_latched_vaddr  = mmu_dbg_d_latched_vaddr;
    assign dbg_mmu_d_latched_sv32   = mmu_dbg_d_latched_sv32;
    assign dbg_mmu_d_pf_from_ptw    = mmu_dbg_d_pf_from_ptw;
    assign dbg_mmu_d_tlb_miss       = mmu_dbg_d_tlb_miss;
    assign dbg_mu_active            = dbg_mu_active_w;
    assign dbg_mu_req_valid         = dbg_mu_req_valid_w;
    assign dbg_mu_ready             = dbg_mu_ready_w;
    assign dbg_mu_busy              = dbg_mu_busy_w;
    assign dbg_mu_result_valid      = dbg_mu_result_valid_w;
    assign dbg_mu_funct3            = dbg_mu_funct3_w;
    assign dbg_exe_is_mu            = dbg_exe_is_mu_w;
    assign dbg_dmmio_req            = dcache_mmio_req;
    assign dbg_dmmio_we             = dcache_mmio_hwrite;
    assign dbg_dmmio_addr           = dcache_mmio_addr;
    assign dbg_dmmio_hsize          = dcache_mmio_hsize;
    assign dbg_dmmio_valid          = ahb_data_valid;
    assign dbg_dmmio_rdata          = ahb_data_rdata;
    assign dbg_last_mmio_valid      = dbg_last_mmio_valid_r;
    assign dbg_last_mmio_pc         = dbg_last_mmio_pc_r;
    assign dbg_last_mmio_we         = dbg_last_mmio_we_r;
    assign dbg_last_mmio_addr       = dbg_last_mmio_addr_r;
    assign dbg_last_mmio_hsize      = dbg_last_mmio_hsize_r;
    assign dbg_last_mmio_wdata      = dbg_last_mmio_wdata_r;
    assign dbg_last_mmio_rdata      = dbg_last_mmio_rdata_r;
    assign dbg_last_mmio_caller_pc  = dbg_last_mmio_caller_pc_r;
    assign dbg_last_mmio_count      = dbg_last_mmio_count_r;

    assign id_pc   = id_pc_wire;
    assign id_inst = id_inst_wire;

endmodule
