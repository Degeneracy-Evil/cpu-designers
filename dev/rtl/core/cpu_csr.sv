`timescale 1ns / 1ps

module cpu_csr(
    input              clk,
    input              reset,

    input       [11:0] sw_csr_addr,
    input              sw_csr_wen,
    input       [31:0] sw_csr_wdata,
    output reg  [31:0] sw_csr_rdata,
    output             csr_addr_valid,
    output             csr_access_ok,

    input       [1:0]  priv_mode,

    input              hw_csr_wen,
    input       [1:0]  hw_target_priv,
    input       [31:0] hw_mepc_wdata,
    input       [31:0] hw_mcause_wdata,
    input       [31:0] hw_mtval_wdata,
    input       [31:0] hw_mstatus_wdata,
    input       [31:0] hw_sepc_wdata,
    input       [31:0] hw_scause_wdata,
    input       [31:0] hw_stval_wdata,
    input       [31:0] hw_sstatus_wdata,

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
    output      [31:0] csr_mip,
    output      [31:0] csr_medeleg,
    output      [31:0] csr_mideleg,
    output      [31:0] csr_sstatus,
    output      [31:0] csr_sie,
    output      [31:0] csr_stvec,
    output      [31:0] csr_sscratch,
    output      [31:0] csr_sepc,
    output      [31:0] csr_scause,
    output      [31:0] csr_stval,
    output      [31:0] csr_sip,
    output      [31:0] csr_satp,
    output      [31:0] csr_mcounteren,
    output      [31:0] csr_scounteren
);
    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;
    localparam PRIV_M = 2'b11;

    localparam ADDR_SSTATUS     = 12'h100;
    localparam ADDR_SIE         = 12'h104;
    localparam ADDR_STVEC       = 12'h105;
    localparam ADDR_SCOUNTEREN  = 12'h106;
    localparam ADDR_SSCRATCH    = 12'h140;
    localparam ADDR_SEPC        = 12'h141;
    localparam ADDR_SCAUSE      = 12'h142;
    localparam ADDR_STVAL       = 12'h143;
    localparam ADDR_SIP         = 12'h144;
    localparam ADDR_SATP        = 12'h180;

    localparam ADDR_MSTATUS     = 12'h300;
    localparam ADDR_MISA        = 12'h301;
    localparam ADDR_MEDELEG     = 12'h302;
    localparam ADDR_MIDELEG     = 12'h303;
    localparam ADDR_MIE         = 12'h304;
    localparam ADDR_MTVEC       = 12'h305;
    localparam ADDR_MCOUNTEREN  = 12'h306;
    localparam ADDR_MSTATUSH    = 12'h310;
    localparam ADDR_MSCRATCH    = 12'h340;
    localparam ADDR_MEPC        = 12'h341;
    localparam ADDR_MCAUSE      = 12'h342;
    localparam ADDR_MTVAL       = 12'h343;
    localparam ADDR_MIP         = 12'h344;
    localparam ADDR_MCYCLE      = 12'hB00;
    localparam ADDR_MINSTRET    = 12'hB02;
    localparam ADDR_MCYCLEH     = 12'hB80;
    localparam ADDR_MINSTRETH   = 12'hB82;
    localparam ADDR_MVENDORID   = 12'hF11;
    localparam ADDR_MARCHID     = 12'hF12;
    localparam ADDR_MIMPID      = 12'hF13;
    localparam ADDR_MHARTID     = 12'hF14;
    localparam ADDR_MCONFIGPTR  = 12'hF15;

    reg [31:0] r_mstatus;
    reg [31:0] r_mie;
    reg [31:0] r_mtvec;
    reg [31:0] r_mscratch;
    reg [31:0] r_mepc;
    reg [31:0] r_mcause;
    reg [31:0] r_mtval;
    reg [31:0] r_mip;
    reg [31:0] r_medeleg;
    reg [31:0] r_mideleg;
    reg [31:0] r_mcounteren;
    reg [63:0] r_mcycle;
    reg [63:0] r_minstret;

    reg [31:0] r_sie;
    reg [31:0] r_stvec;
    reg [31:0] r_sscratch;
    reg [31:0] r_sepc;
    reg [31:0] r_scause;
    reg [31:0] r_stval;
    reg [31:0] r_sip;
    reg [31:0] r_satp;
    reg [31:0] r_scounteren;

    wire [31:0] w_mip_hw;
    assign w_mip_hw = {20'b0, ext_meip, 3'b0, ext_mtip, 3'b0, ext_msip, 3'b0};

    wire sd_bit;
    assign sd_bit = (r_mstatus[14:13] != 2'b00) || (r_mstatus[16:15] != 2'b00);

    wire [31:0] w_sstatus;
    assign w_sstatus = {sd_bit, 1'b0, r_mstatus[30:23], r_mstatus[18], r_mstatus[19],
                        r_mstatus[16:13], 3'b0, r_mstatus[8], 4'b0,
                        r_mstatus[5], 3'b0, r_mstatus[1], 1'b0};

    function is_s_csr;
        input [11:0] addr;
        begin
            is_s_csr = (addr == ADDR_SSTATUS)   || (addr == ADDR_SIE)       ||
                       (addr == ADDR_STVEC)     || (addr == ADDR_SSCRATCH)  ||
                       (addr == ADDR_SEPC)      || (addr == ADDR_SCAUSE)    ||
                       (addr == ADDR_STVAL)     || (addr == ADDR_SIP)       ||
                       (addr == ADDR_SATP)      || (addr == ADDR_SCOUNTEREN);
        end
    endfunction

    function is_m_csr;
        input [11:0] addr;
        begin
            is_m_csr = (addr == ADDR_MSTATUS)    || (addr == ADDR_MISA)       ||
                       (addr == ADDR_MEDELEG)   || (addr == ADDR_MIDELEG)    ||
                       (addr == ADDR_MIE)       || (addr == ADDR_MTVEC)      ||
                       (addr == ADDR_MCOUNTEREN)|| (addr == ADDR_MSTATUSH)   ||
                       (addr == ADDR_MSCRATCH)  || (addr == ADDR_MEPC)       ||
                       (addr == ADDR_MCAUSE)    || (addr == ADDR_MTVAL)      ||
                       (addr == ADDR_MIP)       || (addr == ADDR_MCYCLE)     ||
                       (addr == ADDR_MINSTRET)  || (addr == ADDR_MCYCLEH)   ||
                       (addr == ADDR_MINSTRETH) || (addr == ADDR_MVENDORID) ||
                       (addr == ADDR_MARCHID)   || (addr == ADDR_MIMPID)    ||
                       (addr == ADDR_MHARTID)   || (addr == ADDR_MCONFIGPTR);
        end
    endfunction

    assign csr_addr_valid = is_s_csr(sw_csr_addr) || is_m_csr(sw_csr_addr);

    wire is_read_only_csr;
    assign is_read_only_csr = (sw_csr_addr == ADDR_MISA)     ||
                              (sw_csr_addr == ADDR_MSTATUSH)  ||
                              (sw_csr_addr == ADDR_MVENDORID) ||
                              (sw_csr_addr == ADDR_MARCHID)   ||
                              (sw_csr_addr == ADDR_MIMPID)    ||
                              (sw_csr_addr == ADDR_MHARTID)   ||
                              (sw_csr_addr == ADDR_MCONFIGPTR);

    always @(*) begin
        case (priv_mode)
            PRIV_U: csr_access_ok = 1'b0;
            PRIV_S: csr_access_ok = is_s_csr(sw_csr_addr) && !is_read_only_csr;
            PRIV_M: csr_access_ok = 1'b1;
            default: csr_access_ok = 1'b0;
        endcase
    end

    wire [31:0] mstatus_wmask;
    assign mstatus_wmask = {1'b0, sw_csr_wdata[30:23], sw_csr_wdata[18], sw_csr_wdata[19],
                            sw_csr_wdata[16:13], 1'b0, sw_csr_wdata[11:9], sw_csr_wdata[8],
                            sw_csr_wdata[7], 3'b0, sw_csr_wdata[3], 1'b0, sw_csr_wdata[1], 1'b0};

    wire [31:0] mie_wmask;
    assign mie_wmask = {20'd0, sw_csr_wdata[11], 3'd0, sw_csr_wdata[7], 3'd0, sw_csr_wdata[3], 3'd0};

    wire [31:0] mtvec_wmask;
    assign mtvec_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] mepc_wmask;
    assign mepc_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] medeleg_wmask;
    assign medeleg_wmask = sw_csr_wdata & 32'h0000_B3FF;

    wire [31:0] mideleg_wmask;
    assign mideleg_wmask = sw_csr_wdata & 32'h0000_0AAA;

    wire [31:0] sie_wmask;
    assign sie_wmask = {20'd0, sw_csr_wdata[9], 3'd0, sw_csr_wdata[5], 3'd0, sw_csr_wdata[1], 3'd0};

    wire [31:0] stvec_wmask;
    assign stvec_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] sepc_wmask;
    assign sepc_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] sip_wmask;
    assign sip_wmask = {31'd0, sw_csr_wdata[1]};

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
            r_medeleg   <= 32'b0;
            r_mideleg   <= 32'b0;
            r_mcounteren<= 32'b0;
            r_mcycle    <= 64'b0;
            r_minstret  <= 64'b0;
            r_sie       <= 32'b0;
            r_stvec     <= 32'b0;
            r_sscratch  <= 32'b0;
            r_sepc      <= 32'b0;
            r_scause    <= 32'b0;
            r_stval     <= 32'b0;
            r_sip       <= 32'b0;
            r_satp      <= 32'b0;
            r_scounteren<= 32'b0;
        end else begin
            r_mip <= w_mip_hw;

            if (cycle_en)
                r_mcycle <= r_mcycle + 64'd1;
            if (inst_retire)
                r_minstret <= r_minstret + 64'd1;

            if (hw_csr_wen) begin
                if (hw_target_priv == PRIV_M) begin
                    r_mepc    <= hw_mepc_wdata;
                    r_mcause  <= hw_mcause_wdata;
                    r_mtval   <= hw_mtval_wdata;
                    r_mstatus <= hw_mstatus_wdata;
                end else begin
                    r_sepc    <= hw_sepc_wdata;
                    r_scause  <= hw_scause_wdata;
                    r_stval   <= hw_stval_wdata;
                    r_mstatus <= hw_sstatus_wdata;
                end
            end else if (sw_csr_wen) begin
                case (sw_csr_addr)
                    ADDR_MSTATUS:    r_mstatus   <= mstatus_wmask;
                    ADDR_MIE:        r_mie       <= mie_wmask;
                    ADDR_MTVEC:      r_mtvec     <= mtvec_wmask;
                    ADDR_MSCRATCH:   r_mscratch  <= sw_csr_wdata;
                    ADDR_MEPC:       r_mepc      <= mepc_wmask;
                    ADDR_MCAUSE:     r_mcause    <= sw_csr_wdata;
                    ADDR_MTVAL:      r_mtval     <= sw_csr_wdata;
                    ADDR_MEDELEG:    r_medeleg   <= medeleg_wmask;
                    ADDR_MIDELEG:    r_mideleg   <= mideleg_wmask;
                    ADDR_MCOUNTEREN: r_mcounteren<= sw_csr_wdata;
                    ADDR_MCYCLE:     r_mcycle[31:0]  <= sw_csr_wdata;
                    ADDR_MCYCLEH:    r_mcycle[63:32] <= sw_csr_wdata;
                    ADDR_MINSTRET:   r_minstret[31:0]  <= sw_csr_wdata;
                    ADDR_MINSTRETH:  r_minstret[63:32] <= sw_csr_wdata;
                    ADDR_SSTATUS: begin
                        r_mstatus[1]   <= sw_csr_wdata[1];
                        r_mstatus[5]   <= sw_csr_wdata[5];
                        r_mstatus[8]   <= sw_csr_wdata[8];
                        r_mstatus[13]  <= sw_csr_wdata[13];
                        r_mstatus[14]  <= sw_csr_wdata[14];
                        r_mstatus[15]  <= sw_csr_wdata[15];
                        r_mstatus[16]  <= sw_csr_wdata[16];
                        r_mstatus[18]  <= sw_csr_wdata[18];
                        r_mstatus[19]  <= sw_csr_wdata[19];
                    end
                    ADDR_SIE:        r_sie       <= sie_wmask;
                    ADDR_STVEC:      r_stvec     <= stvec_wmask;
                    ADDR_SSCRATCH:   r_sscratch  <= sw_csr_wdata;
                    ADDR_SEPC:       r_sepc      <= sepc_wmask;
                    ADDR_SCAUSE:     r_scause    <= sw_csr_wdata;
                    ADDR_STVAL:      r_stval     <= sw_csr_wdata;
                    ADDR_SIP:        r_sip       <= sip_wmask;
                    ADDR_SATP:       r_satp      <= sw_csr_wdata;
                    ADDR_SCOUNTEREN: r_scounteren<= sw_csr_wdata;
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (sw_csr_addr)
            ADDR_SSTATUS:     sw_csr_rdata = w_sstatus;
            ADDR_SIE:         sw_csr_rdata = r_sie;
            ADDR_STVEC:       sw_csr_rdata = r_stvec;
            ADDR_SCOUNTEREN:  sw_csr_rdata = r_scounteren;
            ADDR_SSCRATCH:    sw_csr_rdata = r_sscratch;
            ADDR_SEPC:        sw_csr_rdata = r_sepc;
            ADDR_SCAUSE:      sw_csr_rdata = r_scause;
            ADDR_STVAL:       sw_csr_rdata = r_stval;
            ADDR_SIP:         sw_csr_rdata = {31'd0, r_sip[1]};
            ADDR_SATP:        sw_csr_rdata = r_satp;

            ADDR_MSTATUS:     sw_csr_rdata = {sd_bit, r_mstatus[30:0]};
            ADDR_MISA:        sw_csr_rdata = 32'h40141100;
            ADDR_MEDELEG:     sw_csr_rdata = r_medeleg;
            ADDR_MIDELEG:     sw_csr_rdata = r_mideleg;
            ADDR_MIE:         sw_csr_rdata = r_mie;
            ADDR_MTVEC:       sw_csr_rdata = r_mtvec;
            ADDR_MCOUNTEREN:  sw_csr_rdata = r_mcounteren;
            ADDR_MSTATUSH:    sw_csr_rdata = 32'b0;
            ADDR_MSCRATCH:    sw_csr_rdata = r_mscratch;
            ADDR_MEPC:        sw_csr_rdata = r_mepc;
            ADDR_MCAUSE:      sw_csr_rdata = r_mcause;
            ADDR_MTVAL:       sw_csr_rdata = r_mtval;
            ADDR_MIP:         sw_csr_rdata = r_mip;
            ADDR_MCYCLE:      sw_csr_rdata = r_mcycle[31:0];
            ADDR_MINSTRET:    sw_csr_rdata = r_minstret[31:0];
            ADDR_MCYCLEH:     sw_csr_rdata = r_mcycle[63:32];
            ADDR_MINSTRETH:   sw_csr_rdata = r_minstret[63:32];
            ADDR_MVENDORID:   sw_csr_rdata = 32'b0;
            ADDR_MARCHID:     sw_csr_rdata = 32'b0;
            ADDR_MIMPID:      sw_csr_rdata = 32'b0;
            ADDR_MHARTID:     sw_csr_rdata = 32'b0;
            ADDR_MCONFIGPTR:  sw_csr_rdata = 32'b0;
            default:          sw_csr_rdata = 32'b0;
        endcase
    end

    assign csr_mstatus   = {sd_bit, r_mstatus[30:0]};
    assign csr_mie       = r_mie;
    assign csr_mtvec     = r_mtvec;
    assign csr_mscratch  = r_mscratch;
    assign csr_mepc      = r_mepc;
    assign csr_mcause    = r_mcause;
    assign csr_mtval     = r_mtval;
    assign csr_mip       = r_mip;
    assign csr_medeleg   = r_medeleg;
    assign csr_mideleg   = r_mideleg;
    assign csr_sstatus   = w_sstatus;
    assign csr_sie       = r_sie;
    assign csr_stvec     = r_stvec;
    assign csr_sscratch  = r_sscratch;
    assign csr_sepc      = r_sepc;
    assign csr_scause    = r_scause;
    assign csr_stval     = r_stval;
    assign csr_sip       = r_sip;
    assign csr_satp      = r_satp;
    assign csr_mcounteren= r_mcounteren;
    assign csr_scounteren= r_scounteren;

endmodule
