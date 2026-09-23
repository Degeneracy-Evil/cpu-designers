`timescale 1ns / 1ps
`include "core/interface/types.svh"
`include "common/bus/axi.svh"
`include "common/address_map.svh"

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
    output priv_mode_t priv_mode,
    output priv_mode_t target_priv,

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
    output        dbg_if_done,
    output        dbg_inst_valid,
    output [2:0]  dbg_icache_state,
    output        dbg_icache_refill_req,
    output        dbg_icache_refill_valid,
    output [3:0]  dbg_mmu_state,
    output        dbg_mmu_owner,
    output [31:0] dbg_mmu_req_vaddr,
    output        dbg_mmu_sv32,
    output        dbg_mmu_tlb_hit,
    output        dbg_mmu_tlb_perm_fault,
    output        dbg_mmu_ptw_active,
    output        dbg_mmu_fault_from_ptw,
    output        dbg_mu_active,
    output        dbg_mu_req_valid,
    output        dbg_mu_ready,
    output        dbg_mu_busy,
    output        dbg_mu_result_valid,
    output [2:0]  dbg_mu_funct3,
    output        dbg_exe_is_mu,
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

    reg [31:0] pc;
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
    wire exe_to_wb;
    wire        fencei_req;
    wire        icache_invalidate_done;
    wire        sfence_vma_req;

    wire dec_need_exe;
    wire dec_is_csr;
    wire dec_is_mret;
    wire dec_is_sret;
    wire dec_is_nop_like;
    wire dec_is_fencei;
    wire dec_is_sfence_vma;
    trap_return_kind_t trap_return_kind;
    wire exe_branch_taken;
    wire [31:0] exe_branch_target;
    wire exe_is_ctrl_flow;
    wire exe_is_branch;
    wire exe_need_mem;

    if_id_bus_t  if_id_bus;
    id_exe_bus_t id_exe_bus;
    exe_mem_bus_t exe_mem_bus;
    wb_bus_t      mem_wb_bus;

    if_id_bus_t  if_id_bus_r;
    id_exe_bus_t id_exe_bus_r;
    exe_mem_bus_t exe_mem_bus_r;
    wb_bus_t      mem_wb_bus_r;

    wire mem_access_valid;
    wire [31:0] mem_vaddr;
    mem_kind_t mem_kind;
    access_class_t mem_access_type;
    wire [2:0] mem_access_size;
    wire phys_req_valid;
    wire [31:0] phys_req_paddr;

    wire [31:0] mmu_inst_paddr;
    wire [31:0] mmu_data_paddr;

    wire        mmu_inst_fault;
    wire        mmu_data_fault;
    wire [3:0]  mmu_inst_fault_cause;
    wire [3:0]  mmu_data_fault_cause;
    wire [31:0] mmu_inst_fault_vaddr;
    wire [31:0] mmu_data_fault_vaddr;

    wire        mmu_inst_ready;
    wire        mmu_data_ready;
    // Single PTW bus (unified MMU)
    wire        ptw_bus_req;
    wire [31:0] ptw_bus_addr;
    wire        ptw_bus_we;
    wire [31:0] ptw_bus_wdata;
    wire [31:0] ptw_bus_rdata;
    wire        ptw_bus_done;
    wire        ptw_bus_error;
    wire        ptw_mem_done;
    wire        ptw_mem_error;

    wire        mmu_sfence_done;

    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [31:0] rs1_value;
    wire [31:0] rs2_value;

    wire rf_wen;
    wire [4:0] rf_waddr;
    wire [31:0] rf_wdata;
    wire [31:0] id_pc_plus4;
    wire [31:0] exe_pc_plus4;

    assign id_pc_plus4  = if_id_bus_r.pc_plus4;
    assign exe_pc_plus4 = id_exe_bus_r.pc_plus4;

    wb_bus_t      exe_wb_bus;
    assign exe_wb_bus = '{
        wb_we:         exe_mem_bus.wb_we,
        wb_rd:         exe_mem_bus.wb_rd,
        wb_data:       exe_mem_bus.result,
        pc:            exe_mem_bus.pc,
        inst:          exe_mem_bus.inst
    };

    wire [31:0] id_pc_wire;
    wire [31:0] id_inst_wire;

    exception_t fetch_exception;
    exception_t decode_exception;
    exception_t exe_exception;
    exception_t mem_local_exception;
    exception_t mem_external_exception;
    exception_t mem_exception;
    exception_t sync_exception_now;
    wire sync_exception_pending;
    wire interrupt_pending;
    wb_bus_t      csr_wb_bus;
    wire [31:0] csr_pc_plus4_out;

    wire cycle_en;
    assign cycle_en = ~init_sig;
    wire inst_retire;
    // Instructions without a register-writeback stage still retire.  Count
    // each instruction at its single architectural completion point.
    assign inst_retire = wb_done ||
                         (exe_valid && exe_done && exe_is_branch) ||
                         (id_valid && id_done && dec_is_nop_like) ||
                         (fencei_req && icache_invalidate_done) ||
                         (sfence_vma_req && mmu_sfence_done) ||
                         trap_return_valid;

    wire [31:0] csr_mstatus;
    wire [31:0] csr_mie;
    wire [31:0] csr_mip;
    wire [31:0] csr_medeleg;
    wire [31:0] csr_mideleg;
    wire [31:0] csr_sie;
    wire [31:0] csr_sip;
    wire [31:0] csr_mcounteren;
    wire [31:0] csr_scounteren;
    wire [127:0] pmpcfg_flat;
    wire [511:0] pmpaddr_flat;
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
    assign exe_mem_vaddr = mem_vaddr;
    assign exe_is_store  = (exe_mem_bus.mem_kind == MEM_STORE) ||
                           (exe_mem_bus.mem_kind == MEM_SC) ||
                           (exe_mem_bus.mem_kind == MEM_AMO);
    assign exe_is_load   = (exe_mem_bus.mem_kind == MEM_LOAD) ||
                           (exe_mem_bus.mem_kind == MEM_LR);

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            pc <= `SOC_BOOTROM_BASE;
            priv_mode <= PRIV_M;
            if_id_bus_r <= '0;
            id_exe_bus_r <= '0;
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
                if_id_bus_r <= '0;
                id_exe_bus_r <= '0;
                pc <= trap_csr_pc;
                priv_mode <= target_priv;
            end else if (trap_return_valid) begin
                if_id_bus_r <= '0;
                id_exe_bus_r <= '0;
                pc <= trap_csr_pc;
                priv_mode <= target_priv;
            end else if (exe_valid && exe_done) begin
                if (exe_is_ctrl_flow && exe_branch_taken) begin
                    if_id_bus_r <= '0;
                    id_exe_bus_r <= '0;
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
        .dec_need_exe(dec_need_exe),
        .dec_is_csr(dec_is_csr),
        .dec_is_mret(dec_is_mret),
        .dec_is_sret(dec_is_sret),
        .dec_is_nop_like(dec_is_nop_like),
        .dec_is_fencei(dec_is_fencei),
        .dec_is_sfence_vma(dec_is_sfence_vma),
        .fencei_done(icache_invalidate_done),
        .sfence_vma_done(mmu_sfence_done),
        .exe_is_branch(exe_is_branch),
        .exe_need_mem(exe_need_mem),
        .sync_exception_pending(sync_exception_pending),
        .interrupt_pending(interrupt_pending),
        .init_sig(init_sig),
        .if_valid(if_valid),
        .id_valid(id_valid),
        .exe_valid(exe_valid),
        .mem_valid(mem_valid),
        .wb_valid(wb_valid),
        .csr_valid(csr_valid),
        .trap_enter_valid(trap_enter_valid),
        .trap_return_valid(trap_return_valid),
        .trap_return_kind (trap_return_kind),
        .exe_to_wb(exe_to_wb),
        .fencei_req(fencei_req),
        .sfence_vma_req(sfence_vma_req),
        .state()
    );

    wire [31:0] fetch_vaddr;

    wire [31:0] instData_32_mux;
    wire        inst_valid_mux;
    wire        icache_mem_req_valid;
    wire        icache_mem_req_ready;
    wire [31:0] icache_mem_req_addr;
    wire        icache_mem_req_write;
    wire [2:0]  icache_mem_req_size;
    wire [7:0]  icache_mem_req_len;
    wire [31:0] icache_mem_req_wdata;
    wire        icache_mem_resp_valid;
    wire [255:0] icache_mem_resp_data;
    wire        icache_mem_resp_error;
    wire        icache_cpu_error;
    wire [2:0]  icache_dbg_state;

    wire        icache_flush_req;

    // FENCE.I and SFENCE.VMA use held request / completion interfaces.
    // The target modules suppress duplicate acceptance until request drops.
    assign icache_flush_req      = trap_enter_valid ||
                                   trap_return_valid ||
                                   (exe_valid && exe_done && exe_is_ctrl_flow && exe_branch_taken);

    wire fetch_pmp_allow;
    wire fetch_pma_allow;
    wire fetch_protection_deny = mmu_inst_ready &&
                                 (!fetch_pmp_allow || !fetch_pma_allow);
    pmp_checker u_fetch_pmp (
        .paddr(mmu_inst_paddr),
        .access_size(`AXI_SIZE_WORD),
        .access_type(ACCESS_FETCH),
        .effective_priv(priv_mode),
        .pmpcfg_flat(pmpcfg_flat),
        .pmpaddr_flat(pmpaddr_flat),
        .allow(fetch_pmp_allow)
    );
    pma_checker u_fetch_pma (
        .paddr(mmu_inst_paddr),
        .access_type(ACCESS_FETCH),
        .access_size(`AXI_SIZE_WORD),
        .is_atomic(1'b0),
        .is_ptw(1'b0),
        .allow(fetch_pma_allow)
    );


    icache_ctrl u_icache_wrap (
        .clk(clk),
        .resetn(resetn),

        .cpu_req_valid(if_valid && mmu_inst_ready &&
                       fetch_pmp_allow && fetch_pma_allow),
        .cpu_req_paddr(mmu_inst_paddr),
        .flush_req(icache_flush_req),
        .cpu_req_data(instData_32_mux),
        .cpu_req_ready(inst_valid_mux),

        .cpu_req_error(icache_cpu_error),
        .cpu_req_error_addr(),
        .mem_req_valid(icache_mem_req_valid),
        .mem_req_ready(icache_mem_req_ready),
        .mem_req_addr(icache_mem_req_addr),
        .mem_req_write(icache_mem_req_write),
        .mem_req_size(icache_mem_req_size),
        .mem_req_len(icache_mem_req_len),
        .mem_req_wdata(icache_mem_req_wdata),
        .mem_resp_valid(icache_mem_resp_valid),
        .mem_resp_data(icache_mem_resp_data),
        .mem_resp_error(icache_mem_resp_error),

        .invalidate_req(fencei_req),
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
        .id_done(id_done),
        .decode_exception(decode_exception),
        .dec_need_exe(dec_need_exe),
        .id_exe_bus(id_exe_bus),
        .id_pc(id_pc_wire),
        .id_inst(id_inst_wire),
        .dec_is_csr(dec_is_csr),
        .dec_is_mret(dec_is_mret),
        .dec_is_sret(dec_is_sret),
        .dec_is_nop_like(dec_is_nop_like),
        .dec_is_fencei(dec_is_fencei),
        .dec_is_sfence_vma(dec_is_sfence_vma),
        .priv_mode(priv_mode),
        .csr_mstatus(csr_mstatus),
        .csr_mcounteren(csr_mcounteren),
        .csr_scounteren(csr_scounteren)
    );

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
        .exe_done(exe_done),
        .exe_mem_bus(exe_mem_bus),
        .exe_branch_taken(exe_branch_taken),
        .exe_branch_target(exe_branch_target),
        .exe_is_ctrl_flow(exe_is_ctrl_flow),
        .exe_is_branch(exe_is_branch),
        .exe_need_mem(exe_need_mem),
        .exe_pc(exe_pc),
        .exe_inst(exe_inst),
        .exe_exception(exe_exception),
        .dbg_mu_active(dbg_mu_active_w),
        .dbg_mu_req_valid(dbg_mu_req_valid_w),
        .dbg_mu_ready(dbg_mu_ready_w),
        .dbg_mu_busy(dbg_mu_busy_w),
        .dbg_mu_result_valid(dbg_mu_result_valid_w),
        .dbg_mu_funct3(dbg_mu_funct3_w),
        .dbg_exe_is_mu(dbg_exe_is_mu_w)
    );

    wire        phys_req_write;
    wire [2:0]  phys_req_size;
    wire [31:0] phys_req_wdata;

    wire [31:0] readData_32_mux;
    wire        data_valid_mux;

    wire        dcache_mem_req_valid;
    wire        dcache_mem_req_ready;
    wire [31:0] dcache_mem_req_addr;
    wire        dcache_mem_req_write;
    wire [2:0]  dcache_mem_req_size;
    wire [7:0]  dcache_mem_req_len;
    wire [31:0] dcache_mem_req_wdata;
    wire [3:0]  dcache_mem_req_wstrb;
    wire        dcache_mem_resp_valid;
    wire [255:0] dcache_mem_resp_data;
    wire        dcache_mem_resp_error;
    wire        dcache_cpu_error;

    priv_mode_t data_effective_priv;
    assign data_effective_priv = effective_data_priv(
        priv_mode, csr_mstatus[17], priv_mode_t'(csr_mstatus[12:11]));

    wire data_pmp_allow;
    wire data_pma_allow;
    wire data_is_atomic = (mem_kind == MEM_LR) ||
                          (mem_kind == MEM_SC) ||
                          (mem_kind == MEM_AMO);
    wire data_protection_deny = mmu_data_ready &&
                                (!data_pmp_allow || !data_pma_allow);
    wire mem_access_ready = mmu_data_ready &&
                            data_pmp_allow && data_pma_allow;

    pmp_checker u_data_pmp (
        .paddr(mmu_data_paddr),
        .access_size(mem_access_size),
        .access_type(mem_access_type),
        .effective_priv(data_effective_priv),
        .pmpcfg_flat(pmpcfg_flat),
        .pmpaddr_flat(pmpaddr_flat),
        .allow(data_pmp_allow)
    );
    pma_checker u_data_pma (
        .paddr(mmu_data_paddr),
        .access_type(mem_access_type),
        .access_size(mem_access_size),
        .is_atomic(data_is_atomic),
        .is_ptw(1'b0),
        .allow(data_pma_allow)
    );

    wire ptw_pmp_allow;
    wire ptw_pma_allow;
    wire ptw_protection_deny = ptw_bus_req &&
                               (!ptw_pmp_allow || !ptw_pma_allow);
    pmp_checker u_ptw_pmp (
        .paddr(ptw_bus_addr),
        .access_size(`AXI_SIZE_WORD),
        .access_type(ptw_bus_we ? ACCESS_STORE : ACCESS_LOAD),
        .effective_priv(PRIV_S),
        .pmpcfg_flat(pmpcfg_flat),
        .pmpaddr_flat(pmpaddr_flat),
        .allow(ptw_pmp_allow)
    );
    pma_checker u_ptw_pma (
        .paddr(ptw_bus_addr),
        .access_type(ptw_bus_we ? ACCESS_STORE : ACCESS_LOAD),
        .access_size(`AXI_SIZE_WORD),
        .is_atomic(1'b0),
        .is_ptw(1'b1),
        .allow(ptw_pma_allow)
    );

    assign ptw_bus_done = ptw_protection_deny ? 1'b1 : ptw_mem_done;
    assign ptw_bus_error = ptw_protection_deny ? 1'b1 : ptw_mem_error;

    always_comb begin
        fetch_exception = '0;
        if (if_valid && (mmu_inst_fault || fetch_protection_deny ||
                         icache_cpu_error)) begin
            fetch_exception.valid = 1'b1;
            fetch_exception.cause = mmu_inst_fault ?
                                    {28'b0, mmu_inst_fault_cause} : 32'd1;
            fetch_exception.epc = fetch_vaddr;
            fetch_exception.tval = mmu_inst_fault ?
                                   mmu_inst_fault_vaddr : fetch_vaddr;
        end

        mem_external_exception = '0;
        if (mem_valid && (mmu_data_fault || data_protection_deny ||
                          dcache_cpu_error)) begin
            mem_external_exception.valid = 1'b1;
            mem_external_exception.cause = mmu_data_fault ?
                    {28'b0, mmu_data_fault_cause} :
                    (mem_access_type == ACCESS_LOAD ? 32'd5 : 32'd7);
            mem_external_exception.epc = mem_pc;
            mem_external_exception.tval = mmu_data_fault ?
                                           mmu_data_fault_vaddr : mem_vaddr;
        end

        mem_exception = mem_local_exception.valid ?
                        mem_local_exception : mem_external_exception;

        sync_exception_now = '0;
        if (if_valid && fetch_exception.valid)
            sync_exception_now = fetch_exception;
        else if (id_valid && decode_exception.valid)
            sync_exception_now = decode_exception;
        else if (exe_valid && exe_exception.valid)
            sync_exception_now = exe_exception;
        else if (mem_valid && mem_exception.valid)
            sync_exception_now = mem_exception;
    end

    dcache_ctrl u_dcache_wrap (
        .clk(clk),
        .resetn(resetn),

        .cpu_req_valid(phys_req_valid),
        .cpu_req_paddr(phys_req_paddr),
        .cpu_req_wdata(phys_req_wdata),
        .cpu_req_write(phys_req_write),
        .cpu_req_size(phys_req_size),
        .cpu_req_rdata(readData_32_mux),
        .cpu_req_ready(data_valid_mux),

        .ptw_req_valid(ptw_bus_req && ptw_pmp_allow && ptw_pma_allow),
        .ptw_req_addr(ptw_bus_addr),
        .ptw_req_wdata(ptw_bus_wdata),
        .ptw_req_write(ptw_bus_we),
        .ptw_req_rdata(ptw_bus_rdata),
        .ptw_req_done(ptw_mem_done),
        .ptw_req_error(ptw_mem_error),

        .cpu_req_error(dcache_cpu_error),
        .cpu_req_error_is_store(),
        .cpu_req_error_addr(),
        .mem_req_valid(dcache_mem_req_valid),
        .mem_req_ready(dcache_mem_req_ready),
        .mem_req_addr(dcache_mem_req_addr),
        .mem_req_write(dcache_mem_req_write),
        .mem_req_size(dcache_mem_req_size),
        .mem_req_len(dcache_mem_req_len),
        .mem_req_wdata(dcache_mem_req_wdata),
        .mem_req_wstrb(dcache_mem_req_wstrb),
        .mem_resp_valid(dcache_mem_resp_valid),
        .mem_resp_data(dcache_mem_resp_data),
        .mem_resp_error(dcache_mem_resp_error)
    );

    cpu_mem u_mem(
        .clk(clk),
        .resetn(resetn),
        .mem_valid(mem_valid),
        .exe_mem_bus_r(exe_mem_bus_r),
        .trap_enter(trap_enter_valid),
        .mem_access_valid(mem_access_valid),
        .mem_vaddr(mem_vaddr),
        .mem_kind(mem_kind),
        .mem_access_type(mem_access_type),
        .mem_access_size(mem_access_size),
        .mem_access_ready(mem_access_ready),
        .mem_access_paddr(mmu_data_paddr),
        .phys_req_valid(phys_req_valid),
        .phys_req_paddr(phys_req_paddr),
        .phys_req_write(phys_req_write),
        .phys_req_size(phys_req_size),
        .phys_req_wdata(phys_req_wdata),
        .phys_resp_rdata(readData_32_mux),
        .phys_resp_valid(data_valid_mux),
        .mem_done(mem_done),
        .mem_wb_bus(mem_wb_bus),
        .mem_pc(mem_pc),
        .mem_inst(mem_inst),
        .mem_exception(mem_local_exception)
    );

    cpu_wb u_wb(
        .wb_valid(wb_valid),
        .mem_wb_bus_r(mem_wb_bus_r),
        .rf_wen(rf_wen),
        .rf_waddr(rf_waddr),
        .rf_wdata(rf_wdata),
        .wb_done(wb_done),
        .wb_pc(wb_pc),
        .wb_inst(wb_inst)
    );

    cpu_regfile u_regfile(
        .clk(clk),
        .resetn(resetn),
        .wen(rf_wen),
        .raddr1(rs1_addr),
        .raddr2(rs2_addr),
        .waddr(rf_waddr),
        .wdata(rf_wdata),
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

    cpu_trap_csr u_trap_csr(
        .clk              (clk),
        .resetn            (resetn),
        .sync_exception_now(sync_exception_now),
        .id_exe_bus_r     (id_exe_bus_r),
        .csr_valid        (csr_valid),
        .trap_enter_valid (trap_enter_valid),
        .trap_return_valid(trap_return_valid),
        .trap_return_kind (trap_return_kind),
        .priv_mode        (priv_mode),
        .timer_irq        (timer_irq),
        .ext_meip_in      (ext_meip_in),
        .ext_seip_in      (ext_seip_in),
        .ext_msip_in      (ext_msip_in),
        .ext_mtime        (ext_mtime),
        .current_pc       (pc),
        .cycle_en         (cycle_en),
        .inst_retire      (inst_retire),
        .sync_exception_pending(sync_exception_pending),
        .interrupt_pending(interrupt_pending),
        .csr_wb_bus       (csr_wb_bus),
        .trap_pc          (trap_csr_pc),
        .csr_pc_plus4     (csr_pc_plus4_out),
        .target_priv      (target_priv),
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
        .pmpcfg_flat      (pmpcfg_flat),
        .pmpaddr_flat     (pmpaddr_flat),
        // Extended debug outputs
        .hw_trap_epc      (hw_trap_epc_w),
        .hw_trap_cause    (hw_trap_cause_w),
        .hw_trap_tval     (hw_trap_tval_w)
    );

    // Unified MMU: single instance with dual i/d interfaces
    MMU u_mmu(
        .clk(clk),
        .resetn(resetn),
        // i-side
        .i_vaddr(fetch_vaddr),
        .i_translate_en(if_valid),          // request only while fetch is active
        .i_paddr(mmu_inst_paddr),
        .i_miss(),
        .i_fault(mmu_inst_fault),
        .i_fault_cause(mmu_inst_fault_cause),
        .i_fault_vaddr(mmu_inst_fault_vaddr),
        .i_ready(mmu_inst_ready),
        // d-side
        .d_vaddr(mem_vaddr),
        .d_access_type(mem_access_type),
        .d_translate_en(mem_access_valid),
        .d_paddr(mmu_data_paddr),
        .d_miss(),
        .d_fault(mmu_data_fault),
        .d_fault_cause(mmu_data_fault_cause),
        .d_fault_vaddr(mmu_data_fault_vaddr),
        .d_ready(mmu_data_ready),
        // shared CSR
        .priv_mode(priv_mode),
        .satp(csr_satp),
        .mstatus_mprv(csr_mstatus[17]),
        .mstatus_mpp(priv_mode_t'(csr_mstatus[12:11])),
        .mstatus_sum(csr_mstatus[18]),
        .mstatus_mxr(csr_mstatus[19]),
        // single PTW bus
        .ptw_bus_req(ptw_bus_req),
        .ptw_bus_addr(ptw_bus_addr),
        .ptw_bus_we(ptw_bus_we),
        .ptw_bus_wdata(ptw_bus_wdata),
        .ptw_bus_rdata(ptw_bus_rdata),
        .ptw_bus_done(ptw_bus_done),
        .ptw_bus_error(ptw_bus_error),
        // flush
        .sfence_req(sfence_vma_req),
        // sfence completion
        .sfence_done(mmu_sfence_done),
        .dbg_mmu_state(dbg_mmu_state),
        .dbg_mmu_owner(dbg_mmu_owner),
        .dbg_mmu_req_vaddr(dbg_mmu_req_vaddr),
        .dbg_mmu_sv32(dbg_mmu_sv32),
        .dbg_mmu_tlb_hit(dbg_mmu_tlb_hit),
        .dbg_mmu_tlb_perm_fault(dbg_mmu_tlb_perm_fault),
        .dbg_mmu_ptw_active(dbg_mmu_ptw_active),
        .dbg_mmu_fault_from_ptw(dbg_mmu_fault_from_ptw)
    );

    cpu_bus_bridge u_bus_bridge(
        .clk              (clk),
        .resetn            (resetn),
        .i_req_valid       (icache_mem_req_valid),
        .i_req_ready       (icache_mem_req_ready),
        .i_req_addr        (icache_mem_req_addr),
        .i_req_write       (icache_mem_req_write),
        .i_req_size        (icache_mem_req_size),
        .i_req_len         (icache_mem_req_len),
        .i_req_wdata       (icache_mem_req_wdata),
        .i_req_wstrb       (4'b0000),
        .i_resp_valid      (icache_mem_resp_valid),
        .i_resp_data       (icache_mem_resp_data),
        .i_resp_error      (icache_mem_resp_error),
        .d_req_valid       (dcache_mem_req_valid),
        .d_req_ready       (dcache_mem_req_ready),
        .d_req_addr        (dcache_mem_req_addr),
        .d_req_write       (dcache_mem_req_write),
        .d_req_size        (dcache_mem_req_size),
        .d_req_len         (dcache_mem_req_len),
        .d_req_wdata       (dcache_mem_req_wdata),
        .d_req_wstrb       (dcache_mem_req_wstrb),
        .d_resp_valid      (dcache_mem_resp_valid),
        .d_resp_data       (dcache_mem_resp_data),
        .d_resp_error      (dcache_mem_resp_error),
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
        .rready            (rready)
    );

    assign dbg_if_done = if_done;
    assign dbg_inst_valid = inst_valid_mux;
    assign dbg_icache_state = icache_dbg_state;
    assign dbg_icache_refill_req = icache_mem_req_valid && (icache_mem_req_len == 8'd7);
    assign dbg_icache_refill_valid = icache_mem_resp_valid && !icache_mem_resp_error;
    assign dbg_mu_active            = dbg_mu_active_w;
    assign dbg_mu_req_valid         = dbg_mu_req_valid_w;
    assign dbg_mu_ready             = dbg_mu_ready_w;
    assign dbg_mu_busy              = dbg_mu_busy_w;
    assign dbg_mu_result_valid      = dbg_mu_result_valid_w;
    assign dbg_mu_funct3            = dbg_mu_funct3_w;
    assign dbg_exe_is_mu            = dbg_exe_is_mu_w;

    assign id_pc   = id_pc_wire;
    assign id_inst = id_inst_wire;

endmodule
