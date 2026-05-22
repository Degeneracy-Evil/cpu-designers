`timescale 1ns / 1ps

module core_top(
    input         clk,
    input         reset,

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

    output [31:0] HADDR,
    output [1:0]  HTRANS,
    output        HWRITE,
    output [2:0]  HSIZE,
    output [2:0]  HBURST,
    output [3:0]  HPROT,
    output        HMASTLOCK,
    output [31:0] HWDATA,
    input  [31:0] HRDATA,
    input         HREADY,
    input         HRESP,

    input         init_sig,
    input         timer_irq,
    input         ext_meip_in,
    input         ext_msip_in
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
    wire [319:0] id_exe_bus;
    wire [206:0] exe_mem_bus;
    wire [167:0] mem_wb_bus;

    reg [95:0]  if_id_bus_r;
    reg [319:0] id_exe_bus_r;
    reg [206:0] exe_mem_bus_r;
    reg [167:0] mem_wb_bus_r;

    wire mem_en;

    wire [31:0] mmu_inst_paddr;
    wire [31:0] mmu_data_paddr;

    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [31:0] rs1_value;
    wire [31:0] rs2_value;

    wire rf_wen;
    wire [4:0] rf_waddr;
    wire [31:0] rf_wdata;
    wire wb_is_jal_like;

    wire [31:0] id_pc_plus4;
    wire [31:0] exe_pc_plus4;
    wire [31:0] wb_pc_plus4;

    assign id_pc_plus4  = if_id_bus_r[95:64];
    assign exe_pc_plus4 = id_exe_bus_r[319:288];
    assign wb_pc_plus4  = mem_wb_bus_r[167:136];

    wire [31:0] actual_rf_wdata;
    assign actual_rf_wdata = wb_is_jal_like ? wb_pc_plus4 : rf_wdata;

    wire [167:0] exe_wb_bus;
    assign exe_wb_bus = {
        exe_mem_bus[206:175],
        exe_mem_bus[173],
        exe_mem_bus[170],
        exe_mem_bus[169] & exe_mem_bus[174],
        exe_mem_bus[168:164],
        exe_mem_bus[163:132],
        exe_mem_bus[95:64],
        exe_mem_bus[63:32],
        exe_mem_bus[31:0]
    };

    wire mem_misalign_load;
    wire mem_misalign_store;
    wire [31:0] mem_misalign_addr;

    wire [31:0] id_pc_wire;
    wire [31:0] id_inst_wire;

    wire exception_at_decode;
    wire trap_pending;
    wire [31:0] csr_read_data;
    wire [167:0] csr_wb_bus;
    wire [31:0] trap_csr_pc;
    wire [31:0] csr_pc_plus4_out;
    wire [1:0]  target_priv;

    wire inst_access_fault_pending;
    wire data_access_fault_pending;

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
    wire csr_access_ok;

    wire [1:0] mpp_field;
    assign mpp_field = csr_mstatus[12:11];
    wire spp_field;
    assign spp_field = csr_mstatus[8];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 32'h80000000;
            priv_mode <= PRIV_M;
            if_id_bus_r <= 96'b0;
            id_exe_bus_r <= 320'b0;
            exe_mem_bus_r <= 207'b0;
            mem_wb_bus_r <= 168'b0;
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
        .reset(reset),
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
        .exe_is_branch(exe_is_branch),
        .exe_need_mem(exe_need_mem),
        .trap_pending(trap_pending),
        .exception_at_decode(exception_at_decode),
        .inst_access_fault_pending(inst_access_fault_pending),
        .data_access_fault_pending(data_access_fault_pending),
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
        .state(fsm_state)
    );

    wire [31:0] fetch_vaddr;

    wire [31:0] instData_32_mux;
    wire        inst_valid_mux;
    wire        icache_mmio_req;

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

    reg dcache_flush_sent_r;
    reg icache_invalidate_sent_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dcache_flush_sent_r      <= 1'b0;
            icache_invalidate_sent_r <= 1'b0;
        end else begin
            if (!fencei_req) begin
                dcache_flush_sent_r      <= 1'b0;
                icache_invalidate_sent_r <= 1'b0;
            end else begin
                if (dcache_flush_done && !dcache_flush_sent_r)
                    dcache_flush_sent_r <= 1'b1;
                if (icache_invalidate_done && !icache_invalidate_sent_r)
                    icache_invalidate_sent_r <= 1'b1;
            end
        end
    end

    assign dcache_flush_req      = fencei_req && !dcache_flush_sent_r;
    assign icache_invalidate_req = fencei_req && dcache_flush_sent_r && !icache_invalidate_sent_r;
    assign fencei_done           = dcache_flush_sent_r && icache_invalidate_sent_r;

    icache_ctrl u_icache_wrap (
        .clk(clk),
        .reset(reset),

        .cpu_req_valid(if_valid),
        .cpu_req_addr(mmu_inst_paddr),
        .cpu_req_data(instData_32_mux),
        .cpu_req_ready(inst_valid_mux),

        .mmio_req(icache_mmio_req),
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
        .reset(reset),
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

    cpu_execute u_execute(
        .clk(clk),
        .reset(reset),
        .exe_valid(exe_valid),
        .id_exe_bus_r(id_exe_bus_r),
        .csr_rdata(csr_read_data),
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
        .reset(reset),

        .cpu_req_valid(mem_en),
        .cpu_req_addr(mmu_data_paddr),
        .cpu_req_wdata(mem_writeData_32),
        .cpu_req_hwrite(mem_hwrite),
        .cpu_req_hsize(mem_hsize),
        .cpu_req_rdata(readData_32_mux),
        .cpu_req_ready(data_valid_mux),

        .mmio_req(dcache_mmio_req),
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
        .flush_done(dcache_flush_done)
    );

    cpu_mem u_mem(
        .clk(clk),
        .reset(reset),
        .mem_valid(mem_valid),
        .exe_mem_bus_r(exe_mem_bus_r),
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
        .mem_misalign_addr(mem_misalign_addr)
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
        .wb_inst(wb_inst)
    );

    cpu_regfile u_regfile(
        .clk(clk),
        .reset(reset),
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

    cpu_trap_csr u_trap_csr(
        .clk              (clk),
        .reset            (reset),
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
        .csr_access_ok    (csr_access_ok)
    );

    MMU u_mmu_inst(
        .vaddr(fetch_vaddr),
        .paddr(mmu_inst_paddr)
    );

    MMU u_mmu_data(
        .vaddr(mem_dataAddr_32),
        .paddr(mmu_data_paddr)
    );

    cpu_bus_bridge u_bus_bridge(
        .clk              (clk),
        .reset            (reset),
        .icache_mmio_req  (icache_mmio_req),
        .icache_mmio_addr (mmu_inst_paddr),
        .dcache_mmio_req  (dcache_mmio_req),
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
        .HADDR            (HADDR),
        .HTRANS           (HTRANS),
        .HWRITE           (HWRITE),
        .HSIZE            (HSIZE),
        .HBURST           (HBURST),
        .HPROT            (HPROT),
        .HMASTLOCK        (HMASTLOCK),
        .HWDATA           (HWDATA),
        .HRDATA           (HRDATA),
        .HREADY           (HREADY),
        .HRESP            (HRESP),
        .icache_error     (bridge_icache_error),
        .dcache_error     (bridge_dcache_error),
        .dcache_error_is_store(bridge_dcache_error_is_store),
        .bus_error_addr   (bridge_bus_error_addr)
    );

    assign display_state = {28'b0, fsm_state};

    assign id_pc   = id_pc_wire;
    assign id_inst = id_inst_wire;

endmodule
