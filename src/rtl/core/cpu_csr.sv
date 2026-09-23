`timescale 1ns / 1ps
`include "core_bus_types.svh"
`include "csr_defs.svh"

module cpu_csr(
    input              clk,
    input              resetn,

    input       [11:0] sw_csr_addr,
    input              sw_csr_wen,
    input       [31:0] sw_csr_wdata,
    output     [31:0] sw_csr_rdata,

    input              hw_csr_wen,
    input              hw_trap_is_enter,
    input       priv_mode_t hw_status_priv,
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

    output     [127:0] pmpcfg_flat,
    output     [511:0] pmpaddr_flat
);
    reg [31:0] r_mstatus;
    reg [31:0] r_mie;
    reg [31:0] r_mtvec;
    reg [31:0] r_mscratch;
    reg [31:0] r_mepc;
    reg [31:0] r_mcause;
    reg [31:0] r_mtval;
    reg [31:0] r_medeleg;
    reg [31:0] r_mideleg;
    reg [31:0] r_mcounteren;
    reg [63:0] r_mcycle;
    reg [63:0] r_minstret;

    reg [31:0] r_stvec;
    reg [31:0] r_sscratch;
    reg [31:0] r_sepc;
    reg [31:0] r_scause;
    reg [31:0] r_stval;
    reg [31:0] r_sip_sw;
    reg [31:0] r_satp;
    reg [31:0] r_scounteren;

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

    wire [31:0] w_mip;
    wire [31:0] w_sstatus;
    wire [31:0] w_sie;
    wire [31:0] w_sip;
    assign w_mip = (ext_meip ? 32'h0000_0800 : 32'b0) |
                   ((ext_seip | r_sip_sw[9]) ? 32'h0000_0200 : 32'b0) |
                   (ext_mtip ? 32'h0000_0080 : 32'b0) |
                   (r_sip_sw[5] ? 32'h0000_0020 : 32'b0) |
                   (ext_msip ? 32'h0000_0008 : 32'b0) |
                   (r_sip_sw[1] ? 32'h0000_0002 : 32'b0);
    assign w_sstatus = r_mstatus & `CSR_SSTATUS_WRITABLE_MASK;
    // sie/sip are delegated views of the machine-level interrupt CSRs, not
    // independent banks of enable and pending bits.
    assign w_sie = r_mie & r_mideleg & `CSR_MIDELEG_MASK;
    assign w_sip = w_mip & r_mideleg & `CSR_MIDELEG_MASK;

    // ── PMP WARL and lock semantics ──
    function automatic [7:0] sanitize_pmpcfg_byte(input [7:0] value);
        reg [7:0] sanitized;
        begin
            sanitized = value & 8'h9f;
            if (!sanitized[0] && sanitized[1])
                sanitized[1] = 1'b0;
            sanitize_pmpcfg_byte = sanitized;
        end
    endfunction

    function automatic [31:0] merge_pmpcfg(
        input [31:0] old_value,
        input [31:0] write_value
    );
        integer byte_index;
        begin
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
                merge_pmpcfg[byte_index*8 +: 8] =
                    old_value[byte_index*8 + 7] ? old_value[byte_index*8 +: 8] :
                    sanitize_pmpcfg_byte(write_value[byte_index*8 +: 8]);
            end
        end
    endfunction

    wire [15:0] pmpaddr_locked;
    genvar pmp_lock_index;
    generate
        for (pmp_lock_index = 0; pmp_lock_index < 15;
             pmp_lock_index = pmp_lock_index + 1) begin : gen_pmpaddr_lock
            assign pmpaddr_locked[pmp_lock_index] =
                pmpcfg_flat[pmp_lock_index*8 + 7] ||
                (pmpcfg_flat[(pmp_lock_index+1)*8 + 7] &&
                 (pmpcfg_flat[(pmp_lock_index+1)*8 + 3 +: 2] == 2'b01));
        end
    endgenerate
    assign pmpaddr_locked[15] = pmpcfg_flat[15*8 + 7];

    function automatic [31:0] sanitize_mstatus(input [31:0] value);
        reg [31:0] sanitized;
        begin
            sanitized = value & `CSR_MSTATUS_WRITABLE_MASK;
            if (value[12:11] == 2'b10)
                sanitized[12:11] = PRIV_U;
            sanitize_mstatus = sanitized;
        end
    endfunction

    wire [31:0] mstatus_wmask = sanitize_mstatus(sw_csr_wdata);

    wire [31:0] mie_wmask;
    assign mie_wmask = sw_csr_wdata & `CSR_MIE_MASK;

    wire [31:0] mtvec_wmask;
    assign mtvec_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] mepc_wmask;
    assign mepc_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] medeleg_wmask;
    // S-mode ecall (cause 9) must not be delegatable. Linux issues SBI calls
    // via ecall from S-mode, which must trap to M-mode/OpenSBI rather than
    // looping back into the S-mode trap handler.
    assign medeleg_wmask = sw_csr_wdata & `CSR_MEDELEG_MASK;

    wire [31:0] mideleg_wmask;
    assign mideleg_wmask = sw_csr_wdata & `CSR_MIDELEG_MASK;

    wire [31:0] stvec_wmask;
    assign stvec_wmask = {sw_csr_wdata[31:2], 2'b00};

    wire [31:0] sepc_wmask;
    assign sepc_wmask = {sw_csr_wdata[31:2], 2'b00};

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            r_mstatus   <= 32'h00001800;
            r_mie       <= 32'b0;
            r_mtvec     <= 32'b0;
            r_mscratch  <= 32'b0;
            r_mepc      <= 32'b0;
            r_mcause    <= 32'b0;
            r_mtval     <= 32'b0;
            r_medeleg   <= 32'b0;
            r_mideleg   <= 32'b0;
            r_mcounteren<= 32'b0;
            r_mcycle    <= 64'b0;
            r_minstret  <= 64'b0;
            r_stvec     <= 32'b0;
            r_sscratch  <= 32'b0;
            r_sepc      <= 32'b0;
            r_scause    <= 32'b0;
            r_stval     <= 32'b0;
            r_sip_sw    <= 32'b0;
            r_satp      <= 32'b0;
            r_scounteren<= 32'b0;
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
            if (cycle_en)
                r_mcycle <= r_mcycle + 64'd1;
            if (inst_retire)
                r_minstret <= r_minstret + 64'd1;

            if (hw_csr_wen) begin
                if (hw_status_priv == PRIV_M) begin
                    if (hw_trap_is_enter) begin
                        r_mepc    <= hw_mepc_wdata;
                        r_mcause  <= hw_mcause_wdata;
                        r_mtval   <= hw_mtval_wdata;
                    end
                    r_mstatus <= sanitize_mstatus(hw_mstatus_wdata);
                end else begin
                    if (hw_trap_is_enter) begin
                        r_sepc    <= hw_sepc_wdata;
                        r_scause  <= hw_scause_wdata;
                        r_stval   <= hw_stval_wdata;
                    end
                    r_mstatus <= sanitize_mstatus(hw_sstatus_wdata);
                end
            end else if (sw_csr_wen) begin
                case (sw_csr_addr)
                    `CSR_MSTATUS:    r_mstatus   <= mstatus_wmask;
                    `CSR_MIE:        r_mie       <= mie_wmask;
                    `CSR_MTVEC:      r_mtvec     <= mtvec_wmask;
                    `CSR_MSCRATCH:   r_mscratch  <= sw_csr_wdata;
                    `CSR_MEPC:       r_mepc      <= mepc_wmask;
                    `CSR_MCAUSE:     r_mcause    <= sw_csr_wdata;
                    `CSR_MTVAL:      r_mtval     <= sw_csr_wdata;
                    `CSR_MEDELEG:    r_medeleg   <= medeleg_wmask;
                    `CSR_MIDELEG:    r_mideleg   <= mideleg_wmask;
                    `CSR_MIP: begin
                        r_sip_sw <= sw_csr_wdata & `CSR_MIDELEG_MASK;
                    end
                    `CSR_MCOUNTEREN: r_mcounteren <= sw_csr_wdata & `CSR_COUNTEREN_MASK;
                    `CSR_MCYCLE:     r_mcycle[31:0]  <= sw_csr_wdata;
                    `CSR_MCYCLEH:    r_mcycle[63:32] <= sw_csr_wdata;
                    `CSR_MINSTRET:   r_minstret[31:0]  <= sw_csr_wdata;
                    `CSR_MINSTRETH:  r_minstret[63:32] <= sw_csr_wdata;
                    `CSR_SSTATUS:
                        r_mstatus <= (r_mstatus & ~`CSR_SSTATUS_WRITABLE_MASK) |
                                     (sw_csr_wdata & `CSR_SSTATUS_WRITABLE_MASK);
                    `CSR_SIE: begin
                        r_mie <= (r_mie & ~(r_mideleg & `CSR_MIDELEG_MASK)) |
                                 (sw_csr_wdata & r_mideleg & `CSR_MIDELEG_MASK);
                    end
                    `CSR_STVEC:      r_stvec     <= stvec_wmask;
                    `CSR_SSCRATCH:   r_sscratch  <= sw_csr_wdata;
                    `CSR_SEPC:       r_sepc      <= sepc_wmask;
                    `CSR_SCAUSE:     r_scause    <= sw_csr_wdata;
                    `CSR_STVAL:      r_stval     <= sw_csr_wdata;
                    `CSR_SIP: begin
                        r_sip_sw <= (r_sip_sw & ~(r_mideleg & `CSR_MIDELEG_MASK)) |
                                    (sw_csr_wdata & r_mideleg & `CSR_MIDELEG_MASK);
                    end
                    `CSR_SATP:       r_satp <= sw_csr_wdata[31] ? sw_csr_wdata : 32'b0;
                    `CSR_SCOUNTEREN: r_scounteren <= sw_csr_wdata & `CSR_COUNTEREN_MASK;
                    `CSR_PMPCFG0: r_pmpcfg0 <= merge_pmpcfg(r_pmpcfg0, sw_csr_wdata);
                    `CSR_PMPCFG1: r_pmpcfg1 <= merge_pmpcfg(r_pmpcfg1, sw_csr_wdata);
                    `CSR_PMPCFG2: r_pmpcfg2 <= merge_pmpcfg(r_pmpcfg2, sw_csr_wdata);
                    `CSR_PMPCFG3: r_pmpcfg3 <= merge_pmpcfg(r_pmpcfg3, sw_csr_wdata);
                    `CSR_PMPADDR0:  if (!pmpaddr_locked[0])  r_pmpaddr0  <= sw_csr_wdata;
                    `CSR_PMPADDR1:  if (!pmpaddr_locked[1])  r_pmpaddr1  <= sw_csr_wdata;
                    `CSR_PMPADDR2:  if (!pmpaddr_locked[2])  r_pmpaddr2  <= sw_csr_wdata;
                    `CSR_PMPADDR3:  if (!pmpaddr_locked[3])  r_pmpaddr3  <= sw_csr_wdata;
                    `CSR_PMPADDR4:  if (!pmpaddr_locked[4])  r_pmpaddr4  <= sw_csr_wdata;
                    `CSR_PMPADDR5:  if (!pmpaddr_locked[5])  r_pmpaddr5  <= sw_csr_wdata;
                    `CSR_PMPADDR6:  if (!pmpaddr_locked[6])  r_pmpaddr6  <= sw_csr_wdata;
                    `CSR_PMPADDR7:  if (!pmpaddr_locked[7])  r_pmpaddr7  <= sw_csr_wdata;
                    `CSR_PMPADDR8:  if (!pmpaddr_locked[8])  r_pmpaddr8  <= sw_csr_wdata;
                    `CSR_PMPADDR9:  if (!pmpaddr_locked[9])  r_pmpaddr9  <= sw_csr_wdata;
                    `CSR_PMPADDR10: if (!pmpaddr_locked[10]) r_pmpaddr10 <= sw_csr_wdata;
                    `CSR_PMPADDR11: if (!pmpaddr_locked[11]) r_pmpaddr11 <= sw_csr_wdata;
                    `CSR_PMPADDR12: if (!pmpaddr_locked[12]) r_pmpaddr12 <= sw_csr_wdata;
                    `CSR_PMPADDR13: if (!pmpaddr_locked[13]) r_pmpaddr13 <= sw_csr_wdata;
                    `CSR_PMPADDR14: if (!pmpaddr_locked[14]) r_pmpaddr14 <= sw_csr_wdata;
                    `CSR_PMPADDR15: if (!pmpaddr_locked[15]) r_pmpaddr15 <= sw_csr_wdata;
                    default: ;
                endcase
            end
        end
    end

    reg [31:0] sw_csr_rdata_r;
    always_comb begin
        case (sw_csr_addr)
            `CSR_SSTATUS:     sw_csr_rdata_r = w_sstatus;
            `CSR_SIE:         sw_csr_rdata_r = w_sie;
            `CSR_STVEC:       sw_csr_rdata_r = r_stvec;
            `CSR_SCOUNTEREN:  sw_csr_rdata_r = r_scounteren;
            `CSR_SSCRATCH:    sw_csr_rdata_r = r_sscratch;
            `CSR_SEPC:        sw_csr_rdata_r = r_sepc;
            `CSR_SCAUSE:      sw_csr_rdata_r = r_scause;
            `CSR_STVAL:       sw_csr_rdata_r = r_stval;
            // sip exposes the delegated software, timer, and external pending bits.
            `CSR_SIP:         sw_csr_rdata_r = w_sip;
            `CSR_SATP:        sw_csr_rdata_r = r_satp;

            `CSR_MSTATUS:     sw_csr_rdata_r = r_mstatus;
            `CSR_MISA:        sw_csr_rdata_r = 32'h40141101;  // RV32IMASU (F removed — integer core only)
            `CSR_MEDELEG:     sw_csr_rdata_r = r_medeleg;
            `CSR_MIDELEG:     sw_csr_rdata_r = r_mideleg;
            `CSR_MIE:         sw_csr_rdata_r = r_mie;
            `CSR_MTVEC:       sw_csr_rdata_r = r_mtvec;
            `CSR_MCOUNTEREN:  sw_csr_rdata_r = r_mcounteren;
            `CSR_MSTATUSH:    sw_csr_rdata_r = 32'b0;
            `CSR_MSCRATCH:    sw_csr_rdata_r = r_mscratch;
            `CSR_MEPC:        sw_csr_rdata_r = r_mepc;
            `CSR_MCAUSE:      sw_csr_rdata_r = r_mcause;
            `CSR_MTVAL:       sw_csr_rdata_r = r_mtval;
            `CSR_MIP:         sw_csr_rdata_r = w_mip;
            `CSR_MCYCLE:      sw_csr_rdata_r = r_mcycle[31:0];
            `CSR_MINSTRET:    sw_csr_rdata_r = r_minstret[31:0];
            `CSR_MCYCLEH:     sw_csr_rdata_r = r_mcycle[63:32];
            `CSR_MINSTRETH:   sw_csr_rdata_r = r_minstret[63:32];
            // U-mode counter aliases (read-only shadows)
            `CSR_CYCLE:       sw_csr_rdata_r = r_mcycle[31:0];
            `CSR_TIME:        sw_csr_rdata_r = ext_mtime[31:0];
            `CSR_INSTRET:     sw_csr_rdata_r = r_minstret[31:0];
            `CSR_CYCLEH:      sw_csr_rdata_r = r_mcycle[63:32];
            `CSR_TIMEH:       sw_csr_rdata_r = ext_mtime[63:32];
            `CSR_INSTRETH:   sw_csr_rdata_r = r_minstret[63:32];
            `CSR_MVENDORID:   sw_csr_rdata_r = 32'b0;
            `CSR_MARCHID:     sw_csr_rdata_r = 32'b0;
            `CSR_MIMPID:      sw_csr_rdata_r = 32'b0;
            `CSR_MHARTID:     sw_csr_rdata_r = 32'b0;
            `CSR_MCONFIGPTR:  sw_csr_rdata_r = 32'b0;
            // PMP config registers
            `CSR_PMPCFG0:     sw_csr_rdata_r = r_pmpcfg0;
            `CSR_PMPCFG1:     sw_csr_rdata_r = r_pmpcfg1;
            `CSR_PMPCFG2:     sw_csr_rdata_r = r_pmpcfg2;
            `CSR_PMPCFG3:     sw_csr_rdata_r = r_pmpcfg3;
            // PMP address registers
            `CSR_PMPADDR0:    sw_csr_rdata_r = r_pmpaddr0;
            `CSR_PMPADDR1:    sw_csr_rdata_r = r_pmpaddr1;
            `CSR_PMPADDR2:    sw_csr_rdata_r = r_pmpaddr2;
            `CSR_PMPADDR3:    sw_csr_rdata_r = r_pmpaddr3;
            `CSR_PMPADDR4:    sw_csr_rdata_r = r_pmpaddr4;
            `CSR_PMPADDR5:    sw_csr_rdata_r = r_pmpaddr5;
            `CSR_PMPADDR6:    sw_csr_rdata_r = r_pmpaddr6;
            `CSR_PMPADDR7:    sw_csr_rdata_r = r_pmpaddr7;
            `CSR_PMPADDR8:    sw_csr_rdata_r = r_pmpaddr8;
            `CSR_PMPADDR9:    sw_csr_rdata_r = r_pmpaddr9;
            `CSR_PMPADDR10:   sw_csr_rdata_r = r_pmpaddr10;
            `CSR_PMPADDR11:   sw_csr_rdata_r = r_pmpaddr11;
            `CSR_PMPADDR12:   sw_csr_rdata_r = r_pmpaddr12;
            `CSR_PMPADDR13:   sw_csr_rdata_r = r_pmpaddr13;
            `CSR_PMPADDR14:   sw_csr_rdata_r = r_pmpaddr14;
            `CSR_PMPADDR15:   sw_csr_rdata_r = r_pmpaddr15;
            default:          sw_csr_rdata_r = 32'b0;
        endcase
    end
    assign sw_csr_rdata = sw_csr_rdata_r;

    assign csr_mstatus   = r_mstatus;
    assign csr_mie       = r_mie;
    assign csr_mtvec     = r_mtvec;
    assign csr_mscratch  = r_mscratch;
    assign csr_mepc      = r_mepc;
    assign csr_mcause    = r_mcause;
    assign csr_mtval     = r_mtval;
    assign csr_mip       = w_mip;
    assign csr_medeleg   = r_medeleg;
    assign csr_mideleg   = r_mideleg;
    assign csr_sstatus   = w_sstatus;
    assign csr_sie       = w_sie;
    assign csr_stvec     = r_stvec;
    assign csr_sscratch  = r_sscratch;
    assign csr_sepc      = r_sepc;
    assign csr_scause    = r_scause;
    assign csr_stval     = r_stval;
    assign csr_sip       = w_sip;
    assign csr_satp      = r_satp;
    assign csr_mcounteren= r_mcounteren;
    assign csr_scounteren= r_scounteren;

    assign pmpcfg_flat = {r_pmpcfg3, r_pmpcfg2, r_pmpcfg1, r_pmpcfg0};
    assign pmpaddr_flat = {r_pmpaddr15, r_pmpaddr14, r_pmpaddr13, r_pmpaddr12,
                           r_pmpaddr11, r_pmpaddr10, r_pmpaddr9,  r_pmpaddr8,
                           r_pmpaddr7,  r_pmpaddr6,  r_pmpaddr5,  r_pmpaddr4,
                           r_pmpaddr3,  r_pmpaddr2,  r_pmpaddr1,  r_pmpaddr0};

endmodule
