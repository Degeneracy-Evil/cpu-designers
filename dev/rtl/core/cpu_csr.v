`timescale 1ns / 1ps

module cpu_csr(
    input              clk,
    input              reset,

    input       [11:0] sw_csr_addr,
    input              sw_csr_wen,
    input       [31:0] sw_csr_wdata,
    output reg  [31:0] sw_csr_rdata,
    output             csr_addr_valid,

    input              hw_csr_wen,
    input       [31:0] hw_mepc_wdata,
    input       [31:0] hw_mcause_wdata,
    input       [31:0] hw_mtval_wdata,
    input       [31:0] hw_mstatus_wdata,

    input              ext_meip,
    input              ext_mtip,
    input              ext_msip,

    output      [31:0] csr_mstatus,
    output      [31:0] csr_mie,
    output      [31:0] csr_mtvec,
    output      [31:0] csr_mscratch,
    output      [31:0] csr_mepc,
    output      [31:0] csr_mcause,
    output      [31:0] csr_mtval,
    output      [31:0] csr_mip
);

    localparam ADDR_MSTATUS  = 12'h300;
    localparam ADDR_MIE      = 12'h304;
    localparam ADDR_MTVEC    = 12'h305;
    localparam ADDR_MSCRATCH = 12'h340;
    localparam ADDR_MEPC     = 12'h341;
    localparam ADDR_MCAUSE   = 12'h342;
    localparam ADDR_MTVAL    = 12'h343;
    localparam ADDR_MIP      = 12'h344;

    reg [31:0] r_mstatus;
    reg [31:0] r_mie;
    reg [31:0] r_mtvec;
    reg [31:0] r_mscratch;
    reg [31:0] r_mepc;
    reg [31:0] r_mcause;
    reg [31:0] r_mtval;
    reg [31:0] r_mip;

    wire [31:0] w_mip_hw;
    assign w_mip_hw = {20'b0, ext_meip, 3'b0, ext_mtip, 3'b0, ext_msip, 3'b0};

    assign csr_addr_valid = (sw_csr_addr == ADDR_MSTATUS) ||
                            (sw_csr_addr == ADDR_MIE)     ||
                            (sw_csr_addr == ADDR_MTVEC)   ||
                            (sw_csr_addr == ADDR_MSCRATCH)||
                            (sw_csr_addr == ADDR_MEPC)    ||
                            (sw_csr_addr == ADDR_MCAUSE)  ||
                            (sw_csr_addr == ADDR_MTVAL)   ||
                            (sw_csr_addr == ADDR_MIP);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_mstatus  <= 32'b0;
            r_mie      <= 32'b0;
            r_mtvec    <= 32'b0;
            r_mscratch <= 32'b0;
            r_mepc     <= 32'b0;
            r_mcause   <= 32'b0;
            r_mtval    <= 32'b0;
            r_mip      <= 32'b0;
        end else begin
            r_mip <= w_mip_hw;

            if (hw_csr_wen) begin
                r_mepc    <= hw_mepc_wdata;
                r_mcause  <= hw_mcause_wdata;
                r_mtval   <= hw_mtval_wdata;
                r_mstatus <= hw_mstatus_wdata;
            end else if (sw_csr_wen) begin
                case (sw_csr_addr)
                    ADDR_MSTATUS:  r_mstatus  <= sw_csr_wdata;
                    ADDR_MIE:      r_mie      <= sw_csr_wdata;
                    ADDR_MTVEC:    r_mtvec    <= sw_csr_wdata;
                    ADDR_MSCRATCH: r_mscratch <= sw_csr_wdata;
                    ADDR_MEPC:     r_mepc     <= sw_csr_wdata;
                    ADDR_MCAUSE:   r_mcause   <= sw_csr_wdata;
                    ADDR_MTVAL:    r_mtval    <= sw_csr_wdata;
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (sw_csr_addr)
            ADDR_MSTATUS:  sw_csr_rdata = r_mstatus;
            ADDR_MIE:      sw_csr_rdata = r_mie;
            ADDR_MTVEC:    sw_csr_rdata = r_mtvec;
            ADDR_MSCRATCH: sw_csr_rdata = r_mscratch;
            ADDR_MEPC:     sw_csr_rdata = r_mepc;
            ADDR_MCAUSE:   sw_csr_rdata = r_mcause;
            ADDR_MTVAL:    sw_csr_rdata = r_mtval;
            ADDR_MIP:      sw_csr_rdata = r_mip;
            default:       sw_csr_rdata = 32'b0;
        endcase
    end

    assign csr_mstatus  = r_mstatus;
    assign csr_mie      = r_mie;
    assign csr_mtvec    = r_mtvec;
    assign csr_mscratch = r_mscratch;
    assign csr_mepc     = r_mepc;
    assign csr_mcause   = r_mcause;
    assign csr_mtval    = r_mtval;
    assign csr_mip      = r_mip;

endmodule
