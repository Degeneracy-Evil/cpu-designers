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

    input              cycle_en,
    input              inst_retire,

    output      [31:0] csr_mstatus,
    output      [31:0] csr_mie,
    output      [31:0] csr_mtvec,
    output      [31:0] csr_mscratch,
    output      [31:0] csr_mepc,
    output      [31:0] csr_mcause,
    output      [31:0] csr_mtval,
    output      [31:0] csr_mip
);
    localparam ADDR_MSTATUS    = 12'h300;
    localparam ADDR_MISA       = 12'h301;
    localparam ADDR_MIE        = 12'h304;
    localparam ADDR_MTVEC      = 12'h305;
    localparam ADDR_MSTATUSH   = 12'h310;
    localparam ADDR_MSCRATCH   = 12'h340;
    localparam ADDR_MEPC       = 12'h341;
    localparam ADDR_MCAUSE     = 12'h342;
    localparam ADDR_MTVAL      = 12'h343;
    localparam ADDR_MIP        = 12'h344;
    localparam ADDR_MCYCLE     = 12'hB00;
    localparam ADDR_MINSTRET   = 12'hB02;
    localparam ADDR_MCYCLEH    = 12'hB80;
    localparam ADDR_MINSTRETH  = 12'hB82;
    localparam ADDR_MVENDORID  = 12'hF11;
    localparam ADDR_MARCHID    = 12'hF12;
    localparam ADDR_MIMPID     = 12'hF13;
    localparam ADDR_MHARTID    = 12'hF14;
    localparam ADDR_MCONFIGPTR = 12'hF15;

    reg [31:0] r_mstatus;
    reg [31:0] r_mie;
    reg [31:0] r_mtvec;
    reg [31:0] r_mscratch;
    reg [31:0] r_mepc;
    reg [31:0] r_mcause;
    reg [31:0] r_mtval;
    reg [31:0] r_mip;
    reg [63:0] r_mcycle;
    reg [63:0] r_minstret;

    wire [31:0] w_mip_hw;
    assign w_mip_hw = {20'b0, ext_meip, 3'b0, ext_mtip, 3'b0, ext_msip, 3'b0};

    assign csr_addr_valid = (sw_csr_addr == ADDR_MSTATUS)    ||
                            (sw_csr_addr == ADDR_MISA)       ||
                            (sw_csr_addr == ADDR_MIE)        ||
                            (sw_csr_addr == ADDR_MTVEC)      ||
                            (sw_csr_addr == ADDR_MSTATUSH)   ||
                            (sw_csr_addr == ADDR_MSCRATCH)   ||
                            (sw_csr_addr == ADDR_MEPC)       ||
                            (sw_csr_addr == ADDR_MCAUSE)     ||
                            (sw_csr_addr == ADDR_MTVAL)      ||
                            (sw_csr_addr == ADDR_MIP)        ||
                            (sw_csr_addr == ADDR_MCYCLE)     ||
                            (sw_csr_addr == ADDR_MINSTRET)   ||
                            (sw_csr_addr == ADDR_MCYCLEH)    ||
                            (sw_csr_addr == ADDR_MINSTRETH)  ||
                            (sw_csr_addr == ADDR_MVENDORID)  ||
                            (sw_csr_addr == ADDR_MARCHID)    ||
                            (sw_csr_addr == ADDR_MIMPID)     ||
                            (sw_csr_addr == ADDR_MHARTID)    ||
                            (sw_csr_addr == ADDR_MCONFIGPTR);

    wire [31:0] mstatus_wmask;
    assign mstatus_wmask = {19'd0, 2'b11, 2'd0, 1'b0, sw_csr_wdata[7], 3'd0, sw_csr_wdata[3], 3'd0};

    wire [31:0] mie_wmask;
    assign mie_wmask = {20'd0, sw_csr_wdata[11], 3'd0, sw_csr_wdata[7], 3'd0, sw_csr_wdata[3], 3'd0};

    wire [31:0] mtvec_wmask;
    assign mtvec_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] mepc_wmask;
    assign mepc_wmask = {sw_csr_wdata[31:2], 2'b00};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_mstatus   <= 32'h00001800;
            r_mie       <= 32'b0;
            r_mtvec     <= 32'b0;
            r_mscratch  <= 32'b0;
            r_mepc      <= 32'b0;
            r_mcause    <= 32'b0;
            r_mtval     <= 32'b0;
            r_mip       <= 32'b0;
            r_mcycle    <= 64'b0;
            r_minstret  <= 64'b0;
        end else begin
            r_mip <= w_mip_hw;

            if (cycle_en)
                r_mcycle <= r_mcycle + 64'd1;
            if (inst_retire)
                r_minstret <= r_minstret + 64'd1;

            if (hw_csr_wen) begin
                r_mepc    <= hw_mepc_wdata;
                r_mcause  <= hw_mcause_wdata;
                r_mtval   <= hw_mtval_wdata;
                r_mstatus <= hw_mstatus_wdata;
            end else if (sw_csr_wen) begin
                case (sw_csr_addr)
                    ADDR_MSTATUS:  r_mstatus  <= mstatus_wmask;
                    ADDR_MIE:      r_mie      <= mie_wmask;
                    ADDR_MTVEC:    r_mtvec    <= mtvec_wmask;
                    ADDR_MSCRATCH: r_mscratch <= sw_csr_wdata;
                    ADDR_MEPC:     r_mepc     <= mepc_wmask;
                    ADDR_MCAUSE:   r_mcause   <= sw_csr_wdata;
                    ADDR_MTVAL:    r_mtval    <= sw_csr_wdata;
                    ADDR_MCYCLE:   r_mcycle[31:0]  <= sw_csr_wdata;
                    ADDR_MCYCLEH:  r_mcycle[63:32] <= sw_csr_wdata;
                    ADDR_MINSTRET:  r_minstret[31:0]  <= sw_csr_wdata;
                    ADDR_MINSTRETH: r_minstret[63:32] <= sw_csr_wdata;
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (sw_csr_addr)
            ADDR_MSTATUS:    sw_csr_rdata = r_mstatus;
            ADDR_MISA:       sw_csr_rdata = 32'h40001100;
            ADDR_MIE:        sw_csr_rdata = r_mie;
            ADDR_MTVEC:      sw_csr_rdata = r_mtvec;
            ADDR_MSTATUSH:   sw_csr_rdata = 32'b0;
            ADDR_MSCRATCH:   sw_csr_rdata = r_mscratch;
            ADDR_MEPC:       sw_csr_rdata = r_mepc;
            ADDR_MCAUSE:     sw_csr_rdata = r_mcause;
            ADDR_MTVAL:      sw_csr_rdata = r_mtval;
            ADDR_MIP:        sw_csr_rdata = r_mip;
            ADDR_MCYCLE:     sw_csr_rdata = r_mcycle[31:0];
            ADDR_MINSTRET:   sw_csr_rdata = r_minstret[31:0];
            ADDR_MCYCLEH:    sw_csr_rdata = r_mcycle[63:32];
            ADDR_MINSTRETH:  sw_csr_rdata = r_minstret[63:32];
            ADDR_MVENDORID:  sw_csr_rdata = 32'b0;
            ADDR_MARCHID:    sw_csr_rdata = 32'b0;
            ADDR_MIMPID:     sw_csr_rdata = 32'b0;
            ADDR_MHARTID:    sw_csr_rdata = 32'b0;
            ADDR_MCONFIGPTR: sw_csr_rdata = 32'b0;
            default:         sw_csr_rdata = 32'b0;
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
