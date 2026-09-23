`timescale 1ns / 1ps
`include "core_bus_types.svh"
`include "csr_defs.svh"

module csr_meta(
    input  [11:0] addr,
    output reg    implemented,
    output priv_mode_t min_priv,
    output reg    read_only,
    output reg    is_counter_alias,
    output reg [1:0] counter_index
);
    priv_mode_t min_priv_r;
    assign min_priv = min_priv_r;

    always_comb begin
        implemented = 1'b1;
        min_priv_r = PRIV_M;
        read_only = 1'b0;
        is_counter_alias = 1'b0;
        counter_index = 2'd0;

        case (addr)
            `CSR_SSTATUS, `CSR_SIE, `CSR_STVEC, `CSR_SCOUNTEREN,
            `CSR_SSCRATCH, `CSR_SEPC, `CSR_SCAUSE, `CSR_STVAL,
            `CSR_SIP, `CSR_SATP: min_priv_r = PRIV_S;

            `CSR_MSTATUS, `CSR_MEDELEG, `CSR_MIDELEG, `CSR_MIE,
            `CSR_MTVEC, `CSR_MCOUNTEREN, `CSR_MSCRATCH, `CSR_MEPC,
            `CSR_MCAUSE, `CSR_MTVAL, `CSR_MIP, `CSR_MCYCLE,
            `CSR_MINSTRET, `CSR_MCYCLEH, `CSR_MINSTRETH,
            `CSR_PMPCFG0, `CSR_PMPCFG1, `CSR_PMPCFG2, `CSR_PMPCFG3,
            `CSR_PMPADDR0, `CSR_PMPADDR1, `CSR_PMPADDR2, `CSR_PMPADDR3,
            `CSR_PMPADDR4, `CSR_PMPADDR5, `CSR_PMPADDR6, `CSR_PMPADDR7,
            `CSR_PMPADDR8, `CSR_PMPADDR9, `CSR_PMPADDR10, `CSR_PMPADDR11,
            `CSR_PMPADDR12, `CSR_PMPADDR13, `CSR_PMPADDR14, `CSR_PMPADDR15:
                min_priv_r = PRIV_M;

            `CSR_MISA, `CSR_MSTATUSH, `CSR_MVENDORID, `CSR_MARCHID,
            `CSR_MIMPID, `CSR_MHARTID, `CSR_MCONFIGPTR: begin
                min_priv_r = PRIV_M;
                read_only = 1'b1;
            end

            `CSR_CYCLE, `CSR_CYCLEH: begin
                min_priv_r = PRIV_U;
                read_only = 1'b1;
                is_counter_alias = 1'b1;
                counter_index = 2'd0;
            end
            `CSR_TIME, `CSR_TIMEH: begin
                min_priv_r = PRIV_U;
                read_only = 1'b1;
                is_counter_alias = 1'b1;
                counter_index = 2'd1;
            end
            `CSR_INSTRET, `CSR_INSTRETH: begin
                min_priv_r = PRIV_U;
                read_only = 1'b1;
                is_counter_alias = 1'b1;
                counter_index = 2'd2;
            end

            default: begin
                implemented = 1'b0;
                min_priv_r = PRIV_M;
            end
        endcase
    end
endmodule
