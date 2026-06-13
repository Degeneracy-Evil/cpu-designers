`ifndef APB_DEF_SVH
`define APB_DEF_SVH

`define APB_ADDR_WIDTH 32
`define APB_DATA_WIDTH 32
`define APB_STRB_WIDTH 4
`define APB_PROT_WIDTH 3

`define APB_STATE_IDLE   2'b00
`define APB_STATE_SETUP  2'b01
`define APB_STATE_ACCESS 2'b10

// -----------------------------------------------------------------------------
// Protection Attributes (PPROT) — AMBA APB4 Spec (IHI0016)
// -----------------------------------------------------------------------------
// [0] 0=Unprivileged, 1=Privileged  (opposite polarity to AXI4 AxPROT[0])
// [1] 0=Secure, 1=Non-secure
// [2] 0=Data, 1=Instruction
`define APB_PROT_DATA_PRIV_SECURE   3'b001  // Data, Privileged, Secure
`define APB_PROT_DATA_PRIV_NSECURE  3'b011  // Data, Privileged, Non-secure
`define APB_PROT_DATA_UPRIV_SECURE  3'b000  // Data, Unprivileged, Secure
`define APB_PROT_INST_PRIV_SECURE   3'b101  // Instruction, Privileged, Secure
`define APB_PROT_INST_PRIV_NSECURE  3'b111  // Instruction, Privileged, Non-secure

`endif // APB_DEF_SVH
