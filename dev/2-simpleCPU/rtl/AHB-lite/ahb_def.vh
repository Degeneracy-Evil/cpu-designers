`ifndef AHB_DEF_VH
`define AHB_DEF_VH

`define AHB_ADDR_WIDTH 32
`define AHB_DATA_WIDTH 32
`define AHB_STRB_WIDTH 4

`define AHB_TRANS_IDLE   2'b00
`define AHB_TRANS_BUSY   2'b01
`define AHB_TRANS_NONSEQ 2'b10
`define AHB_TRANS_SEQ    2'b11

`define AHB_BURST_SINGLE 3'b000
`define AHB_BURST_INCR   3'b001
`define AHB_BURST_WRAP4  3'b010
`define AHB_BURST_INCR4  3'b011
`define AHB_BURST_WRAP8  3'b100
`define AHB_BURST_INCR8  3'b101
`define AHB_BURST_WRAP16 3'b110
`define AHB_BURST_INCR16 3'b111

`define AHB_SIZE_BYTE     3'b000
`define AHB_SIZE_HWORD   3'b001
`define AHB_SIZE_WORD    3'b010
`define AHB_SIZE_DWORD   3'b011
`define AHB_SIZE_4WORD   3'b100
`define AHB_SIZE_8WORD   3'b101
`define AHB_SIZE_16WORD  3'b110
`define AHB_SIZE_32WORD  3'b111

`define AHB_RESP_OKAY   1'b0
`define AHB_RESP_ERROR  1'b1

`define AHB_PROT_OPCODE     0
`define AHB_PROT_DATA       1
`define AHB_PROT_USER       0
`define AHB_PROT_PRIVILEGED 1

`endif
