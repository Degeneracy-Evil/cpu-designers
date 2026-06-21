/*------------------------------------------------------------------------------
--------------------------------------------------------------------------------
Copyright (c) 2016, Loongson Technology Corporation Limited.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this 
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, 
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

3. Neither the name of Loongson Technology Corporation Limited nor the names of 
its contributors may be used to endorse or promote products derived from this 
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL LOONGSON TECHNOLOGY CORPORATION LIMITED BE LIABLE
TO ANY PARTY FOR DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE 
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) 
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--------------------------------------------------------------------------------
------------------------------------------------------------------------------*/
// Adapted from chiplab axi_wrap_ram.v for RISC-V CPU SoC
// BRAM-based AXI4 slave simulation model with INCR burst support.
// Zero-latency by default (awready=1, wready=1, arready=1).
// ram_random_mask accepted on port but not used in initial version.

`include "soc_config.vh"

module axi_wrap_ram(
  input         aclk,
  input         aresetn,
  //ar
  input  [3 :0] axi_arid   ,
  input  [31:0] axi_araddr ,
  input  [7 :0] axi_arlen  ,
  input  [2 :0] axi_arsize ,
  input  [1 :0] axi_arburst,
  input         axi_arlock ,
  input  [3 :0] axi_arcache,
  input  [2 :0] axi_arprot ,
  input         axi_arvalid,
  output        axi_arready,
  //r
  output [3 :0] axi_rid    ,
  output [31:0] axi_rdata  ,
  output [1 :0] axi_rresp  ,
  output        axi_rlast  ,
  output        axi_rvalid ,
  input         axi_rready ,
  //aw
  input  [3 :0] axi_awid   ,
  input  [31:0] axi_awaddr ,
  input  [7 :0] axi_awlen  ,
  input  [2 :0] axi_awsize ,
  input  [1 :0] axi_awburst,
  input         axi_awlock ,
  input  [3 :0] axi_awcache,
  input  [2 :0] axi_awprot ,
  input         axi_awvalid,
  output        axi_awready,
  //w
  input  [31:0] axi_wdata  ,
  input  [3 :0] axi_wstrb  ,
  input         axi_wlast  ,
  input         axi_wvalid ,
  output        axi_wready ,
  //b
  output [3 :0] axi_bid    ,
  output [1 :0] axi_bresp  ,
  output        axi_bvalid ,
  input         axi_bready ,

  //from confreg
  input  [4 :0] ram_random_mask
);

// ===========================================================================
// BRAM memory array
// ===========================================================================
// MEM_DEPTH = 262144 => 1MB / 4bytes = 256K words
// Address bits [19:2] index into BRAM (18-bit index for 256K entries)
localparam MEM_DEPTH = 262144;
// WARNING: MEM_DEPTH=256K words = 1MB. With 128MB DDR3 address space (0x8000_0000-0x87FF_FFFF),
// only the first 1MB is accessible via BRAM. Addresses beyond 1MB wrap around.
// For full DDR3 coverage, use axi_wrap_ddr (MIG) instead.

reg [31:0] BRAM [0:MEM_DEPTH-1];

// Initialize BRAM — simulation: load prog.hex (placed by orchestrator into xsim dir)
// FPGA: synthesizer handles COE via Sram IP.
`ifdef SIMULATION
initial begin
    $readmemh("prog.hex", BRAM);
end

reg        sim_inject_rresp_pending;
reg [31:0] sim_inject_rresp_addr;
reg [1 :0] sim_inject_rresp_code;
reg        sim_inject_bresp_pending;
reg [31:0] sim_inject_bresp_addr;
reg [1 :0] sim_inject_bresp_code;

initial begin
    sim_inject_rresp_pending = 1'b0;
    sim_inject_rresp_addr    = 32'd0;
    sim_inject_rresp_code    = 2'b10;
    sim_inject_bresp_pending = 1'b0;
    sim_inject_bresp_addr    = 32'd0;
    sim_inject_bresp_code    = 2'b10;
