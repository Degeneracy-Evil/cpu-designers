`timescale 1ns / 1ps

`include "axi4_def.svh"

module axi4lite_plic #(
    parameter NUM_SRC = 8
)(
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

    // Interrupt interface (preserved from AHB version)
    input  wire [NUM_SRC-1:0] src_irq,
    output wire               o_eip
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
    // Address decode — write path (uses latched wr_addr)
    // =========================================================================
    wire wr_addr_is_prio   = (wr_addr[23:6] == 18'd0);
    wire wr_addr_is_pend   = (wr_addr[23:14] == 10'd0) && (wr_addr[13:2] == 12'd256);
    wire wr_addr_is_enable = (wr_addr[23:14] == 10'd0) && (wr_addr[13:2] == 12'd512);
    wire wr_addr_is_thresh = (wr_addr[23:4] == {20'h20000});
    wire wr_addr_is_claim  = (wr_addr[23:4] == {20'h20001});

    // Address decode — read path (uses latched rd_addr)
    wire rd_addr_is_prio   = (rd_addr[23:6] == 18'd0);
    wire rd_addr_is_pend   = (rd_addr[23:14] == 10'd0) && (rd_addr[13:2] == 12'd256);
    wire rd_addr_is_enable = (rd_addr[23:14] == 10'd0) && (rd_addr[13:2] == 12'd512);
    wire rd_addr_is_thresh = (rd_addr[23:4] == {20'h20000});
    wire rd_addr_is_claim  = (rd_addr[23:4] == {20'h20001});

    // =========================================================================
    // Internal registers (identical to AHB version)
    // =========================================================================
    reg  [31:0] r_prio [0:NUM_SRC-1];
    reg  [31:0] r_pending;
    reg  [31:0] r_enable;
    reg  [31:0] r_threshold;
    reg  [NUM_SRC-1:0] r_gw_en;

    reg  [7:0]  r_claim_id;   // latched claim ID for rdata

    integer ii;

    // find_highest function (identical to AHB version)
    function [7:0] find_highest;
        input [31:0] pend, enbl, thresh;
        input [31:0] prio_arr [0:NUM_SRC-1];
        reg   [31:0] pmat [1:NUM_SRC-1];
        reg   [31:0] best;
        reg   [7:0]  id;
        integer      j;
        begin
            best = 32'd0;
            id   = 8'd0;
            for (j = 1; j < NUM_SRC; j = j + 1) begin
                pmat[j] = 32'd0;
                if (pend[j] && enbl[j])
                    pmat[j] = prio_arr[j];
            end
            for (j = NUM_SRC-1; j >= 1; j = j - 1) begin
                if (pmat[j] > thresh && pmat[j] > best) begin
                    best = pmat[j];
                    id   = j;
                end
            end
            find_highest = id;
        end
    endfunction

    wire [7:0] highest_id = find_highest(r_pending, r_enable, r_threshold, r_prio);
    wire       any_pending = (highest_id != 8'd0);

    assign o_eip = any_pending;

    // =========================================================================
    // WSTRB-aware write data: only update bytes where WSTRB[i]=1
    // For AXI4-Lite, WSTRB indicates which byte lanes of WDATA are valid.
    // Bytes with WSTRB[i]=0 retain their current register value.
    // =========================================================================
    wire [31:0] wdata_prio_masked = (wr_addr[7:2] < NUM_SRC) ?
        {(s_axi_wstrb[3] ? s_axi_wdata[31:24] : r_prio[wr_addr[7:2]][31:24]),
         (s_axi_wstrb[2] ? s_axi_wdata[23:16] : r_prio[wr_addr[7:2]][23:16]),
         (s_axi_wstrb[1] ? s_axi_wdata[15:8]  : r_prio[wr_addr[7:2]][15:8]),
         (s_axi_wstrb[0] ? s_axi_wdata[7:0]   : r_prio[wr_addr[7:2]][7:0])} : 32'd0;

    wire [31:0] wdata_enable_masked = {(s_axi_wstrb[3] ? s_axi_wdata[31:24] : r_enable[31:24]),
                                        (s_axi_wstrb[2] ? s_axi_wdata[23:16] : r_enable[23:16]),
                                        (s_axi_wstrb[1] ? s_axi_wdata[15:8]  : r_enable[15:8]),
                                        (s_axi_wstrb[0] ? s_axi_wdata[7:0]   : r_enable[7:0])};

    wire [31:0] wdata_thresh_masked = {(s_axi_wstrb[3] ? s_axi_wdata[31:24] : r_threshold[31:24]),
                                         (s_axi_wstrb[2] ? s_axi_wdata[23:16] : r_threshold[23:16]),
                                         (s_axi_wstrb[1] ? s_axi_wdata[15:8]  : r_threshold[15:8]),
                                         (s_axi_wstrb[0] ? s_axi_wdata[7:0]   : r_threshold[7:0])};

    // =========================================================================
    // Register update logic (adapted from AHB version)
    // =========================================================================
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            r_pending    <= 32'd0;
            r_enable     <= 32'd0;
            r_threshold  <= 32'd0;
            r_claim_id   <= 8'd0;
            r_gw_en      <= {(NUM_SRC){1'b1}};
            for (ii = 0; ii < NUM_SRC; ii = ii + 1)
                r_prio[ii] <= 32'd0;
        end else begin
            // 1. Pending and gateway enable logic (identical)
            for (ii = 1; ii < NUM_SRC; ii = ii + 1) begin
                if (r_gw_en[ii] && src_irq[ii])
                    r_pending[ii] <= 1'b1;
            end

            for (ii = 1; ii < NUM_SRC; ii = ii + 1) begin
                if (!src_irq[ii])
                    r_gw_en[ii] <= 1'b1;
            end

            // 2. AXI4-Lite write operations (WSTRB-aware)
            if (wr_fire && wr_addr_is_prio && (wr_addr[7:2] < NUM_SRC))
                r_prio[wr_addr[7:2]] <= wdata_prio_masked;

            if (wr_fire && wr_addr_is_enable)
                r_enable <= wdata_enable_masked;

            if (wr_fire && wr_addr_is_thresh)
                r_threshold <= wdata_thresh_masked;

            if (wr_fire && wr_addr_is_claim) begin
                // Claim/complete: only byte 0 matters (interrupt ID)
                if (s_axi_wstrb[0] && (s_axi_wdata >= 1) && (s_axi_wdata < NUM_SRC))
                    r_gw_en[s_axi_wdata] <= 1'b1;
            end

            // 3. AXI4-Lite read Claim: atomic return highest_id and clear pending
            //    r_claim_id is latched so the R channel returns the correct ID
            //    even though the pending clear takes effect one cycle later.
            if (rd_fire && rd_addr_is_claim) begin
                r_claim_id <= highest_id;
                if (any_pending) begin
                    r_pending[highest_id] <= 1'b0;
                    r_gw_en[highest_id]   <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // Read data mux (uses latched rd_addr; claim returns r_claim_id)
    // =========================================================================
    always_comb begin
        s_axi_rdata = 32'd0;
        if (rd_addr_is_prio) begin
            s_axi_rdata = (rd_addr[7:2] < NUM_SRC) ? r_prio[rd_addr[7:2]] : 32'd0;
        end else if (rd_addr_is_pend) begin
            s_axi_rdata = r_pending;
        end else if (rd_addr_is_enable) begin
            s_axi_rdata = r_enable;
        end else if (rd_addr_is_thresh) begin
            s_axi_rdata = r_threshold;
        end else if (rd_addr_is_claim) begin
            s_axi_rdata = {24'd0, r_claim_id};
        end
    end

endmodule
