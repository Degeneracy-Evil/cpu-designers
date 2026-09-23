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
// Adapted from chiplab axi_wrap_ddr.v for RISC-V CPU SoC
// Changes from chiplab:
//   - Address remap base: 0x8000_0000 (DDR3 direct) instead of 0x0/0x1/0x7
//   - Delay expansion skipped (Phase 6) — ram_* signals pass through directly
//   - ram_random_mask left unconnected (tied 5'b0 internally)
//   - MIG module name: mig_axi_32 (same as chiplab)

`include "soc/config.svh"

module axi_wrap_ddr(
    input         aclk,
    input         aresetn,
    input         xtal_clk,
    input         button_resetn,
    input         ddr_clk_ref,
    output reg    ddr_aresetn,

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
    input  [4 :0] ram_random_mask,

    //------DDR3 interface------
    inout  [15:0] ddr3_dq,
    output [12:0] ddr3_addr,
    output [2 :0] ddr3_ba,
    output        ddr3_ras_n,
    output        ddr3_cas_n,
    output        ddr3_we_n,
    output        ddr3_odt,
    output        ddr3_reset_n,
    output        ddr3_cke,
    output [1:0]  ddr3_dm,
    inout  [1:0]  ddr3_dqs_p,
    inout  [1:0]  ddr3_dqs_n,
    output        ddr3_ck_p,
    output        ddr3_ck_n
);

// Delay expansion skipped for Phase 6.
// ram_random_mask is accepted on the port but not used internally.
// All ram_* signals pass directly through to Axi_CDC without delay logic.

//ram axi
//ar
wire [3 :0] ram_arid   ;
wire [31:0] ram_araddr ;
wire [7 :0] ram_arlen  ;
wire [2 :0] ram_arsize ;
wire [1 :0] ram_arburst;
wire        ram_arlock ;
wire [3 :0] ram_arcache;
wire [2 :0] ram_arprot ;
wire        ram_arvalid;
wire        ram_arready;
//r
wire [3 :0] ram_rid    ;
wire [31:0] ram_rdata  ;
wire [1 :0] ram_rresp  ;
wire        ram_rlast  ;
wire        ram_rvalid ;
wire        ram_rready ;
//aw
wire [3 :0] ram_awid   ;
wire [31:0] ram_awaddr ;
wire [7 :0] ram_awlen  ;
wire [2 :0] ram_awsize ;
wire [1 :0] ram_awburst;
wire        ram_awlock ;
wire [3 :0] ram_awcache;
wire [2 :0] ram_awprot ;
wire        ram_awvalid;
wire        ram_awready;
//w
wire [31:0] ram_wdata  ;
wire [3 :0] ram_wstrb  ;
wire        ram_wlast  ;
wire        ram_wvalid ;
wire        ram_wready ;
//b
wire [3 :0] ram_bid    ;
wire [1 :0] ram_bresp  ;
wire        ram_bvalid ;
wire        ram_bready ;

//ddr axi
//ar
wire [3 :0] mig_arid   ;
wire [31:0] mig_araddr ;
wire [7 :0] mig_arlen  ;
wire [2 :0] mig_arsize ;
wire [1 :0] mig_arburst;
wire        mig_arlock ;
wire [3 :0] mig_arcache;
wire [2 :0] mig_arprot ;
wire        mig_arvalid;
wire        mig_arready;
//r
wire [3 :0] mig_rid    ;
wire [31:0] mig_rdata  ;
wire [1 :0] mig_rresp  ;
wire        mig_rlast  ;
wire        mig_rvalid ;
wire        mig_rready ;
//aw
wire [3 :0] mig_awid   ;
wire [31:0] mig_awaddr ;
wire [7 :0] mig_awlen  ;
wire [2 :0] mig_awsize ;
wire [1 :0] mig_awburst;
wire        mig_awlock ;
wire [3 :0] mig_awcache;
wire [2 :0] mig_awprot ;
wire        mig_awvalid;
wire        mig_awready;
//w
wire [31:0] mig_wdata  ;
wire [3 :0] mig_wstrb  ;
wire        mig_wlast  ;
wire        mig_wvalid ;
wire        mig_wready ;
//b
wire [3 :0] mig_bid    ;
wire [1 :0] mig_bresp  ;
wire        mig_bvalid ;
wire        mig_bready ;

// The MIG is generated with an 8-bit AXI ID. The core only issues 4-bit IDs,
// so extend requests explicitly and discard the known-zero upper response bits.
wire [7 :0] mig_bid_wide;
wire [7 :0] mig_rid_wide;

assign mig_bid = mig_bid_wide[3:0];
assign mig_rid = mig_rid_wide[3:0];

wire ui_clk;
wire ui_clk_sync_rst;
wire init_calib_complete;

Axi_CDC  u_Axi_CDC (
    .axiInClk                ( aclk                 ),
    .axiInRst                ( aresetn              ),
    .axiOutClk               ( ui_clk               ),
    .axiOutRst               ( ddr_aresetn          ),

    .axiIn_awvalid           ( ram_awvalid         ),
    .axiIn_awaddr            ( ram_awaddr          ),
    .axiIn_awid              ( ram_awid            ),
    .axiIn_awlen             ( ram_awlen           ),
    .axiIn_awsize            ( ram_awsize          ),
    .axiIn_awburst           ( ram_awburst         ),
    .axiIn_awlock            ( ram_awlock          ),
    .axiIn_awcache           ( ram_awcache         ),
    .axiIn_awprot            ( ram_awprot          ),
    .axiIn_wvalid            ( ram_wvalid          ),
    .axiIn_wdata             ( ram_wdata           ),
    .axiIn_wstrb             ( ram_wstrb           ),
    .axiIn_wlast             ( ram_wlast           ),
    .axiIn_bready            ( ram_bready          ),
    .axiIn_arvalid           ( ram_arvalid         ),
    .axiIn_araddr            ( ram_araddr          ),
    .axiIn_arid              ( ram_arid            ),
    .axiIn_arlen             ( ram_arlen           ),
    .axiIn_arsize            ( ram_arsize          ),
    .axiIn_arburst           ( ram_arburst         ),
    .axiIn_arlock            ( ram_arlock          ),
    .axiIn_arcache           ( ram_arcache         ),
    .axiIn_arprot            ( ram_arprot          ),
    .axiIn_rready            ( ram_rready          ),
    .axiOut_awready          ( mig_awready         ),
    .axiOut_wready           ( mig_wready          ),
    .axiOut_bvalid           ( mig_bvalid          ),
    .axiOut_bid              ( mig_bid             ),
    .axiOut_bresp            ( mig_bresp           ),
    .axiOut_arready          ( mig_arready         ),
    .axiOut_rvalid           ( mig_rvalid          ),
    .axiOut_rdata            ( mig_rdata           ),
    .axiOut_rid              ( mig_rid             ),
    .axiOut_rresp            ( mig_rresp           ),
    .axiOut_rlast            ( mig_rlast           ),

    .axiIn_awready           ( ram_awready         ),
    .axiIn_wready            ( ram_wready          ),
    .axiIn_bvalid            ( ram_bvalid          ),
    .axiIn_bid               ( ram_bid             ),
    .axiIn_bresp             ( ram_bresp           ),
    .axiIn_arready           ( ram_arready         ),
    .axiIn_rvalid            ( ram_rvalid          ),
    .axiIn_rdata             ( ram_rdata           ),
    .axiIn_rid               ( ram_rid             ),
    .axiIn_rresp             ( ram_rresp           ),
    .axiIn_rlast             ( ram_rlast           ),
    .axiOut_awvalid          ( mig_awvalid         ),
    .axiOut_awaddr           ( mig_awaddr          ),
    .axiOut_awid             ( mig_awid            ),
    .axiOut_awlen            ( mig_awlen           ),
    .axiOut_awsize           ( mig_awsize          ),
    .axiOut_awburst          ( mig_awburst         ),
    .axiOut_awlock           ( mig_awlock          ),
    .axiOut_awcache          ( mig_awcache         ),
    .axiOut_awprot           ( mig_awprot          ),
    .axiOut_wvalid           ( mig_wvalid          ),
    .axiOut_wdata            ( mig_wdata           ),
    .axiOut_wstrb            ( mig_wstrb           ),
    .axiOut_wlast            ( mig_wlast           ),
    .axiOut_bready           ( mig_bready          ),
    .axiOut_arvalid          ( mig_arvalid         ),
    .axiOut_araddr           ( mig_araddr          ),
    .axiOut_arid             ( mig_arid            ),
    .axiOut_arlen            ( mig_arlen           ),
    .axiOut_arsize           ( mig_arsize          ),
    .axiOut_arburst          ( mig_arburst         ),
    .axiOut_arlock           ( mig_arlock          ),
    .axiOut_arcache          ( mig_arcache         ),
    .axiOut_arprot           ( mig_arprot          ),
    .axiOut_rready           ( mig_rready          )
);

// BUG-FIX: ddr_aresetn 必须有异步复位，否则上电后为 X 阻止 MIG 初始化
always_ff @(posedge ui_clk or negedge button_resetn) begin
    if (!button_resetn) begin
        ddr_aresetn <= 1'b0;
    end else begin
        ddr_aresetn <= ~ui_clk_sync_rst && init_calib_complete;
    end
end

//ddr3 controller
mig_axi_32 mig_axi (
    // Inouts
    .ddr3_dq             (ddr3_dq         ),  
    .ddr3_dqs_p          (ddr3_dqs_p      ),
    .ddr3_dqs_n          (ddr3_dqs_n      ),
    // Outputs
    .ddr3_addr           (ddr3_addr       ),  
    .ddr3_ba             (ddr3_ba         ),
    .ddr3_ras_n          (ddr3_ras_n      ),                        
    .ddr3_cas_n          (ddr3_cas_n      ),                        
    .ddr3_we_n           (ddr3_we_n       ),                          
    .ddr3_reset_n        (ddr3_reset_n    ),
    .ddr3_ck_p           (ddr3_ck_p       ),                          
    .ddr3_ck_n           (ddr3_ck_n       ),       
    .ddr3_cke            (ddr3_cke        ),                          
    .ddr3_dm             (ddr3_dm         ),
    .ddr3_odt            (ddr3_odt        ),
    
    .ui_clk              (ui_clk          ),
    .ui_clk_sync_rst     (ui_clk_sync_rst ),
 
    .sys_clk_i           (xtal_clk        ),
    .sys_rst             (button_resetn   ),                        
    .init_calib_complete (init_calib_complete),
    .device_temp         (                ),
    .clk_ref_i           (ddr_clk_ref     ),
    .mmcm_locked         (                ),
	
    .app_sr_active       (                ),
    .app_ref_ack         (                ),
    .app_zq_ack          (                ),
    .app_sr_req          (1'b0            ),
    .app_ref_req         (1'b0            ),
    .app_zq_req          (1'b0            ),
    
    .aresetn             (ddr_aresetn     ),
    .s_axi_awid          ({4'b0, mig_awid}),
    .s_axi_awaddr        (mig_awaddr[26:0]),
    .s_axi_awlen         (mig_awlen       ),
    .s_axi_awsize        (mig_awsize      ),
    .s_axi_awburst       (mig_awburst     ),
    .s_axi_awlock        (mig_awlock      ),
    .s_axi_awcache       (mig_awcache     ),
    .s_axi_awprot        (mig_awprot      ),
    .s_axi_awqos         (4'b0            ),
    .s_axi_awvalid       (mig_awvalid     ),
    .s_axi_awready       (mig_awready     ),
    .s_axi_wdata         (mig_wdata       ),
    .s_axi_wstrb         (mig_wstrb       ),
    .s_axi_wlast         (mig_wlast       ),
    .s_axi_wvalid        (mig_wvalid      ),
    .s_axi_wready        (mig_wready      ),
    .s_axi_bid           (mig_bid_wide    ),
    .s_axi_bresp         (mig_bresp       ),
    .s_axi_bvalid        (mig_bvalid      ),
    .s_axi_bready        (mig_bready      ),
    .s_axi_arid          ({4'b0, mig_arid}),
    .s_axi_araddr        (mig_araddr[26:0]),
    .s_axi_arlen         (mig_arlen       ),
    .s_axi_arsize        (mig_arsize      ),
    .s_axi_arburst       (mig_arburst     ),
    .s_axi_arlock        (mig_arlock      ),
    .s_axi_arcache       (mig_arcache     ),
    .s_axi_arprot        (mig_arprot      ),
    .s_axi_arqos         (4'b0            ),
    .s_axi_arvalid       (mig_arvalid     ),
    .s_axi_arready       (mig_arready     ),
    .s_axi_rid           (mig_rid_wide    ),
    .s_axi_rdata         (mig_rdata       ),
    .s_axi_rresp         (mig_rresp       ),
    .s_axi_rlast         (mig_rlast       ),
    .s_axi_rvalid        (mig_rvalid      ),
    .s_axi_rready        (mig_rready      )
);

//ar — direct passthrough (no delay expansion)
assign ram_arid    = axi_arid   ;
`ifdef RUN_PERF_TEST
assign ram_araddr  = axi_araddr ;
`else
// Address remap: DDR3 at 0x8000_0000, others remapped to MIG address space
assign ram_araddr  = (axi_araddr[31:28] == 4'h8) ? axi_araddr :
                      {12'b0, 4'hf, axi_araddr[31:28], axi_araddr[11:0]};
`endif
assign ram_arlen   = axi_arlen  ;
assign ram_arsize  = axi_arsize ;
assign ram_arburst = axi_arburst;
assign ram_arlock  = axi_arlock ;
assign ram_arcache = axi_arcache;
assign ram_arprot  = axi_arprot ;
assign ram_arvalid = axi_arvalid;
assign axi_arready = ram_arready;
//r
assign axi_rid    = ram_rid   ;
assign axi_rdata  = ram_rdata ;
assign axi_rresp  = ram_rresp ;
assign axi_rlast  = ram_rlast ;
assign axi_rvalid = ram_rvalid;
assign ram_rready = axi_rready;
//aw — direct passthrough (no delay expansion)
assign ram_awid    = axi_awid   ;
`ifdef RUN_PERF_TEST
assign ram_awaddr  = axi_awaddr ;
`else
// Address remap: DDR3 at 0x8000_0000, others remapped to MIG address space
assign ram_awaddr  = (axi_awaddr[31:28] == 4'h8) ? axi_awaddr :
                      {12'b0, 4'hf, axi_awaddr[31:28], axi_awaddr[11:0]};
`endif
assign ram_awlen   = axi_awlen  ;
assign ram_awsize  = axi_awsize ;
assign ram_awburst = axi_awburst;
assign ram_awlock  = axi_awlock ;
assign ram_awcache = axi_awcache;
assign ram_awprot  = axi_awprot ;
assign ram_awvalid = axi_awvalid;
assign axi_awready = ram_awready;
//w
assign ram_wdata  = axi_wdata  ;
assign ram_wstrb  = axi_wstrb  ;
assign ram_wlast  = axi_wlast  ;
assign ram_wvalid = axi_wvalid ;
assign axi_wready = ram_wready ;
//b
assign axi_bid    = ram_bid   ;
assign axi_bresp  = ram_bresp ;
assign axi_bvalid = ram_bvalid;
assign ram_bready = axi_bready;

endmodule
