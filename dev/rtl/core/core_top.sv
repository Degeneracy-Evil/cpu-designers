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
    wire [333:0] id_exe_bus;
    exe_mem_bus_t exe_mem_bus;
    wb_bus_t      mem_wb_bus;

    reg [95:0]  if_id_bus_r;
    reg [333:0] id_exe_bus_r;
    exe_mem_bus_t exe_mem_bus_r;
    wb_bus_t      mem_wb_bus_r;

    wire mem_en;

    wire [31:0] mmu_inst_paddr;
    wire [31:0] mmu_data_paddr;

    wire        mmu_inst_miss;
    wire        mmu_data_miss;
    wire        mem_data_access;   // Combinational: is_load||is_store||is_flw||is_fsw (consumed by cpu_controller)
    wire        mmu_inst_page_fault;
    wire        mmu_data_page_fault;
    wire [3:0]  mmu_inst_pf_cause;
    wire [3:0]  mmu_data_pf_cause;
    wire [31:0] mmu_inst_pf_vaddr;
    wire [31:0] mmu_data_pf_vaddr;

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

    // PTW A/D bit writeback → dcache line invalidation
    // When PTW completes a write (ptw_bus_we && ptw_bus_done), the written
    // PTE address may have a stale copy in dcache. Invalidate that line.
    reg        ptw_ad_inv_pending_r;
    reg [31:0] ptw_ad_inv_addr_r;
    wire       ptw_ad_inv_req  = ptw_ad_inv_pending_r;
    wire [31:0]ptw_ad_inv_addr = ptw_ad_inv_addr_r;
    wire       ptw_ad_inv_done;

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
    wire [31:0] frs1_value;
    wire [31:0] frs2_value;
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
    assign exe_pc_plus4 = id_exe_bus_r[333:302];
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
        fpu_fflags:    exe_mem_bus.fpu_fflags
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
    // Debug: CSR access permission from trap_csr (used internally; not consumed at core_top)
    wire csr_access_ok;

    wire [1:0] mpp_field;
    assign mpp_field = csr_mstatus[12:11];
    wire spp_field;
    assign spp_field = csr_mstatus[8];

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            pc <= 32'hFC000000;  // Boot ROM @ 0xFC00_0000 (both sim and FPGA)
            priv_mode <= PRIV_M;
            if_id_bus_r <= 96'b0;
            id_exe_bus_r <= 334'b0;
            exe_mem_bus_r <= 216'b0;
            mem_wb_bus_r <= 177'b0;
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
                pc <= trap_csr_pc;
                priv_mode <= target_priv;
            end else if (trap_return_valid) begin
                pc <= trap_csr_pc;
                if (priv_mode == PRIV_M) begin
                    priv_mode <= mpp_field;
                end else begin
                    priv_mode <= spp_field ? PRIV_S : PRIV_U;
                end
            end else if (exe_valid && exe_done) begin
                if (exe_is_ctrl_flow && exe_branch_taken) begin
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
        .mmu_inst_miss(mmu_inst_miss),
        .mmu_data_miss(mmu_data_miss),
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

    wire        dcache_flush_req;
    wire        dcache_flush_done;
    wire        icache_invalidate_req;
    wire        icache_invalidate_done;

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

    // PTW A/D bit writeback → dcache line invalidation
    // When PTW completes a write to memory (setting A/D bits in a PTE),
    // the dcache may contain a stale copy of that cache line.
    // Latch the address and request invalidation; hold until dcache completes.
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ptw_ad_inv_pending_r <= 1'b0;
            ptw_ad_inv_addr_r   <= 32'b0;
        end else begin
            if (ptw_bus_we && ptw_bus_done && !ptw_ad_inv_pending_r) begin
                // PTW write completed — request dcache line invalidation
                ptw_ad_inv_pending_r <= 1'b1;
                ptw_ad_inv_addr_r   <= ptw_bus_addr;
            end else if (ptw_ad_inv_done) begin
                // dcache completed the invalidation
                ptw_ad_inv_pending_r <= 1'b0;
            end
        end
    end



    icache_ctrl u_icache_wrap (
        .clk(clk),
        .resetn(resetn),

        .cpu_req_valid(if_valid),
        .cpu_req_addr(mmu_inst_paddr),
        .cpu_req_vaddr(fetch_vaddr),
        .mmu_ready(mmu_inst_ready),
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

        .invalidate_req(icache_invalidate_req),
        .invalidate_done(icache_invalidate_done)
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
    assign frs1_addr = rs1_addr;
    assign frs2_addr = rs2_addr;

    cpu_execute u_execute(
        .clk(clk),
        .resetn(resetn),
        .exe_valid(exe_valid),
        .id_exe_bus_r(id_exe_bus_r),
        .csr_rdata(csr_read_data),
        .csr_frm(csr_frm),
        .frs1_value(frs1_value),
        .frs2_value(frs2_value),
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
        .exe_csr_old_val()
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

    wire        dcache_wb_req;
    wire [31:0] dcache_wb_addr;
    wire [255:0] dcache_wb_data;
    wire        dcache_wb_valid;

    wire        bridge_icache_error;
    wire        bridge_dcache_error;
    wire        bridge_dcache_error_is_store;
    wire [31:0] bridge_bus_error_addr;

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

        .wb_req(dcache_wb_req),
        .wb_addr(dcache_wb_addr),
        .wb_data(dcache_wb_data),
        .wb_valid(dcache_wb_valid),

        .flush_req(dcache_flush_req),
        .flush_done(dcache_flush_done),

        // Single-line invalidation for PTW A/D bit coherency
        .inv_line_req(ptw_ad_inv_req),
        .inv_line_addr(ptw_ad_inv_addr),
        .inv_line_done(ptw_ad_inv_done)
    );

    cpu_mem u_mem(
        .clk(clk),
        .resetn(resetn),
        .mem_valid(mem_valid),
        .exe_mem_bus_r(exe_mem_bus_r),
        .frs2_value(frs2_value),
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
        .mem_data_access(mem_data_access)
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
        .dbg_rdata(rf_data)
    );

    fpu_regfile u_fregfile(
        .clk(clk),
        .resetn(resetn),
        .wen(fp_wen),
        .raddr1(frs1_addr),
        .raddr2(frs2_addr),
        .waddr(fp_waddr),
        .wdata(fp_wdata),
        .rdata1(frs1_value),
        .rdata2(frs2_value),
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
        .ext_msip_in      (ext_msip_in),
        .ext_mtime        (ext_mtime),
        .current_pc       (pc),
        .exe_misalign_valid(exe_misalign_valid),
        .exe_misalign_target(exe_misalign_target),
        .exe_pc           (exe_pc),
        .inst_access_fault(bridge_icache_error),
        .inst_access_fault_addr(bridge_bus_error_addr),
        .load_access_fault(bridge_dcache_error && !bridge_dcache_error_is_store),
        .load_access_fault_addr(bridge_bus_error_addr),
        .store_access_fault(bridge_dcache_error && bridge_dcache_error_is_store),
        .store_access_fault_addr(bridge_bus_error_addr),
        .mem_access_fault_pc(exe_pc),
        .inst_page_fault(mmu_inst_page_fault),
        .inst_page_fault_vaddr(mmu_inst_pf_vaddr),
        // BUG-10 fix: 移除 mem_en 门控 — mem_en=0 时 MMU d-side 不翻译 (d_translate_en=mem_en),
        // d_page_fault 不会产生，因此 mem_en 门控是冗余的。保留 mem_en 会在 PTW 完成
        // 后 mem_en 已变 0 时吞掉 PF 信号。
        .load_page_fault(mmu_data_page_fault && !mem_hwrite),
        .load_page_fault_vaddr(mmu_data_pf_vaddr),
        .store_page_fault(mmu_data_page_fault && mem_hwrite),
        .store_page_fault_vaddr(mmu_data_pf_vaddr),
        .mem_page_fault_pc(exe_pc),
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
        .csr_pmpcfg0      (),
        .csr_pmpcfg1      (),
        .csr_pmpcfg2      (),
        .csr_pmpcfg3      (),
        .csr_pmpaddr0     (),
        .csr_pmpaddr1     (),
        .csr_pmpaddr2     (),
        .csr_pmpaddr3     (),
        .csr_pmpaddr4     (),
        .csr_pmpaddr5     (),
        .csr_pmpaddr6     (),
        .csr_pmpaddr7     (),
        .csr_pmpaddr8     (),
        .csr_pmpaddr9     (),
        .csr_pmpaddr10    (),
        .csr_pmpaddr11    (),
        .csr_pmpaddr12    (),
        .csr_pmpaddr13    (),
        .csr_pmpaddr14    (),
        .csr_pmpaddr15    (),
        .fflags_wdata     (wb_fflags),
        .fflags_wen       (wb_valid && (wb_fflags != 5'b0))
    );

    // Unified MMU: single instance with dual i/d interfaces
    MMU u_mmu(
        .clk(clk),
        .resetn(resetn),
        // i-side
        .i_vaddr(fetch_vaddr),
        .i_translate_en(1'b1),             // inst MMU always translates
        .i_paddr(mmu_inst_paddr),
        .i_miss(mmu_inst_miss),
        .i_page_fault(mmu_inst_page_fault),
        .i_pf_cause(mmu_inst_pf_cause),
        .i_pf_vaddr(mmu_inst_pf_vaddr),
        .i_ready(mmu_inst_ready),
        // d-side
        .d_vaddr(mem_dataAddr_32),
        .d_access_type(mem_hwrite ? 2'b10 : 2'b01),
        .d_translate_en(mem_en),           // data MMU only translates when address is valid
        .d_paddr(mmu_data_paddr),
        .d_miss(mmu_data_miss),
        .d_page_fault(mmu_data_page_fault),
        .d_pf_cause(mmu_data_pf_cause),
        .d_pf_vaddr(mmu_data_pf_vaddr),
        .d_ready(mmu_data_ready),
        // shared CSR
        .priv_mode(priv_mode),
        .satp(csr_satp),
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
        .sfence_vma(sfence_vma_to_mmu_pulse),
        // sfence completion
        .sfence_done(mmu_sfence_done)
    );

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
        .dcache_refill_req  (dcache_refill_req),
        .dcache_refill_addr (dcache_refill_addr),
        .dcache_refill_data (dcache_refill_data),
        .dcache_refill_valid (dcache_refill_valid),
        .dcache_wb_req      (dcache_wb_req),
        .dcache_wb_addr     (dcache_wb_addr),
        .dcache_wb_data     (dcache_wb_data),
        .dcache_wb_valid    (dcache_wb_valid),
        .ptw_req           (ptw_bus_req),
        .ptw_addr          (ptw_bus_addr),
        .ptw_we            (ptw_bus_we),
        .ptw_wdata         (ptw_bus_wdata),
        .ptw_rdata         (ptw_bus_rdata),
        .ptw_done          (ptw_bus_done),
        .ptw_error         (ptw_bus_error),
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

    assign id_pc   = id_pc_wire;
    assign id_inst = id_inst_wire;

endmodule
