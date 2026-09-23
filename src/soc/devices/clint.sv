`timescale 1ns / 1ps

`include "common/bus/axi.svh"

module axi4lite_clint(
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,

    // AXI4-Lite Write Address Channel
    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // AXI4-Lite Write Response Channel
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  logic [31:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // AXI4-Lite Read Data Channel
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // Timer interrupt interface (preserved from AHB version)
    output wire         o_mtip,
    output wire         o_msip,
    output wire [63:0]  o_mtime,
    output wire [63:0]  o_mtimecmp
);

    // =========================================================================
    // AXI4-Lite Write FSM
    // =========================================================================
    // Single-outstanding AXI4-Lite slave:
    // AW and W are accepted independently, then the write side effect fires
    // exactly once when both channels for the transaction have arrived.
    localparam WR_IDLE = 1'd0;
    localparam WR_RESP = 1'd1;

    reg        wr_state;
    reg [31:0] wr_addr;
    reg [31:0] wr_wdata;
    reg [3:0]  wr_wstrb;
    reg        aw_latched;
    reg        w_latched;

    wire aw_fire = (wr_state == WR_IDLE) && !aw_latched && s_axi_awvalid;
    wire w_fire  = (wr_state == WR_IDLE) && !w_latched  && s_axi_wvalid;
    wire wr_fire = (wr_state == WR_IDLE) && ((aw_latched || aw_fire) && (w_latched || w_fire));

    wire [31:0] wr_addr_eff  = aw_latched ? wr_addr  : s_axi_awaddr;
    wire [31:0] wr_wdata_eff = w_latched  ? wr_wdata : s_axi_wdata;
    wire [3:0]  wr_wstrb_eff = w_latched  ? wr_wstrb : s_axi_wstrb;

    assign s_axi_awready = (wr_state == WR_IDLE) && !aw_latched;
    assign s_axi_wready  = (wr_state == WR_IDLE) && !w_latched;

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            wr_state   <= WR_IDLE;
            wr_addr    <= 32'd0;
            wr_wdata   <= 32'd0;
            wr_wstrb   <= 4'd0;
            aw_latched <= 1'b0;
            w_latched  <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (aw_fire)
                        wr_addr <= s_axi_awaddr;
                    if (w_fire) begin
                        wr_wdata <= s_axi_wdata;
                        wr_wstrb <= s_axi_wstrb;
                    end
                    if (wr_fire) begin
                        wr_state <= WR_RESP;
                        aw_latched <= 1'b0;
                        w_latched  <= 1'b0;
                    end else begin
                        if (aw_fire)
                            aw_latched <= 1'b1;
                        if (w_fire)
                            w_latched <= 1'b1;
                    end
                end
                WR_RESP: begin
                    if (s_axi_bready) begin
                        wr_state <= WR_IDLE;
                    end
                end
                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // B channel
    assign s_axi_bvalid = (wr_state == WR_RESP);
    assign s_axi_bresp  = `AXI_RESP_OKAY;

    // =========================================================================
    // AXI4-Lite Read FSM
    // =========================================================================
    // RD_IDLE:  ready to accept AR (arready=1)
    // RD_RESP:  AR latched, driving R response (rvalid=1)
    localparam RD_IDLE = 1'd0;
    localparam RD_RESP = 1'd1;

    reg        rd_state;
    reg [31:0] rd_addr;

    assign s_axi_arready = (rd_state == RD_IDLE);

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            rd_state <= RD_IDLE;
            rd_addr  <= 32'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (s_axi_arvalid) begin
                        rd_addr  <= s_axi_araddr;
                        rd_state <= RD_RESP;
                    end
                end
                RD_RESP: begin
                    if (s_axi_rready) begin
                        rd_state <= RD_IDLE;
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // Read fires when AR channel handshake completes
    wire rd_fire = (rd_state == RD_IDLE) && s_axi_arvalid;

    // R channel
    assign s_axi_rvalid = (rd_state == RD_RESP);
    assign s_axi_rresp  = `AXI_RESP_OKAY;

    // =========================================================================
    // Address decode — Standard SiFive CLINT layout
    // =========================================================================
    //   0x0000: msip         (32-bit, bit 0 effective)
    //   0x4000: mtimecmp_lo  (32-bit)
    //   0x4004: mtimecmp_hi  (32-bit)
    //   0xBFF8: mtime_lo     (32-bit)
    //   0xBFFC: mtime_hi     (32-bit)
    //
    // Decode uses addr[15:0] to cover the full 64KB CLINT window.
    // The system_top address decoder routes 0x0200_xxxx to this slave,
    // so addr[15:0] captures the intra-CLINT offset.
    // =========================================================================
    localparam ADDR_MSIP        = 16'h0000;
    localparam ADDR_MTIMECMP_LO = 16'h4000;
    localparam ADDR_MTIMECMP_HI = 16'h4004;
    localparam ADDR_MTIME_LO    = 16'hBFF8;
    localparam ADDR_MTIME_HI    = 16'hBFFC;

    // Write path address decode
    wire wr_addr_msip   = (wr_addr_eff[15:0] == ADDR_MSIP);
    wire wr_addr_cmplo  = (wr_addr_eff[15:0] == ADDR_MTIMECMP_LO);
    wire wr_addr_cmphi  = (wr_addr_eff[15:0] == ADDR_MTIMECMP_HI);
    wire wr_addr_timelo = (wr_addr_eff[15:0] == ADDR_MTIME_LO);
    wire wr_addr_timehi = (wr_addr_eff[15:0] == ADDR_MTIME_HI);

    // Read path address decode
    wire rd_addr_msip   = (rd_addr[15:0] == ADDR_MSIP);
    wire rd_addr_cmplo  = (rd_addr[15:0] == ADDR_MTIMECMP_LO);
    wire rd_addr_cmphi  = (rd_addr[15:0] == ADDR_MTIMECMP_HI);
    wire rd_addr_timelo = (rd_addr[15:0] == ADDR_MTIME_LO);
    wire rd_addr_timehi = (rd_addr[15:0] == ADDR_MTIME_HI);

    // =========================================================================
    // Internal registers (identical to AHB version)
    // =========================================================================
    reg [31:0] r_mtimecmp_lo;
    reg [31:0] r_mtimecmp_hi;
    reg [63:0] r_mtime;
    reg        r_msip;

    wire [63:0] mtimecmp_64;
    assign mtimecmp_64 = {r_mtimecmp_hi, r_mtimecmp_lo};

    wire mtip_raw;
    assign mtip_raw = (r_mtime >= mtimecmp_64);

    assign o_mtip = mtip_raw;
    assign o_msip = r_msip;
    assign o_mtime = r_mtime;
    assign o_mtimecmp = mtimecmp_64;

    // Software-visible contract: mtime and mtimecmp are exposed as split 32-bit
    // registers. Software must use the standard hi/lo retry sequence for reads
    // and the safe compare-update sequence when programming mtimecmp.
    //
    // Hardware guarantee preserved here: a write to either half of mtime pauses
    // the free-running increment for one cycle so the software-written value is
    // not immediately clobbered by the timer increment path.
    wire mtime_we = wr_fire && (wr_addr_timelo || wr_addr_timehi);

    // =========================================================================
    // WSTRB-aware write data: only update bytes where WSTRB[i]=1
    // For AXI4-Lite, WSTRB indicates which byte lanes of WDATA are valid.
    // Bytes with WSTRB[i]=0 retain their current register value.
    // =========================================================================
    wire [31:0] wdata_cmplo_masked = {(wr_wstrb_eff[3] ? wr_wdata_eff[31:24] : r_mtimecmp_lo[31:24]),
                                       (wr_wstrb_eff[2] ? wr_wdata_eff[23:16] : r_mtimecmp_lo[23:16]),
                                       (wr_wstrb_eff[1] ? wr_wdata_eff[15:8]  : r_mtimecmp_lo[15:8]),
                                       (wr_wstrb_eff[0] ? wr_wdata_eff[7:0]   : r_mtimecmp_lo[7:0])};

    wire [31:0] wdata_cmphi_masked = {(wr_wstrb_eff[3] ? wr_wdata_eff[31:24] : r_mtimecmp_hi[31:24]),
                                       (wr_wstrb_eff[2] ? wr_wdata_eff[23:16] : r_mtimecmp_hi[23:16]),
                                       (wr_wstrb_eff[1] ? wr_wdata_eff[15:8]  : r_mtimecmp_hi[15:8]),
                                       (wr_wstrb_eff[0] ? wr_wdata_eff[7:0]   : r_mtimecmp_hi[7:0])};

    wire [31:0] wdata_timelo_masked = {(wr_wstrb_eff[3] ? wr_wdata_eff[31:24] : r_mtime[31:24]),
                                        (wr_wstrb_eff[2] ? wr_wdata_eff[23:16] : r_mtime[23:16]),
                                        (wr_wstrb_eff[1] ? wr_wdata_eff[15:8]  : r_mtime[15:8]),
                                        (wr_wstrb_eff[0] ? wr_wdata_eff[7:0]   : r_mtime[7:0])};

    wire [31:0] wdata_timehi_masked = {(wr_wstrb_eff[3] ? wr_wdata_eff[31:24] : r_mtime[63:56]),
                                        (wr_wstrb_eff[2] ? wr_wdata_eff[23:16] : r_mtime[55:48]),
                                        (wr_wstrb_eff[1] ? wr_wdata_eff[15:8]  : r_mtime[47:40]),
                                        (wr_wstrb_eff[0] ? wr_wdata_eff[7:0]   : r_mtime[39:32])};

    // =========================================================================
    // Register update logic (adapted from AHB version, WSTRB-aware)
    // =========================================================================
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            r_mtimecmp_lo <= 32'hFFFF_FFFF;
            r_mtimecmp_hi <= 32'hFFFF_FFFF;
            r_mtime       <= 64'd0;
            r_msip        <= 1'b0;
        end else begin
            if (!mtime_we)
                r_mtime <= r_mtime + 64'd1;

            if (wr_fire && wr_addr_cmplo)
                r_mtimecmp_lo <= wdata_cmplo_masked;
            if (wr_fire && wr_addr_cmphi)
                r_mtimecmp_hi <= wdata_cmphi_masked;
            if (wr_fire && wr_addr_timelo)
                r_mtime[31:0] <= wdata_timelo_masked;
            if (wr_fire && wr_addr_timehi)
                r_mtime[63:32] <= wdata_timehi_masked;
            if (wr_fire && wr_addr_msip)
                r_msip <= wr_wstrb_eff[0] ? wr_wdata_eff[0] : r_msip;
        end
    end

    // =========================================================================
    // Read data mux (uses latched rd_addr)
    // =========================================================================
    always_comb begin
        s_axi_rdata = 32'd0;
        if (rd_addr_msip)       s_axi_rdata = {31'b0, r_msip};
        else if (rd_addr_cmplo)  s_axi_rdata = r_mtimecmp_lo;
        else if (rd_addr_cmphi)  s_axi_rdata = r_mtimecmp_hi;
        else if (rd_addr_timelo) s_axi_rdata = r_mtime[31:0];
        else if (rd_addr_timehi) s_axi_rdata = r_mtime[63:32];
    end

endmodule
