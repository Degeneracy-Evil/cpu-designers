`timescale 1ns / 1ps

module cpu_csr(
    input              clk,
    input              resetn,

    input       [11:0] sw_csr_addr,
    input              sw_csr_wen,
    input       [31:0] sw_csr_wdata,
    output     [31:0] sw_csr_rdata,
    output             csr_addr_valid,
    output             csr_access_ok,

    input       [1:0]  priv_mode,

    input              hw_csr_wen,
    input              hw_trap_is_enter,
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
    input              ext_seip,
    input              ext_mtip,
    input              ext_msip,
    input       [63:0] ext_mtime,

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
    output      [31:0] csr_scounteren,

    output      [4:0]  csr_fflags,
    output      [2:0]  csr_frm,

    // PMP config outputs (for future hardware enforcement)
    output      [31:0] csr_pmpcfg0,
    output      [31:0] csr_pmpcfg1,
    output      [31:0] csr_pmpcfg2,
    output      [31:0] csr_pmpcfg3,
    output      [31:0] csr_pmpaddr0,
    output      [31:0] csr_pmpaddr1,
    output      [31:0] csr_pmpaddr2,
    output      [31:0] csr_pmpaddr3,
    output      [31:0] csr_pmpaddr4,
    output      [31:0] csr_pmpaddr5,
    output      [31:0] csr_pmpaddr6,
    output      [31:0] csr_pmpaddr7,
    output      [31:0] csr_pmpaddr8,
    output      [31:0] csr_pmpaddr9,
    output      [31:0] csr_pmpaddr10,
    output      [31:0] csr_pmpaddr11,
    output      [31:0] csr_pmpaddr12,
    output      [31:0] csr_pmpaddr13,
    output      [31:0] csr_pmpaddr14,
    output      [31:0] csr_pmpaddr15,

    input       [4:0]  fflags_wdata,
    input              fflags_wen
);
    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;
    localparam PRIV_M = 2'b11;

    localparam ADDR_FFLAGS      = 12'h001;
    localparam ADDR_FRM        = 12'h002;
    localparam ADDR_FCSR       = 12'h003;

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

    // U-mode counter aliases (read-only shadows of M-mode counters)
    localparam ADDR_CYCLE       = 12'hC00;
    localparam ADDR_TIME        = 12'hC01;
    localparam ADDR_INSTRET     = 12'hC02;
    localparam ADDR_CYCLEH      = 12'hC80;
    localparam ADDR_TIMEH       = 12'hC81;
    localparam ADDR_INSTRETH    = 12'hC82;
    localparam ADDR_PMPCFG0     = 12'h3A0;
    localparam ADDR_PMPCFG1     = 12'h3A1;
    localparam ADDR_PMPCFG2     = 12'h3A2;
    localparam ADDR_PMPCFG3     = 12'h3A3;
    localparam ADDR_PMPADDR0    = 12'h3B0;
    localparam ADDR_PMPADDR1    = 12'h3B1;
    localparam ADDR_PMPADDR2    = 12'h3B2;
    localparam ADDR_PMPADDR3    = 12'h3B3;
    localparam ADDR_PMPADDR4    = 12'h3B4;
    localparam ADDR_PMPADDR5    = 12'h3B5;
    localparam ADDR_PMPADDR6    = 12'h3B6;
    localparam ADDR_PMPADDR7    = 12'h3B7;
    localparam ADDR_PMPADDR8    = 12'h3B8;
    localparam ADDR_PMPADDR9    = 12'h3B9;
    localparam ADDR_PMPADDR10   = 12'h3BA;
    localparam ADDR_PMPADDR11   = 12'h3BB;
    localparam ADDR_PMPADDR12   = 12'h3BC;
    localparam ADDR_PMPADDR13   = 12'h3BD;
    localparam ADDR_PMPADDR14   = 12'h3BE;
    localparam ADDR_PMPADDR15   = 12'h3BF;
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

    reg [4:0]  r_fflags;
    reg [2:0]  r_frm;

    // PMP registers: 4 config registers (each holds 4 byte-sized PMP configs)
    // and 16 address registers. Per RISC-V spec, reset clears A and L fields.
    reg [31:0] r_pmpcfg0;
    reg [31:0] r_pmpcfg1;
    reg [31:0] r_pmpcfg2;
    reg [31:0] r_pmpcfg3;
    reg [31:0] r_pmpaddr0;
    reg [31:0] r_pmpaddr1;
    reg [31:0] r_pmpaddr2;
    reg [31:0] r_pmpaddr3;
    reg [31:0] r_pmpaddr4;
    reg [31:0] r_pmpaddr5;
    reg [31:0] r_pmpaddr6;
    reg [31:0] r_pmpaddr7;
    reg [31:0] r_pmpaddr8;
    reg [31:0] r_pmpaddr9;
    reg [31:0] r_pmpaddr10;
    reg [31:0] r_pmpaddr11;
    reg [31:0] r_pmpaddr12;
    reg [31:0] r_pmpaddr13;
    reg [31:0] r_pmpaddr14;
    reg [31:0] r_pmpaddr15;

    wire [31:0] w_mip_hw;
    assign w_mip_hw = {20'b0, ext_meip, 3'b0, ext_mtip, 3'b0, ext_msip, 3'b0};

    wire sd_bit;
    assign sd_bit = (r_mstatus[14:13] != 2'b00) || (r_mstatus[16:15] != 2'b00);

    wire [31:0] w_sstatus;
    wire [31:0] w_sip;
    assign w_sstatus = {sd_bit,
                        8'b0,
                        3'b000,
                        r_mstatus[19],
                        r_mstatus[18],
                        r_mstatus[17],
                        r_mstatus[16:15],
                        r_mstatus[14:13],
                        2'b00,
                        2'b00,
                        r_mstatus[8],
                        1'b0,
                        1'b0,
                        r_mstatus[5],
                        1'b0,
                        1'b0,
                        1'b0,
                        r_mstatus[1],
                        1'b0};
    assign w_sip = {22'd0, (ext_seip | r_sip[9]), 3'b0, r_sip[5], 3'b0, r_sip[1], 1'b0};

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

    function is_u_csr;
        input [11:0] addr;
        begin
            // U-mode counter aliases: cycle, time, instret, cycleh, timeh, instreth
            is_u_csr = (addr == ADDR_CYCLE)    || (addr == ADDR_TIME)      ||
                       (addr == ADDR_INSTRET)  ||
                       (addr == ADDR_CYCLEH)   || (addr == ADDR_TIMEH)    ||
                       (addr == ADDR_INSTRETH);
        end
    endfunction

    function is_m_csr;
        input [11:0] addr;
        begin
            is_m_csr = (addr == ADDR_FFLAGS)    || (addr == ADDR_FRM)        ||
                       (addr == ADDR_FCSR)      ||
                       (addr == ADDR_MSTATUS)    || (addr == ADDR_MISA)       ||
                       (addr == ADDR_MEDELEG)   || (addr == ADDR_MIDELEG)    ||
                       (addr == ADDR_MIE)       || (addr == ADDR_MTVEC)      ||
                       (addr == ADDR_MCOUNTEREN)|| (addr == ADDR_MSTATUSH)   ||
                       (addr == ADDR_MSCRATCH)  || (addr == ADDR_MEPC)       ||
                       (addr == ADDR_MCAUSE)    || (addr == ADDR_MTVAL)      ||
                       (addr == ADDR_MIP)       || (addr == ADDR_MCYCLE)     ||
                       (addr == ADDR_MINSTRET)  || (addr == ADDR_MCYCLEH)   ||
                       (addr == ADDR_MINSTRETH) || (addr == ADDR_MVENDORID) ||
                       (addr == ADDR_MARCHID)   || (addr == ADDR_MIMPID)    ||
                        (addr == ADDR_MHARTID)   || (addr == ADDR_MCONFIGPTR)||
                        (addr == ADDR_TIME)      || (addr == ADDR_TIMEH);
        end
    endfunction

    function is_pmp_csr;
        input [11:0] addr;
        begin
            // PMP CSRs: pmpcfg0-3 (0x3A0-0x3A3) and pmpaddr0-15 (0x3B0-0x3BF)
            // Only M-mode can access PMP CSRs
            is_pmp_csr = (addr == ADDR_PMPCFG0)  || (addr == ADDR_PMPCFG1)  ||
                         (addr == ADDR_PMPCFG2)  || (addr == ADDR_PMPCFG3)  ||
                         (addr == ADDR_PMPADDR0) || (addr == ADDR_PMPADDR1) ||
                         (addr == ADDR_PMPADDR2) || (addr == ADDR_PMPADDR3) ||
                         (addr == ADDR_PMPADDR4) || (addr == ADDR_PMPADDR5) ||
                         (addr == ADDR_PMPADDR6) || (addr == ADDR_PMPADDR7) ||
                         (addr == ADDR_PMPADDR8) || (addr == ADDR_PMPADDR9) ||
                         (addr == ADDR_PMPADDR10)|| (addr == ADDR_PMPADDR11)||
                         (addr == ADDR_PMPADDR12)|| (addr == ADDR_PMPADDR13)||
                         (addr == ADDR_PMPADDR14)|| (addr == ADDR_PMPADDR15);
        end
    endfunction

    // Accept ALL CSR addresses as valid. Unimplemented CSRs read as 0 and
    // silently ignore writes. This prevents OpenSBI from trapping on optional
    // feature probes (tselect, mhpmevent, mstateen, debug/trace CSRs, etc.).
    assign csr_addr_valid = 1'b1;

    wire is_read_only_csr;
    assign is_read_only_csr = (sw_csr_addr == ADDR_MISA)     ||
                              (sw_csr_addr == ADDR_MSTATUSH)  ||
                              (sw_csr_addr == ADDR_MVENDORID) ||
                              (sw_csr_addr == ADDR_MARCHID)   ||
                              (sw_csr_addr == ADDR_MIMPID)    ||
                              (sw_csr_addr == ADDR_MHARTID)   ||
                              (sw_csr_addr == ADDR_MCONFIGPTR)||
                              // U-mode counter aliases are read-only
                              (sw_csr_addr == ADDR_CYCLE)    ||
                              (sw_csr_addr == ADDR_TIME)     ||
                              (sw_csr_addr == ADDR_INSTRET)  ||
                              (sw_csr_addr == ADDR_CYCLEH)   ||
                              (sw_csr_addr == ADDR_TIMEH)   ||
                              (sw_csr_addr == ADDR_INSTRETH);

    reg csr_access_ok_r;
    always_comb begin
        case (priv_mode)
            PRIV_U: begin
                // U-mode can read counter aliases (cycle/time/instret) if
                // mcounteren allows; writes are blocked by is_read_only_csr
                // checked in cpu_decode.sv (write_ro_csr).
                csr_access_ok_r = is_u_csr(sw_csr_addr) && u_counter_allowed;
            end
            PRIV_S: begin
                // S-mode can access own CSRs and U-mode counter aliases
                // (if both mcounteren and scounteren allow).
                // Read-only check for writes is handled in cpu_decode.sv.
                csr_access_ok_r = is_s_csr(sw_csr_addr) || (is_u_csr(sw_csr_addr) && s_counter_allowed);
            end
            PRIV_M: csr_access_ok_r = 1'b1;
            default: csr_access_ok_r = 1'b0;
        endcase
    end
    assign csr_access_ok = csr_access_ok_r;

    // ── PMP lock-bit enforcement ──
    // PMP config byte format: bit7=L, bit6:5=reserved(0), bit4:3=A, bit2=X, bit1=W, bit0=R
    // When L=1 for a PMP entry, both pmpcfg and pmpaddr become read-only until reset.
    // pmpcfg0 holds entries 0-3, pmpcfg1 holds 4-7, pmpcfg2 holds 8-11, pmpcfg3 holds 12-15.
    wire pmp_entry0_locked  = r_pmpcfg0[7];    // entry 0: pmpcfg0 byte 0, bit 7
    wire pmp_entry1_locked  = r_pmpcfg0[15];   // entry 1: pmpcfg0 byte 1, bit 7
    wire pmp_entry2_locked  = r_pmpcfg0[23];   // entry 2: pmpcfg0 byte 2, bit 7
    wire pmp_entry3_locked  = r_pmpcfg0[31];   // entry 3: pmpcfg0 byte 3, bit 7
    wire pmp_entry4_locked  = r_pmpcfg1[7];
    wire pmp_entry5_locked  = r_pmpcfg1[15];
    wire pmp_entry6_locked  = r_pmpcfg1[23];
    wire pmp_entry7_locked  = r_pmpcfg1[31];
    wire pmp_entry8_locked  = r_pmpcfg2[7];
    wire pmp_entry9_locked  = r_pmpcfg2[15];
    wire pmp_entry10_locked = r_pmpcfg2[23];
    wire pmp_entry11_locked = r_pmpcfg2[31];
    wire pmp_entry12_locked = r_pmpcfg3[7];
    wire pmp_entry13_locked = r_pmpcfg3[15];
    wire pmp_entry14_locked = r_pmpcfg3[23];
    wire pmp_entry15_locked = r_pmpcfg3[31];

    // PMP config write masks: clear locked entries' bytes (L=1 → byte becomes read-only)
    // Per RISC-V spec: A field is WARL (only OFF=00 and TOR=01 supported in minimal impl)
    // Reserved bits [6:5] always read 0.
    wire [31:0] pmpcfg0_wmask;
    assign pmpcfg0_wmask = {(pmp_entry3_locked ? 8'b0 : (sw_csr_wdata[31:24] & 8'h9F)),  // L,A,X,W,R; bits[6:5]=0
                            (pmp_entry2_locked ? 8'b0 : (sw_csr_wdata[23:16] & 8'h9F)),
                            (pmp_entry1_locked ? 8'b0 : (sw_csr_wdata[15:8]  & 8'h9F)),
                            (pmp_entry0_locked ? 8'b0 : (sw_csr_wdata[7:0]   & 8'h9F))};

    wire [31:0] pmpcfg1_wmask;
    assign pmpcfg1_wmask = {(pmp_entry7_locked ? 8'b0 : (sw_csr_wdata[31:24] & 8'h9F)),
                            (pmp_entry6_locked ? 8'b0 : (sw_csr_wdata[23:16] & 8'h9F)),
                            (pmp_entry5_locked ? 8'b0 : (sw_csr_wdata[15:8]  & 8'h9F)),
                            (pmp_entry4_locked ? 8'b0 : (sw_csr_wdata[7:0]   & 8'h9F))};

    wire [31:0] pmpcfg2_wmask;
    assign pmpcfg2_wmask = {(pmp_entry11_locked ? 8'b0 : (sw_csr_wdata[31:24] & 8'h9F)),
                            (pmp_entry10_locked ? 8'b0 : (sw_csr_wdata[23:16] & 8'h9F)),
                            (pmp_entry9_locked  ? 8'b0 : (sw_csr_wdata[15:8]  & 8'h9F)),
                            (pmp_entry8_locked  ? 8'b0 : (sw_csr_wdata[7:0]   & 8'h9F))};

    wire [31:0] pmpcfg3_wmask;
    assign pmpcfg3_wmask = {(pmp_entry15_locked ? 8'b0 : (sw_csr_wdata[31:24] & 8'h9F)),
                            (pmp_entry14_locked ? 8'b0 : (sw_csr_wdata[23:16] & 8'h9F)),
                            (pmp_entry13_locked ? 8'b0 : (sw_csr_wdata[15:8]  & 8'h9F)),
                            (pmp_entry12_locked ? 8'b0 : (sw_csr_wdata[7:0]   & 8'h9F))};

    // ── Counter access permission checks ──
    // mcounteren/scounteren bit mapping:
    //   bit 0 = cycle/cycleh, bit 1 = time/timeh, bit 2 = instret/instreth
    // U-mode access allowed if mcounteren bit is set.
    // S-mode access to U-mode aliases allowed if both mcounteren and scounteren bits are set.
    wire [2:0] counter_idx;
    assign counter_idx = (sw_csr_addr == ADDR_CYCLE  || sw_csr_addr == ADDR_CYCLEH)  ? 3'd0 :
                         (sw_csr_addr == ADDR_TIME   || sw_csr_addr == ADDR_TIMEH)   ? 3'd1 :
                         (sw_csr_addr == ADDR_INSTRET|| sw_csr_addr == ADDR_INSTRETH) ? 3'd2 : 3'd0;

    wire u_counter_allowed = r_mcounteren[counter_idx];
    wire s_counter_allowed = r_mcounteren[counter_idx] && r_scounteren[counter_idx];

    wire [31:0] mstatus_wmask;
    assign mstatus_wmask = {1'b0,
                            sw_csr_wdata[30:23],
                            sw_csr_wdata[22],
                            sw_csr_wdata[21],
                            sw_csr_wdata[20],
                            sw_csr_wdata[19],
                            sw_csr_wdata[18],
                            sw_csr_wdata[17],
                            sw_csr_wdata[16:15],
                            sw_csr_wdata[14:13],
                            sw_csr_wdata[12:11],
                            2'b00,
                            sw_csr_wdata[8],
                            sw_csr_wdata[7],
                            1'b0,
                            sw_csr_wdata[5],
                            1'b0,
                            sw_csr_wdata[3],
                            1'b0,
                            sw_csr_wdata[1],
                            1'b0};

    wire [31:0] mie_wmask;
    assign mie_wmask = {20'd0, sw_csr_wdata[11], 3'd0, sw_csr_wdata[7], 3'd0, sw_csr_wdata[3], 3'd0};

    wire [31:0] mtvec_wmask;
    assign mtvec_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] mepc_wmask;
    assign mepc_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] medeleg_wmask;
    // S-mode ecall (cause 9) must not be delegatable. Linux issues SBI calls
    // via ecall from S-mode, which must trap to M-mode/OpenSBI rather than
    // looping back into the S-mode trap handler.
    assign medeleg_wmask = sw_csr_wdata & 32'h0000_B1FF;

    // BUG-FIX (sub-issue ⑤): Per RISC-V Privileged Spec, M-mode interrupts
    // (MSI=3, MTI=7, MEI=11) are NOT delegatable and must be hardwired to 0.
    // Old mask 0xAAA allowed writing bits 3,7,11 — if set, M-mode interrupts
    // would be incorrectly delegated to S-mode (e.g., PLIC MEI→S-mode).
    wire [31:0] mideleg_wmask;
    assign mideleg_wmask = sw_csr_wdata & 32'h0000_0222;  // only SSI(1), STI(5), SEI(9)

    wire [31:0] sie_wmask;
    assign sie_wmask = {20'd0, sw_csr_wdata[9], 3'd0, sw_csr_wdata[5], 3'd0, sw_csr_wdata[1], 3'd0};

    wire [31:0] stvec_wmask;
    assign stvec_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] sepc_wmask;
    assign sepc_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] sip_wmask;
    // BUG-FIX: Allow writing sip[5] (STIP) in addition to sip[1] (SSIP).
    // Per RISC-V spec, S-mode can write STIP to set/clear the S-mode timer
    // interrupt pending bit. This is essential for software-interrupt-based
    // timer emulation when mideleg[5]=0 (timer not delegated to S-mode).
    assign sip_wmask = {22'd0, sw_csr_wdata[9], 3'b0, sw_csr_wdata[5], 3'b0, sw_csr_wdata[1], 1'b0};

    // Merged fflags write logic: resolves conflict between software CSR write
    // and hardware OR-accumulate. When both occur in the same cycle, the
    // software value is written first, then hardware flags are OR-accumulated
    // on top of it (per F extension spec 21.2).
    wire [4:0] fflags_sw_new;
    wire       fflags_sw_wen;
    assign fflags_sw_new = (sw_csr_addr == ADDR_FFLAGS) ? sw_csr_wdata[4:0] :
                           (sw_csr_addr == ADDR_FCSR)   ? sw_csr_wdata[4:0] : r_fflags;
    assign fflags_sw_wen = sw_csr_wen && (sw_csr_addr == ADDR_FFLAGS ||
                                          sw_csr_addr == ADDR_FCSR);

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
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
            r_fflags    <= 5'b0;
            r_frm       <= 3'b0;
            // PMP: per RISC-V spec, reset clears A and L fields of all PMP entries
            r_pmpcfg0   <= 32'b0;
            r_pmpcfg1   <= 32'b0;
            r_pmpcfg2   <= 32'b0;
            r_pmpcfg3   <= 32'b0;
            r_pmpaddr0  <= 32'b0;
            r_pmpaddr1  <= 32'b0;
            r_pmpaddr2  <= 32'b0;
            r_pmpaddr3  <= 32'b0;
            r_pmpaddr4  <= 32'b0;
            r_pmpaddr5  <= 32'b0;
            r_pmpaddr6  <= 32'b0;
            r_pmpaddr7  <= 32'b0;
            r_pmpaddr8  <= 32'b0;
            r_pmpaddr9  <= 32'b0;
            r_pmpaddr10 <= 32'b0;
            r_pmpaddr11 <= 32'b0;
            r_pmpaddr12 <= 32'b0;
            r_pmpaddr13 <= 32'b0;
            r_pmpaddr14 <= 32'b0;
            r_pmpaddr15 <= 32'b0;
        end else begin
            // mip construction:
            //   bit 11 = MEIP (ext_meip, from PLIC context 0)
            //   bit  9 = SEIP (ext_seip | r_sip[9]), PLIC context 1 OR software write
            //   bit  7 = MTIP (ext_mtip, from CLINT)
            //   bit  5 = STIP (r_sip[5]), software write only
            //   bit  3 = MSIP (ext_msip, from CLINT)
            //   bit  1 = SSIP (r_sip[1]), software write only
            r_mip <= {w_mip_hw[31:10], (ext_seip | r_sip[9]), w_mip_hw[8:6], r_sip[5], w_mip_hw[4:2], r_sip[1], w_mip_hw[0]};

            if (cycle_en)
                r_mcycle <= r_mcycle + 64'd1;
            if (inst_retire)
                r_minstret <= r_minstret + 64'd1;

            if (hw_csr_wen) begin
                if (hw_target_priv == PRIV_M) begin
                    if (hw_trap_is_enter) begin
                        r_mepc    <= hw_mepc_wdata;
                        r_mcause  <= hw_mcause_wdata;
                        r_mtval   <= hw_mtval_wdata;
                    end
                    r_mstatus <= hw_mstatus_wdata;
                end else begin
                    if (hw_trap_is_enter) begin
                        r_sepc    <= hw_sepc_wdata;
                        r_scause  <= hw_scause_wdata;
                        r_stval   <= hw_stval_wdata;
                    end
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
                    ADDR_MIP: begin
                        // M-mode writes to mip update only software-writable bits
                        // via r_sip. Hardware bits (MTIP/MSIP/MEIP) are read-only.
                        //   bit 9 = SEIP (software portion, OR'd with ext_seip)
                        //   bit 5 = STIP
                        //   bit 1 = SSIP
                        // This allows OpenSBI to inject/clear STIP and SSIP via
                        // csr_set(CSR_MIP, ...) / csr_clear(CSR_MIP, ...).
                        r_sip[9] <= sw_csr_wdata[9];
                        r_sip[5] <= sw_csr_wdata[5];
                        r_sip[1] <= sw_csr_wdata[1];
                    end
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
                        r_mstatus[17]  <= sw_csr_wdata[17];
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
                    ADDR_SCOUNTEREN: if (priv_mode != PRIV_U) r_scounteren <= sw_csr_wdata;
                    ADDR_FFLAGS: ;  // fflags handled by merged logic below
                    ADDR_FRM:        r_frm       <= sw_csr_wdata[2:0];
                    ADDR_FCSR:       r_frm       <= sw_csr_wdata[7:5];  // fflags handled by merged logic below
                    // PMP config writes: lock-bit enforcement via pmpcfg*_wmask
                    ADDR_PMPCFG0:    r_pmpcfg0   <= pmpcfg0_wmask;
                    ADDR_PMPCFG1:    r_pmpcfg1   <= pmpcfg1_wmask;
                    ADDR_PMPCFG2:    r_pmpcfg2   <= pmpcfg2_wmask;
                    ADDR_PMPCFG3:    r_pmpcfg3   <= pmpcfg3_wmask;
                    // PMP address writes: locked entries cannot be modified
                    ADDR_PMPADDR0:  if (!pmp_entry0_locked)  r_pmpaddr0  <= sw_csr_wdata;
                    ADDR_PMPADDR1:  if (!pmp_entry1_locked)  r_pmpaddr1  <= sw_csr_wdata;
                    ADDR_PMPADDR2:  if (!pmp_entry2_locked)  r_pmpaddr2  <= sw_csr_wdata;
                    ADDR_PMPADDR3:  if (!pmp_entry3_locked)  r_pmpaddr3  <= sw_csr_wdata;
                    ADDR_PMPADDR4:  if (!pmp_entry4_locked)  r_pmpaddr4  <= sw_csr_wdata;
                    ADDR_PMPADDR5:  if (!pmp_entry5_locked)  r_pmpaddr5  <= sw_csr_wdata;
                    ADDR_PMPADDR6:  if (!pmp_entry6_locked)  r_pmpaddr6  <= sw_csr_wdata;
                    ADDR_PMPADDR7:  if (!pmp_entry7_locked)  r_pmpaddr7  <= sw_csr_wdata;
                    ADDR_PMPADDR8:  if (!pmp_entry8_locked)  r_pmpaddr8  <= sw_csr_wdata;
                    ADDR_PMPADDR9:  if (!pmp_entry9_locked)  r_pmpaddr9  <= sw_csr_wdata;
                    ADDR_PMPADDR10: if (!pmp_entry10_locked) r_pmpaddr10 <= sw_csr_wdata;
                    ADDR_PMPADDR11: if (!pmp_entry11_locked) r_pmpaddr11 <= sw_csr_wdata;
                    ADDR_PMPADDR12: if (!pmp_entry12_locked) r_pmpaddr12 <= sw_csr_wdata;
                    ADDR_PMPADDR13: if (!pmp_entry13_locked) r_pmpaddr13 <= sw_csr_wdata;
                    ADDR_PMPADDR14: if (!pmp_entry14_locked) r_pmpaddr14 <= sw_csr_wdata;
                    ADDR_PMPADDR15: if (!pmp_entry15_locked) r_pmpaddr15 <= sw_csr_wdata;
                    default: ;
                endcase
            end

            // Merged fflags write: software write + hardware OR-accumulate
            // When both occur simultaneously, software value is applied first,
            // then hardware flags are OR-accumulated on the new value.
            if (fflags_sw_wen && fflags_wen)
                r_fflags <= fflags_sw_new | fflags_wdata;
            else if (fflags_sw_wen)
                r_fflags <= fflags_sw_new;
            else if (fflags_wen)
                r_fflags <= r_fflags | fflags_wdata;
        end
    end

    reg [31:0] sw_csr_rdata_r;
    always_comb begin
        case (sw_csr_addr)
            ADDR_FFLAGS:      sw_csr_rdata_r = {27'b0, r_fflags};
            ADDR_FRM:         sw_csr_rdata_r = {29'b0, r_frm};
            ADDR_FCSR:        sw_csr_rdata_r = {24'b0, r_frm, r_fflags};
            ADDR_SSTATUS:     sw_csr_rdata_r = w_sstatus;
            ADDR_SIE:         sw_csr_rdata_r = r_sie;
            ADDR_STVEC:       sw_csr_rdata_r = r_stvec;
            ADDR_SCOUNTEREN:  sw_csr_rdata_r = r_scounteren;
            ADDR_SSCRATCH:    sw_csr_rdata_r = r_sscratch;
            ADDR_SEPC:        sw_csr_rdata_r = r_sepc;
            ADDR_SCAUSE:      sw_csr_rdata_r = r_scause;
            ADDR_STVAL:       sw_csr_rdata_r = r_stval;
            // BUG-FIX: Expose sip[5] (STIP) in addition to sip[1] (SSIP).
            // Per RISC-V spec, sip read should show both SSIP and STIP bits.
            // BUG-CSR-3 FIX: sip[9] (SEIP) must include hardware ext_seip from PLIC,
            // not just software r_sip[9]. Without this, S-mode reads sip and sees
            // SEIP=0 even when PLIC has a pending interrupt for S-mode context.
            ADDR_SIP:         sw_csr_rdata_r = w_sip;
            ADDR_SATP:        sw_csr_rdata_r = r_satp;

            ADDR_MSTATUS:     sw_csr_rdata_r = {sd_bit, r_mstatus[30:0]};
            ADDR_MISA:        sw_csr_rdata_r = 32'h40141129;  // RV32AIMFDSU (bit 0 = A, bit 3 = D extension)
            ADDR_MEDELEG:     sw_csr_rdata_r = r_medeleg;
            ADDR_MIDELEG:     sw_csr_rdata_r = r_mideleg;
            ADDR_MIE:         sw_csr_rdata_r = r_mie;
            ADDR_MTVEC:       sw_csr_rdata_r = r_mtvec;
            ADDR_MCOUNTEREN:  sw_csr_rdata_r = r_mcounteren;
            ADDR_MSTATUSH:    sw_csr_rdata_r = 32'b0;
            ADDR_MSCRATCH:    sw_csr_rdata_r = r_mscratch;
            ADDR_MEPC:        sw_csr_rdata_r = r_mepc;
            ADDR_MCAUSE:      sw_csr_rdata_r = r_mcause;
            ADDR_MTVAL:       sw_csr_rdata_r = r_mtval;
            ADDR_MIP:         sw_csr_rdata_r = r_mip;
            ADDR_MCYCLE:      sw_csr_rdata_r = r_mcycle[31:0];
            ADDR_MINSTRET:    sw_csr_rdata_r = r_minstret[31:0];
            ADDR_MCYCLEH:     sw_csr_rdata_r = r_mcycle[63:32];
            ADDR_MINSTRETH:   sw_csr_rdata_r = r_minstret[63:32];
            // U-mode counter aliases (read-only shadows)
            ADDR_CYCLE:       sw_csr_rdata_r = r_mcycle[31:0];
            ADDR_TIME:        sw_csr_rdata_r = ext_mtime[31:0];
            ADDR_INSTRET:     sw_csr_rdata_r = r_minstret[31:0];
            ADDR_CYCLEH:      sw_csr_rdata_r = r_mcycle[63:32];
            ADDR_TIMEH:       sw_csr_rdata_r = ext_mtime[63:32];
            ADDR_INSTRETH:   sw_csr_rdata_r = r_minstret[63:32];
            ADDR_MVENDORID:   sw_csr_rdata_r = 32'b0;
            ADDR_MARCHID:     sw_csr_rdata_r = 32'b0;
            ADDR_MIMPID:      sw_csr_rdata_r = 32'b0;
            ADDR_MHARTID:     sw_csr_rdata_r = 32'b0;
            ADDR_MCONFIGPTR:  sw_csr_rdata_r = 32'b0;
            // PMP config registers
            ADDR_PMPCFG0:     sw_csr_rdata_r = r_pmpcfg0;
            ADDR_PMPCFG1:     sw_csr_rdata_r = r_pmpcfg1;
            ADDR_PMPCFG2:     sw_csr_rdata_r = r_pmpcfg2;
            ADDR_PMPCFG3:     sw_csr_rdata_r = r_pmpcfg3;
            // PMP address registers
            ADDR_PMPADDR0:    sw_csr_rdata_r = r_pmpaddr0;
            ADDR_PMPADDR1:    sw_csr_rdata_r = r_pmpaddr1;
            ADDR_PMPADDR2:    sw_csr_rdata_r = r_pmpaddr2;
            ADDR_PMPADDR3:    sw_csr_rdata_r = r_pmpaddr3;
            ADDR_PMPADDR4:    sw_csr_rdata_r = r_pmpaddr4;
            ADDR_PMPADDR5:    sw_csr_rdata_r = r_pmpaddr5;
            ADDR_PMPADDR6:    sw_csr_rdata_r = r_pmpaddr6;
            ADDR_PMPADDR7:    sw_csr_rdata_r = r_pmpaddr7;
            ADDR_PMPADDR8:    sw_csr_rdata_r = r_pmpaddr8;
            ADDR_PMPADDR9:    sw_csr_rdata_r = r_pmpaddr9;
            ADDR_PMPADDR10:   sw_csr_rdata_r = r_pmpaddr10;
            ADDR_PMPADDR11:   sw_csr_rdata_r = r_pmpaddr11;
            ADDR_PMPADDR12:   sw_csr_rdata_r = r_pmpaddr12;
            ADDR_PMPADDR13:   sw_csr_rdata_r = r_pmpaddr13;
            ADDR_PMPADDR14:   sw_csr_rdata_r = r_pmpaddr14;
            ADDR_PMPADDR15:   sw_csr_rdata_r = r_pmpaddr15;
            default:          sw_csr_rdata_r = 32'b0;
        endcase
    end
    assign sw_csr_rdata = sw_csr_rdata_r;

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
    assign csr_sip       = w_sip;
    assign csr_satp      = r_satp;
    assign csr_mcounteren= r_mcounteren;
    assign csr_scounteren= r_scounteren;

    assign csr_fflags    = r_fflags;
    assign csr_frm       = r_frm;

    // PMP config outputs
    assign csr_pmpcfg0   = r_pmpcfg0;
    assign csr_pmpcfg1   = r_pmpcfg1;
    assign csr_pmpcfg2   = r_pmpcfg2;
    assign csr_pmpcfg3   = r_pmpcfg3;
    assign csr_pmpaddr0  = r_pmpaddr0;
    assign csr_pmpaddr1  = r_pmpaddr1;
    assign csr_pmpaddr2  = r_pmpaddr2;
    assign csr_pmpaddr3  = r_pmpaddr3;
    assign csr_pmpaddr4  = r_pmpaddr4;
    assign csr_pmpaddr5  = r_pmpaddr5;
    assign csr_pmpaddr6  = r_pmpaddr6;
    assign csr_pmpaddr7  = r_pmpaddr7;
    assign csr_pmpaddr8  = r_pmpaddr8;
    assign csr_pmpaddr9  = r_pmpaddr9;
    assign csr_pmpaddr10 = r_pmpaddr10;
    assign csr_pmpaddr11 = r_pmpaddr11;
    assign csr_pmpaddr12 = r_pmpaddr12;
    assign csr_pmpaddr13 = r_pmpaddr13;
    assign csr_pmpaddr14 = r_pmpaddr14;
    assign csr_pmpaddr15 = r_pmpaddr15;

endmodule
