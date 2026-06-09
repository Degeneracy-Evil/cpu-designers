// =============================================================================
// AXI4 Constants — 替代 ahb_def.svh
// =============================================================================
// 基于 AMBA AXI4 Protocol Spec (IHI0022H)
// 适用于 AXI4 和 AXI4-Lite 接口

#ifndef AXI4_DEF_SVH
#define AXI4_DEF_SVH

// -----------------------------------------------------------------------------
// Response (BRESP / RRESP)
// -----------------------------------------------------------------------------
localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;  // Normal success
localparam logic [1:0] AXI_RESP_EXOKAY = 2'b01;  // Exclusive access OK
localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;  // Subordinate error
localparam logic [1:0] AXI_RESP_DECERR = 2'b11;  // Decode error (no subordinate)

// -----------------------------------------------------------------------------
// Burst Type (AWBURST / ARBURST)
// -----------------------------------------------------------------------------
localparam logic [1:0] AXI_BURST_FIXED = 2'b00;  // Same address each beat (FIFO)
localparam logic [1:0] AXI_BURST_INCR  = 2'b01;  // Address increments by size
localparam logic [1:0] AXI_BURST_WRAP  = 2'b10;  // Wrapping at boundary
// 2'b11 = RESERVED

// -----------------------------------------------------------------------------
// Transfer Size (AWSIZE / ARSIZE) — bytes per beat = 2^SIZE
// -----------------------------------------------------------------------------
localparam logic [2:0] AXI_SIZE_1B  = 3'b000;  // 1 byte
localparam logic [2:0] AXI_SIZE_2B  = 3'b001;  // 2 bytes (halfword)
localparam logic [2:0] AXI_SIZE_4B  = 3'b010;  // 4 bytes (word)
localparam logic [2:0] AXI_SIZE_8B  = 3'b011;  // 8 bytes (doubleword)
localparam logic [2:0] AXI_SIZE_16B = 3'b100;  // 16 bytes
localparam logic [2:0] AXI_SIZE_32B = 3'b101;  // 32 bytes
localparam logic [2:0] AXI_SIZE_64B = 3'b110;  // 64 bytes
localparam logic [2:0] AXI_SIZE_128B = 3'b111; // 128 bytes

// -----------------------------------------------------------------------------
// Cache Attributes (AWCACHE / ARCACHE)
// -----------------------------------------------------------------------------
// Write: [0]Bufferable [1]Modifiable [2]OtherAllocate [3]Allocate
// Read:  [0]Bufferable [1]Modifiable [2]Allocate [3]OtherAllocate
localparam logic [3:0] AXI_CACHE_DEV_NONBUF    = 4'b0000; // Device Non-bufferable
localparam logic [3:0] AXI_CACHE_DEV_BUF       = 4'b0001; // Device Bufferable
localparam logic [3:0] AXI_CACHE_NORM_NONCACHE = 4'b0010; // Normal Non-cacheable Non-bufferable
localparam logic [3:0] AXI_CACHE_NORM_BUF      = 4'b0011; // Normal Non-cacheable Bufferable
localparam logic [3:0] AXI_CACHE_WT_NO_ALLOC   = 4'b1010; // Write-Through, No Allocate
localparam logic [3:0] AXI_CACHE_WB_NO_ALLOC   = 4'b0111; // Write-Back, No Allocate (W) / 4'b1011 (R)
localparam logic [3:0] AXI_CACHE_WT_R_ALLOC    = 4'b1110; // Write-Through, Read Allocate
localparam logic [3:0] AXI_CACHE_WB_RW_ALLOC   = 4'b1111; // Write-Back, Read+Write Allocate

// -----------------------------------------------------------------------------
// Protection Attributes (AWPROT / ARPROT)
// -----------------------------------------------------------------------------
// [0] 0=Privileged, 1=Unprivileged
// [1] 0=Secure, 1=Non-secure
// [2] 0=Data, 1=Instruction
localparam logic [2:0] AXI_PROT_DATA_PRIV_SECURE   = 3'b000; // Data, Privileged, Secure
localparam logic [2:0] AXI_PROT_DATA_PRIV_NSECURE  = 3'b010; // Data, Privileged, Non-secure
localparam logic [2:0] AXI_PROT_DATA_UPRIV_SECURE  = 3'b001; // Data, Unprivileged, Secure
localparam logic [2:0] AXI_PROT_INST_PRIV_SECURE   = 3'b100; // Instruction, Privileged, Secure
localparam logic [2:0] AXI_PROT_INST_PRIV_NSECURE  = 3'b110; // Instruction, Privileged, Non-secure

// -----------------------------------------------------------------------------
// Lock (AWLOCK / ARLOCK) — 1-bit in AXI4
// -----------------------------------------------------------------------------
localparam logic AXI_LOCK_NORMAL    = 1'b0;  // Normal access
localparam logic AXI_LOCK_EXCLUSIVE = 1'b1;  // Exclusive access

// -----------------------------------------------------------------------------
// Region (AWREGION / ARREGION) — 4-bit, typically 0
// -----------------------------------------------------------------------------
localparam logic [3:0] AXI_REGION_DEFAULT = 4'b0000;

// -----------------------------------------------------------------------------
// QoS (AWQOS / ARQOS) — 4-bit, higher = higher priority, typically 0
// -----------------------------------------------------------------------------
localparam logic [3:0] AXI_QOS_DEFAULT = 4'b0000;

// -----------------------------------------------------------------------------
// AXI4-Lite Fixed Values (driven as constants when adapting from AXI4)
// -----------------------------------------------------------------------------
localparam logic [7:0] AXI4LITE_LEN   = 8'h00;  // Always 1 transfer
localparam logic [2:0] AXI4LITE_SIZE  = 3'b010;  // Always 4 bytes (32-bit)
localparam logic [1:0] AXI4LITE_BURST = 2'b01;   // Always INCR
localparam logic       AXI4LITE_LOCK  = 1'b0;    // No exclusive
localparam logic [3:0] AXI4LITE_CACHE = 4'b0000; // Device Non-bufferable
localparam logic       AXI4LITE_WLAST = 1'b1;    // Always last (single beat)
localparam logic       AXI4LITE_RLAST = 1'b1;    // Always last (single beat)

// -----------------------------------------------------------------------------
// Bus Width Constants (project-specific)
// -----------------------------------------------------------------------------
localparam int AXI_ADDR_WIDTH = 32;
localparam int AXI_DATA_WIDTH = 32;
localparam int AXI_STRB_WIDTH = 4;   // DATA_WIDTH / 8
localparam int AXI_ID_WIDTH   = 4;   // Match chiplab core_top
localparam int AXI_LEN_WIDTH  = 8;   // AXI4: 8-bit (vs AXI3: 4-bit)

// MIG-specific
localparam int MIG_AXI_ADDR_WIDTH = 27;  // MIG uses 27-bit address
localparam int MIG_AXI_ID_WIDTH   = 8;   // MIG uses 8-bit ID

#endif // AXI4_DEF_SVH
