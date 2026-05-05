`timescale 1ns / 1ps

module cpu_csr_interface(
    input         clk,
    input         reset,

    input  [315:0] id_exe_bus_r,
    input  [11:0]  dec_csr_addr,
    input          csr_valid,

    input         hw_csr_wen,
    input  [31:0] hw_mepc_wdata,
    input  [31:0] hw_mcause_wdata,
    input  [31:0] hw_mtval_wdata,
    input  [31:0] hw_mstatus_wdata,

    input         timer_irq,

    output [31:0] csr_read_data,
    output [167:0] csr_wb_bus,
    output [31:0] csr_pc_plus4,

    output [31:0] csr_mstatus,
    output [31:0] csr_mie,
    output [31:0] csr_mtvec,
    output [31:0] csr_mepc,
    output [31:0] csr_mip
);

    wire [2:0] csr_funct3_bus;
    wire [4:0] csr_uimm_bus;
    wire [4:0] csr_rs1_bus;
    wire [31:0] csr_rs1_val_bus;
    wire [4:0] csr_rd_bus;
    wire [31:0] csr_pc_plus4_bus;
    wire [31:0] csr_pc_bus;
    wire [31:0] csr_inst_bus;

    assign csr_funct3_bus   = id_exe_bus_r[71:69];
    assign csr_uimm_bus    = id_exe_bus_r[68:64];
    assign csr_rs1_bus     = id_exe_bus_r[19:15];
    assign csr_rs1_val_bus = id_exe_bus_r[154:123];
    assign csr_rd_bus      = id_exe_bus_r[275:271];
    assign csr_pc_plus4_bus= id_exe_bus_r[315:284];
    assign csr_pc_bus      = id_exe_bus_r[63:32];
    assign csr_inst_bus    = id_exe_bus_r[31:0];

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

    assign csr_wb_bus = {csr_pc_plus4_bus, 1'b0, 1'b1, 1'b1, csr_rd_bus, csr_read_data, csr_read_data, csr_pc_bus, csr_inst_bus};

    wire [31:0] csr_mscratch;
    wire [31:0] csr_mcause;
    wire [31:0] csr_mtval;

    cpu_csr u_csr(
        .clk(clk),
        .reset(reset),
        .sw_csr_addr(csr_sw_addr),
        .sw_csr_wen(csr_sw_wen),
        .sw_csr_wdata(csr_sw_wdata),
        .sw_csr_rdata(csr_read_data),
        .csr_addr_valid(),
        .hw_csr_wen(hw_csr_wen),
        .hw_mepc_wdata(hw_mepc_wdata),
        .hw_mcause_wdata(hw_mcause_wdata),
        .hw_mtval_wdata(hw_mtval_wdata),
        .hw_mstatus_wdata(hw_mstatus_wdata),
        .ext_meip(1'b0),
        .ext_mtip(timer_irq),
        .ext_msip(1'b0),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mtvec(csr_mtvec),
        .csr_mscratch(csr_mscratch),
        .csr_mepc(csr_mepc),
        .csr_mcause(csr_mcause),
        .csr_mtval(csr_mtval),
        .csr_mip(csr_mip)
    );

endmodule
