// =============================================================================
// Implemented CSR addresses and fixed architectural masks
// =============================================================================

`ifndef CSR_DEFS_SVH
`define CSR_DEFS_SVH

`define CSR_SSTATUS       12'h100
`define CSR_SIE           12'h104
`define CSR_STVEC         12'h105
`define CSR_SCOUNTEREN    12'h106
`define CSR_SSCRATCH      12'h140
`define CSR_SEPC          12'h141
`define CSR_SCAUSE        12'h142
`define CSR_STVAL         12'h143
`define CSR_SIP           12'h144
`define CSR_SATP          12'h180

`define CSR_MSTATUS       12'h300
`define CSR_MISA          12'h301
`define CSR_MEDELEG       12'h302
`define CSR_MIDELEG       12'h303
`define CSR_MIE           12'h304
`define CSR_MTVEC         12'h305
`define CSR_MCOUNTEREN    12'h306
`define CSR_MSTATUSH      12'h310
`define CSR_MSCRATCH      12'h340
`define CSR_MEPC          12'h341
`define CSR_MCAUSE        12'h342
`define CSR_MTVAL         12'h343
`define CSR_MIP           12'h344

`define CSR_PMPCFG0       12'h3A0
`define CSR_PMPCFG1       12'h3A1
`define CSR_PMPCFG2       12'h3A2
`define CSR_PMPCFG3       12'h3A3
`define CSR_PMPADDR0      12'h3B0
`define CSR_PMPADDR1      12'h3B1
`define CSR_PMPADDR2      12'h3B2
`define CSR_PMPADDR3      12'h3B3
`define CSR_PMPADDR4      12'h3B4
`define CSR_PMPADDR5      12'h3B5
`define CSR_PMPADDR6      12'h3B6
`define CSR_PMPADDR7      12'h3B7
`define CSR_PMPADDR8      12'h3B8
`define CSR_PMPADDR9      12'h3B9
`define CSR_PMPADDR10     12'h3BA
`define CSR_PMPADDR11     12'h3BB
`define CSR_PMPADDR12     12'h3BC
`define CSR_PMPADDR13     12'h3BD
`define CSR_PMPADDR14     12'h3BE
`define CSR_PMPADDR15     12'h3BF

`define CSR_MCYCLE        12'hB00
`define CSR_MINSTRET      12'hB02
`define CSR_MCYCLEH       12'hB80
`define CSR_MINSTRETH     12'hB82

`define CSR_CYCLE         12'hC00
`define CSR_TIME          12'hC01
`define CSR_INSTRET       12'hC02
`define CSR_CYCLEH        12'hC80
`define CSR_TIMEH         12'hC81
`define CSR_INSTRETH      12'hC82

`define CSR_MVENDORID     12'hF11
`define CSR_MARCHID       12'hF12
`define CSR_MIMPID        12'hF13
`define CSR_MHARTID       12'hF14
`define CSR_MCONFIGPTR    12'hF15

`define CSR_MSTATUS_WRITABLE_MASK 32'h007E_19AA
`define CSR_SSTATUS_WRITABLE_MASK 32'h000C_0122
`define CSR_MIE_MASK              32'h0000_0AAA
`define CSR_MIDELEG_MASK          32'h0000_0222
`define CSR_MEDELEG_MASK          32'h0000_B1FF
`define CSR_COUNTEREN_MASK        32'h0000_0007

`endif // CSR_DEFS_SVH
