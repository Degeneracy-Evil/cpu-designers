`timescale 1ns / 1ps

module cpu_clint(
    input              clk,
    input              reset,

    input              exception_valid,
    input       [31:0] exception_cause,
    input       [31:0] exception_pc,
    input       [31:0] exception_mtval,

    input              mret_req,

    input       [31:0] csr_mstatus,
    input       [31:0] csr_mie,
    input       [31:0] csr_mtvec,
    input       [31:0] csr_mepc,
    input       [31:0] csr_mip,

    output             trap_enter,
    output             trap_return,
    output      [31:0] trap_pc,

    output             hw_csr_wen,
    output      [31:0] hw_mepc_wdata,
    output      [31:0] hw_mcause_wdata,
    output      [31:0] hw_mtval_wdata,
    output      [31:0] hw_mstatus_wdata
);

    wire mie_bit    = csr_mstatus[3];
    wire meie_bit   = csr_mie[11];
    wire msie_bit   = csr_mie[3];
    wire meip_bit   = csr_mip[11];
    wire msip_bit   = csr_mip[3];
    wire mpie_bit   = csr_mstatus[7];
    wire mpp_bits   = csr_mstatus[12:11];

    wire interrupt_pending = mie_bit && ((meie_bit && meip_bit) || (msie_bit && msip_bit));

    wire [31:0] interrupt_cause;
    assign interrupt_cause = (meie_bit && meip_bit) ? {1'b1, 23'b0, 1'b1, 7'b0} :
                             {1'b1, 27'b0, 1'b1, 3'b0};

    assign trap_enter  = exception_valid || (interrupt_pending && !exception_valid);
    assign trap_return = mret_req;

    assign trap_pc = mret_req ? csr_mepc : {csr_mtvec[31:2], 2'b00};

    assign hw_csr_wen = trap_enter || trap_return;

    assign hw_mepc_wdata = exception_valid ? exception_pc :
                           csr_mepc;

    assign hw_mcause_wdata = exception_valid ? exception_cause :
                             interrupt_cause;

    assign hw_mtval_wdata = exception_valid ? exception_mtval :
                            32'b0;

    wire [1:0] cur_mpp;
    assign cur_mpp = 2'b11;

    assign hw_mstatus_wdata = trap_enter ?
                              {csr_mstatus[31:13], cur_mpp, csr_mstatus[10:8], mie_bit, csr_mstatus[6:4], 1'b0, csr_mstatus[2:0]} :
                              {csr_mstatus[31:13], 2'b00, csr_mstatus[10:8], mpie_bit, csr_mstatus[6:4], 1'b1, csr_mstatus[2:0]};

endmodule