end
`endif

// ===========================================================================
// Address remap (same as chiplab: DDR3 at 0x8000_0000)
// ===========================================================================
wire [31:0] remapped_araddr;
wire [31:0] remapped_awaddr;

`ifdef RUN_PERF_TEST
assign remapped_araddr = axi_araddr;
assign remapped_awaddr = axi_awaddr;
`else
// Address decoder in system_top ensures only 0x8xxxxxxx addresses reach this slave.
// No remapping needed — pass through directly.
assign remapped_araddr = axi_araddr;
assign remapped_awaddr = axi_awaddr;
`endif

// ===========================================================================
// Read channel (AR + R)
// ===========================================================================
// State machine for read bursts
localparam R_IDLE    = 2'd0;
localparam R_BURST   = 2'd1;

reg [1:0]  r_state;
reg [31:0] r_addr;       // current beat address (byte-aligned)
reg [7:0]  r_count;      // beats remaining in burst
reg [7:0]  r_len;        // total burst length (arlen)
reg [2:0]  r_size;       // burst size
reg [1:0]  r_burst;      // burst type
reg [3:0]  r_id;         // transaction ID
reg [17:0] r_word_addr;  // word-aligned address for BRAM indexing
reg [1 :0] r_resp;

// Computed next address for INCR burst
wire [31:0] r_next_addr;
assign r_next_addr = r_addr + (32'b1 << r_size);

// BRAM read data (combinational — zero-latency read)
wire [31:0] r_bram_data = BRAM[r_word_addr];

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        r_state     <= R_IDLE;
        r_addr      <= 32'd0;
        r_count     <= 8'd0;
        r_len       <= 8'd0;
        r_size      <= 3'd0;
        r_burst     <= 2'd0;
        r_id        <= 4'd0;
        r_word_addr <= 18'd0;
        r_resp      <= 2'b00;

    end else begin
        case (r_state)
            R_IDLE: begin
                if (axi_arvalid) begin
                    // Accept AR channel — latch burst parameters
                    r_state <= R_BURST;
                    r_addr  <= remapped_araddr;
                    r_len   <= axi_arlen;
                    r_count <= axi_arlen;  // remaining beats after first
                    r_size  <= axi_arsize;
                    r_burst <= axi_arburst;
                    r_id    <= axi_arid;
                    r_word_addr <= remapped_araddr[19:2];  // word index
`ifdef SIMULATION
                    if (sim_inject_rresp_pending && (remapped_araddr == sim_inject_rresp_addr)) begin
                        r_resp <= sim_inject_rresp_code;
                        sim_inject_rresp_pending <= 1'b0;
                    end else begin
                        r_resp <= 2'b00;
                    end
`else
                    r_resp <= 2'b00;
`endif
                    // WRAP burst assertion — this model does not implement WRAP
                    `ifdef SIMULATION
                    assert (axi_arburst != 2'b10) else
                        $error("axi_wrap_ram: WRAP burst not supported, received arburst=%b araddr=%h", axi_arburst, axi_araddr);
                    `endif
                end
            end
            R_BURST: begin
                if (axi_rready) begin
                    // Advance to next beat
                    if (r_count == 8'd0) begin
                        // Last beat sent — back to idle
                        r_state <= R_IDLE;
                    end else begin
                        r_count <= r_count - 8'd1;
                        if (r_burst == 2'b01) begin  // INCR
                            r_addr      <= r_next_addr;
                            r_word_addr <= r_next_addr[19:2];
                        end
                        // FIXED burst: address stays the same
                        // WRAP burst: not supported in this model, treat as INCR
                    end
                end
            end
            default: begin
                r_state <= R_IDLE;
            end
        endcase
    end
end

// BRAM read — combinational (zero-latency), driven by continuous assign above

// AR channel outputs
assign axi_arready = (r_state == R_IDLE);

// R channel outputs
assign axi_rvalid  = (r_state == R_BURST);
assign axi_rid     = r_id;
assign axi_rdata   = r_bram_data;
assign axi_rresp   = r_resp;
assign axi_rlast   = (r_state == R_BURST) && (r_count == 8'd0);

// ===========================================================================
// Write channel (AW + W + B)
// ===========================================================================
// State machine for write bursts
localparam W_IDLE    = 2'd0;
localparam W_DATA    = 2'd1;
localparam W_RESP    = 2'd2;

reg [1:0]  w_state;
reg [31:0] w_addr;       // current beat address
reg [7:0]  w_count;      // beats remaining
reg [2:0]  w_size;       // burst size
reg [1:0]  w_burst;      // burst type
reg [3:0]  w_id;         // transaction ID
reg [31:0] w_base_addr;  // burst base address for response injection matching
reg [1 :0] w_resp;
reg        w_drop_write;

// Computed next address for INCR burst
wire [31:0] w_next_addr;
assign w_next_addr = w_addr + (32'b1 << w_size);

// AW channel: accept immediately when in IDLE
assign axi_awready = (w_state == W_IDLE);

// W channel: accept when in DATA phase
assign axi_wready  = (w_state == W_DATA);

// B channel: valid when in RESP phase
assign axi_bvalid  = (w_state == W_RESP);
assign axi_bid     = w_id;
assign axi_bresp   = w_resp;

// BRAM write and state machine
always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        w_state <= W_IDLE;
        w_addr  <= 32'd0;
        w_count <= 8'd0;
        w_size  <= 3'd0;
        w_burst <= 2'd0;
        w_id    <= 4'd0;
        w_base_addr <= 32'd0;
        w_resp  <= 2'b00;
        w_drop_write <= 1'b0;
    end else begin
        case (w_state)
            W_IDLE: begin
                if (axi_awvalid) begin
                    // Accept AW channel — latch burst parameters
                    w_state <= W_DATA;
                    w_addr  <= remapped_awaddr;
                    w_count <= axi_awlen;
                    w_size  <= axi_awsize;
                    w_burst <= axi_awburst;
                    w_id    <= axi_awid;
                    w_base_addr <= remapped_awaddr;
`ifdef SIMULATION
                    if (sim_inject_bresp_pending && (remapped_awaddr == sim_inject_bresp_addr)) begin
                        w_resp <= sim_inject_bresp_code;
                        w_drop_write <= 1'b1;
                        sim_inject_bresp_pending <= 1'b0;
                    end else begin
                        w_resp <= 2'b00;
                        w_drop_write <= 1'b0;
                    end
`else
                    w_resp <= 2'b00;
                    w_drop_write <= 1'b0;
`endif
                    // WRAP burst assertion — this model does not implement WRAP
                    `ifdef SIMULATION
                    assert (axi_awburst != 2'b10) else
                        $error("axi_wrap_ram: WRAP burst not supported, received awburst=%b awaddr=%h", axi_awburst, axi_awaddr);
                    `endif
                end
            end
            W_DATA: begin
                if (axi_wvalid) begin
                    if (!w_drop_write) begin
                        // Injected write errors model a failed memory commit in simulation.
                        if (axi_wstrb[3]) BRAM[w_addr[19:2]][31:24] <= axi_wdata[31:24];
                        if (axi_wstrb[2]) BRAM[w_addr[19:2]][23:16] <= axi_wdata[23:16];
                        if (axi_wstrb[1]) BRAM[w_addr[19:2]][15:8]  <= axi_wdata[15:8];
                        if (axi_wstrb[0]) BRAM[w_addr[19:2]][7:0]   <= axi_wdata[7:0];
                    end


                    if (axi_wlast) begin
                        // Last beat — move to response phase
                        w_state <= W_RESP;
                    end else begin
                        // Advance address for next beat
                        if (w_burst == 2'b01) begin  // INCR
                            w_addr <= w_next_addr;
                        end
                        // FIXED burst: address stays the same
                        // WRAP burst: not supported, treat as INCR
                    end
                end
            end
            W_RESP: begin
                if (axi_bready) begin
                    // B channel handshake complete
                    w_state <= W_IDLE;
                    w_drop_write <= 1'b0;
                end
            end
            default: begin
                w_state <= W_IDLE;
            end
        endcase
    end
end

endmodule
