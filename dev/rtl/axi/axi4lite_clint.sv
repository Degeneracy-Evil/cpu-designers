`timescale 1ns / 1ps

`include "axi4_def.svh"

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
    output wire [63:0]  o_mtime
);

    // =========================================================================
    // AXI4-Lite Write FSM
    // =========================================================================
    // WR_IDLE:  ready to accept AW (awready=1)
    // WR_DATA:  AW latched, ready to accept W (wready=1)
    // WR_RESP:  W consumed, driving B response (bvalid=1)
    localparam WR_IDLE = 2'd0;
    localparam WR_DATA = 2'd1;
    localparam WR_RESP = 2'd2;

    reg [1:0]  wr_state;
    reg [31:0] wr_addr;

    assign s_axi_awready = (wr_state == WR_IDLE);
    assign s_axi_wready  = (wr_state == WR_DATA);

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            wr_state <= WR_IDLE;
            wr_addr  <= 32'd0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (s_axi_awvalid) begin
                        wr_addr  <= s_axi_awaddr;
                        wr_state <= WR_DATA;
                    end
                end
                WR_DATA: begin
                    if (s_axi_wvalid) begin
                        wr_state <= WR_RESP;
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

    // Write fires when W channel handshake completes
    wire wr_fire = (wr_state == WR_DATA) && s_axi_wvalid;

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
    // Address decode (identical to AHB version, using latched addresses)
    // =========================================================================
    localparam ADDR_MTIMECMP_LO = 4'h0;
    localparam ADDR_MTIMECMP_HI = 4'h4;
    localparam ADDR_MTIME_LO    = 4'h8;
    localparam ADDR_MTIME_HI    = 4'hC;
    localparam ADDR_MSIP        = 4'h10;

    // Write path address decode
    wire wr_addr_cmplo  = (wr_addr[3:0] == ADDR_MTIMECMP_LO);
    wire wr_addr_cmphi  = (wr_addr[3:0] == ADDR_MTIMECMP_HI);
    wire wr_addr_timelo = (wr_addr[3:0] == ADDR_MTIME_LO);
    wire wr_addr_timehi = (wr_addr[3:0] == ADDR_MTIME_HI);
    wire wr_addr_msip   = (wr_addr[3:0] == ADDR_MSIP);

    // Read path address decode
    wire rd_addr_cmplo  = (rd_addr[3:0] == ADDR_MTIMECMP_LO);
    wire rd_addr_cmphi  = (rd_addr[3:0] == ADDR_MTIMECMP_HI);
    wire rd_addr_timelo = (rd_addr[3:0] == ADDR_MTIME_LO);
    wire rd_addr_timehi = (rd_addr[3:0] == ADDR_MTIME_HI);
    wire rd_addr_msip   = (rd_addr[3:0] == ADDR_MSIP);

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

    // BUG-FIX: 当软件写入 mtime 时，暂停自增一周期，避免写入值被自增覆盖
    wire mtime_we = wr_fire && (wr_addr_timelo || wr_addr_timehi);

    // =========================================================================
    // WSTRB-aware write data: only update bytes where WSTRB[i]=1
    // For AXI4-Lite, WSTRB indicates which byte lanes of WDATA are valid.
    // Bytes with WSTRB[i]=0 retain their current register value.
    // =========================================================================
    wire [31:0] wdata_cmplo_masked = {(s_axi_wstrb[3] ? s_axi_wdata[31:24] : r_mtimecmp_lo[31:24]),
                                       (s_axi_wstrb[2] ? s_axi_wdata[23:16] : r_mtimecmp_lo[23:16]),
                                       (s_axi_wstrb[1] ? s_axi_wdata[15:8]  : r_mtimecmp_lo[15:8]),
                                       (s_axi_wstrb[0] ? s_axi_wdata[7:0]   : r_mtimecmp_lo[7:0])};

    wire [31:0] wdata_cmphi_masked = {(s_axi_wstrb[3] ? s_axi_wdata[31:24] : r_mtimecmp_hi[31:24]),
                                       (s_axi_wstrb[2] ? s_axi_wdata[23:16] : r_mtimecmp_hi[23:16]),
                                       (s_axi_wstrb[1] ? s_axi_wdata[15:8]  : r_mtimecmp_hi[15:8]),
                                       (s_axi_wstrb[0] ? s_axi_wdata[7:0]   : r_mtimecmp_hi[7:0])};

    wire [31:0] wdata_timelo_masked = {(s_axi_wstrb[3] ? s_axi_wdata[31:24] : r_mtime[31:24]),
                                        (s_axi_wstrb[2] ? s_axi_wdata[23:16] : r_mtime[23:16]),
                                        (s_axi_wstrb[1] ? s_axi_wdata[15:8]  : r_mtime[15:8]),
                                        (s_axi_wstrb[0] ? s_axi_wdata[7:0]   : r_mtime[7:0])};

    wire [31:0] wdata_timehi_masked = {(s_axi_wstrb[3] ? s_axi_wdata[31:24] : r_mtime[63:56]),
                                        (s_axi_wstrb[2] ? s_axi_wdata[23:16] : r_mtime[55:48]),
                                        (s_axi_wstrb[1] ? s_axi_wdata[15:8]  : r_mtime[47:40]),
                                        (s_axi_wstrb[0] ? s_axi_wdata[7:0]   : r_mtime[39:32])};

    // =========================================================================
    // Register update logic (adapted from AHB version, WSTRB-aware)
    // =========================================================================
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            r_mtimecmp_lo <= 32'd0;
            r_mtimecmp_hi <= 32'd0;
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
                r_msip <= s_axi_wstrb[0] ? s_axi_wdata[0] : r_msip;
        end
    end

    // =========================================================================
    // Read data mux (uses latched rd_addr)
    // =========================================================================
    always_comb begin
        s_axi_rdata = 32'd0;
        if (rd_addr_cmplo)       s_axi_rdata = r_mtimecmp_lo;
        else if (rd_addr_cmphi)  s_axi_rdata = r_mtimecmp_hi;
        else if (rd_addr_timelo) s_axi_rdata = r_mtime[31:0];
        else if (rd_addr_timehi) s_axi_rdata = r_mtime[63:32];
        else if (rd_addr_msip)   s_axi_rdata = {31'b0, r_msip};
    end

endmodule
