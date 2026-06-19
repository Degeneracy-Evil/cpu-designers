`timescale 1ns / 1ps
`include "core_bus_types.svh"

module cpu_csr_interface(
    input         clk,
    input         resetn,

    input  [348:0] id_exe_bus_r,
    input  [11:0]  dec_csr_addr,
    input          csr_valid,

    input  [1:0]   priv_mode,

    input         hw_csr_wen,
    input         hw_trap_is_enter,
    input  [1:0]  hw_target_priv,
    input  [31:0] hw_mepc_wdata,
    input  [31:0] hw_mcause_wdata,
    input  [31:0] hw_mtval_wdata,
    input  [31:0] hw_mstatus_wdata,
    input  [31:0] hw_sepc_wdata,
    input  [31:0] hw_scause_wdata,
    input  [31:0] hw_stval_wdata,
    input  [31:0] hw_sstatus_wdata,

    input         timer_irq,
    input         ext_meip_in,
    input         ext_seip_in,
    input         ext_msip_in,
    input  [63:0] ext_mtime,

    input         cycle_en,
    input         inst_retire,

    input  [4:0]  fflags_wdata,
    input         fflags_wen,

    output [31:0] csr_read_data,
    output wb_bus_t csr_wb_bus,
    output [31:0] csr_pc_plus4,

    output [31:0] csr_mstatus,
    output [31:0] csr_mie,
    output [31:0] csr_mtvec,
    output [31:0] csr_mepc,
    output [31:0] csr_mcause,
    output [31:0] csr_mip,
    output [31:0] csr_medeleg,
    output [31:0] csr_mideleg,
    output [31:0] csr_sstatus,
    output [31:0] csr_sie,
    output [31:0] csr_stvec,
    output [31:0] csr_sscratch,
    output [31:0] csr_sepc,
    output [31:0] csr_scause,
    output [31:0] csr_stval,
    output [31:0] csr_sip,
    output [31:0] csr_satp,
    output [31:0] csr_mcounteren,
    output [31:0] csr_scounteren,

    output        csr_access_ok,
    output [4:0]  csr_fflags,
    output [2:0]  csr_frm,

    // PMP config outputs
    output [31:0] csr_pmpcfg0,
    output [31:0] csr_pmpcfg1,
    output [31:0] csr_pmpcfg2,
    output [31:0] csr_pmpcfg3,
    output [31:0] csr_pmpaddr0,
    output [31:0] csr_pmpaddr1,
    output [31:0] csr_pmpaddr2,
    output [31:0] csr_pmpaddr3,
    output [31:0] csr_pmpaddr4,
    output [31:0] csr_pmpaddr5,
    output [31:0] csr_pmpaddr6,
    output [31:0] csr_pmpaddr7,
    output [31:0] csr_pmpaddr8,
    output [31:0] csr_pmpaddr9,
    output [31:0] csr_pmpaddr10,
    output [31:0] csr_pmpaddr11,
    output [31:0] csr_pmpaddr12,
    output [31:0] csr_pmpaddr13,
    output [31:0] csr_pmpaddr14,
    output [31:0] csr_pmpaddr15
);

    wire [2:0] csr_funct3_bus;
    wire [4:0] csr_uimm_bus;
    wire [4:0] csr_rs1_bus;
    wire [31:0] csr_rs1_val_bus;
    wire [4:0] csr_rd_bus;
    wire [31:0] csr_pc_plus4_bus;
    wire [31:0] csr_pc_bus;
    wire [31:0] csr_inst_bus;

    assign csr_funct3_bus   = id_exe_bus_r[100:98];
    assign csr_uimm_bus    = id_exe_bus_r[97:93];
    assign csr_rs1_bus     = id_exe_bus_r[48:44];
    assign csr_rs1_val_bus = id_exe_bus_r[183:152];
    assign csr_rd_bus      = id_exe_bus_r[308:304];
    assign csr_pc_plus4_bus= id_exe_bus_r[348:317];
    assign csr_pc_bus      = id_exe_bus_r[92:61];
    assign csr_inst_bus    = id_exe_bus_r[60:29];

    assign csr_pc_plus4 = csr_pc_plus4_bus;

    wire [31:0] csr_new_val;
    assign csr_new_val = (csr_funct3_bus == 3'b001) ? csr_rs1_val_bus :
                         (csr_funct3_bus == 3'b010) ? (csr_read_data | csr_rs1_val_bus) :
                         (csr_funct3_bus == 3'b011) ? (csr_read_data & ~csr_rs1_val_bus) :
                         (csr_funct3_bus == 3'b101) ? {27'b0, csr_uimm_bus} :
                         (csr_funct3_bus == 3'b110) ? (csr_read_data | {27'b0, csr_uimm_bus}) :
                         (csr_funct3_bus == 3'b111) ? (csr_read_data & ~{27'b0, csr_uimm_bus}) :
                         csr_read_data;

    wire csr_no_write;
    assign csr_no_write = ((csr_funct3_bus == 3'b010 || csr_funct3_bus == 3'b011) && (csr_rs1_bus == 5'd0)) ||
                          ((csr_funct3_bus == 3'b110 || csr_funct3_bus == 3'b111) && (csr_uimm_bus == 5'd0));

    wire [11:0] csr_sw_addr;
    wire csr_sw_wen;
    wire [31:0] csr_sw_wdata;

    assign csr_sw_addr  = dec_csr_addr;
    assign csr_sw_wen   = csr_valid && !csr_no_write;
    assign csr_sw_wdata = csr_new_val;

    assign csr_wb_bus = '{
        pc_plus4:      csr_pc_plus4_bus,
        is_jal_like:   1'b0,
        is_csr:        1'b1,
        wb_we:         1'b1,
        wb_rd:         csr_rd_bus,
        wb_data:       csr_read_data,
        csr_rdata:     csr_read_data,
        pc:            csr_pc_bus,
        inst:          csr_inst_bus,
        is_fpu:        1'b0,
        is_flw:        1'b0,
        is_fsw:        1'b0,
        fpu_rd_is_int: 1'b0,
        fpu_fflags:    5'b0,
        is_amo:        1'b0,
        is_lr:         1'b0,
        is_sc:         1'b0
    };

    wire [31:0] csr_mscratch;
    wire [31:0] csr_mcause;
    wire [31:0] csr_mtval;

    cpu_csr u_csr(
        .clk(clk),
        .resetn(resetn),
        .sw_csr_addr(csr_sw_addr),
        .sw_csr_wen(csr_sw_wen),
        .sw_csr_wdata(csr_sw_wdata),
        .sw_csr_rdata(csr_read_data),
        .csr_addr_valid(),
        .csr_access_ok(csr_access_ok),
        .priv_mode(priv_mode),
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
        .hw_sstatus_wdata(hw_sstatus_wdata),
        .ext_meip(ext_meip_in),
        .ext_seip(ext_seip_in),
        .ext_mtip(timer_irq),
        .ext_msip(ext_msip_in),
        .ext_mtime(ext_mtime),
        .cycle_en(cycle_en),
        .inst_retire(inst_retire),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mtvec(csr_mtvec),
        .csr_mscratch(csr_mscratch),
        .csr_mepc(csr_mepc),
        .csr_mcause(csr_mcause),
        .csr_mtval(csr_mtval),
        .csr_mip(csr_mip),
        .csr_medeleg(csr_medeleg),
        .csr_mideleg(csr_mideleg),
        .csr_sstatus(csr_sstatus),
        .csr_sie(csr_sie),
        .csr_stvec(csr_stvec),
        .csr_sscratch(csr_sscratch),
        .csr_sepc(csr_sepc),
        .csr_scause(csr_scause),
        .csr_stval(csr_stval),
        .csr_sip(csr_sip),
        .csr_satp(csr_satp),
        .csr_mcounteren(csr_mcounteren),
        .csr_scounteren(csr_scounteren),
        .fflags_wdata(fflags_wdata),
        .fflags_wen(fflags_wen),
        .csr_fflags(csr_fflags),
        .csr_frm(csr_frm),
        .csr_pmpcfg0(csr_pmpcfg0),
        .csr_pmpcfg1(csr_pmpcfg1),
        .csr_pmpcfg2(csr_pmpcfg2),
        .csr_pmpcfg3(csr_pmpcfg3),
        .csr_pmpaddr0(csr_pmpaddr0),
        .csr_pmpaddr1(csr_pmpaddr1),
        .csr_pmpaddr2(csr_pmpaddr2),
        .csr_pmpaddr3(csr_pmpaddr3),
        .csr_pmpaddr4(csr_pmpaddr4),
        .csr_pmpaddr5(csr_pmpaddr5),
        .csr_pmpaddr6(csr_pmpaddr6),
        .csr_pmpaddr7(csr_pmpaddr7),
        .csr_pmpaddr8(csr_pmpaddr8),
        .csr_pmpaddr9(csr_pmpaddr9),
        .csr_pmpaddr10(csr_pmpaddr10),
        .csr_pmpaddr11(csr_pmpaddr11),
        .csr_pmpaddr12(csr_pmpaddr12),
        .csr_pmpaddr13(csr_pmpaddr13),
        .csr_pmpaddr14(csr_pmpaddr14),
        .csr_pmpaddr15(csr_pmpaddr15)
    );

endmodule
