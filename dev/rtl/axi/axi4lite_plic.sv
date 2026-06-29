`timescale 1ns / 1ps

`include "axi4_def.svh"

module axi4lite_plic #(
    parameter NUM_SRC = 8,
    parameter NUM_CTX = 2
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

    // Interrupt interface
    input  wire [NUM_SRC-1:0] src_irq,
    output reg  [NUM_CTX-1:0] o_eip       // [0]=M-mode, [1]=S-mode
);

    // =========================================================================
    // AXI4-Lite Write FSM
    // =========================================================================
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
            wr_state    <= WR_IDLE;
            wr_addr     <= 32'd0;
            wr_wdata    <= 32'd0;
            wr_wstrb    <= 4'd0;
            aw_latched  <= 1'b0;
            w_latched   <= 1'b0;
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
                        wr_state   <= WR_RESP;
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

    assign s_axi_bvalid = (wr_state == WR_RESP);
    assign s_axi_bresp  = `AXI_RESP_OKAY;

    // =========================================================================
    // AXI4-Lite Read FSM
    // =========================================================================
    localparam RD_IDLE        = 2'd0;
    localparam RD_WAIT        = 2'd1;
    localparam RD_RESP        = 2'd2;
    localparam RD_CLAIM_APPLY = 2'd3;

    reg [1:0]  rd_state;
    reg [31:0] rd_addr;
    reg [31:0] r_rd_data;
    reg [7:0]  rd_claim_id;

    assign s_axi_arready = (rd_state == RD_IDLE);

    assign s_axi_rvalid = (rd_state == RD_RESP);
    assign s_axi_rresp  = `AXI_RESP_OKAY;

    // =========================================================================
    // Address decode — SiFive PLIC standard layout
    // =========================================================================
    // Priority[S]:    offset 0x000000 + S*4   → addr[23:12]==12'h000, index=addr[7:2]
    // Pending:        offset 0x001000         → addr[23:12]==12'h001
    // Enable[ctx N]:  offset 0x002000 + N*0x80 → addr[23:12]==12'h002, ctx=addr[11:7]
    // Threshold[ctx]: offset 0x200000 + N*0x1000 → addr[23:20]==4'h2, ctx=addr[15:12], sub=addr[3:2]==0
    // Claim[ctx]:     offset 0x200000 + N*0x1000 + 4 → addr[23:20]==4'h2, ctx=addr[15:12], sub=addr[3:2]==1

    // --- Write path (latched wr_addr) ---
    wire wr_addr_is_prio   = (wr_addr_eff[23:12] == 12'h000);
    wire wr_addr_is_pend   = (wr_addr_eff[23:12] == 12'h001);
    wire wr_addr_is_enable = (wr_addr_eff[23:12] == 12'h002);
    wire wr_addr_is_ctx    = (wr_addr_eff[23:20] == 4'h2);   // threshold or claim
    wire wr_addr_is_thresh = wr_addr_is_ctx && (wr_addr_eff[3:2] == 2'd0);
    wire wr_addr_is_claim  = wr_addr_is_ctx && (wr_addr_eff[3:2] == 2'd1);

    wire [3:0] wr_ctx = wr_addr_eff[15:12];   // context index from address
    wire [4:0] wr_en_ctx = wr_addr_eff[11:7]; // enable context index from address

    // --- Read path (latched rd_addr) ---
    wire rd_addr_is_prio   = (rd_addr[23:12] == 12'h000);
    wire rd_addr_is_pend   = (rd_addr[23:12] == 12'h001);
    wire rd_addr_is_enable = (rd_addr[23:12] == 12'h002);
    wire rd_addr_is_ctx    = (rd_addr[23:20] == 4'h2);
    wire rd_addr_is_thresh = rd_addr_is_ctx && (rd_addr[3:2] == 2'd0);
    wire rd_addr_is_claim  = rd_addr_is_ctx && (rd_addr[3:2] == 2'd1);

    wire [3:0] rd_ctx = rd_addr[15:12];
    wire [4:0] rd_en_ctx = rd_addr[11:7];

    // =========================================================================
    // Internal registers
    // =========================================================================
    // Shared across all contexts
    reg  [31:0] r_prio [0:NUM_SRC-1];
    reg  [31:0] r_pending;
    reg  [NUM_SRC-1:0] r_gw_en;

    // Per-context
    reg  [31:0] r_enable   [0:NUM_CTX-1];
    reg  [31:0] r_threshold[0:NUM_CTX-1];

    // Stage 1 registered priority matrix:
    //   r_prio_pe[ci][j] = r_prio[j] if (r_pending[j] && r_enable[ci][j]), else 0
    // Pre-computed every cycle to break the r_enable -> find_highest -> r_highest_id
    // combinational path. The priority encoder is split into 2 half-range stages
    // (Stage 1: find best in each half, Stage 2: compare the two half-winners),
    // adding 2 pipeline registers total. Interrupt latency: r_pending ->
    // r_prio_pe -> r_best_lower/upper -> r_highest_id -> o_eip = 5 cycles.
    reg  [31:0] r_prio_pe  [0:NUM_CTX-1][0:NUM_SRC-1];

    integer ii;
    integer ci;

    // =========================================================================
    // find_highest function — returns highest-priority pending+enabled ID
    // =========================================================================
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
            for (j = 1; j < NUM_SRC; j = j + 1) begin
                if (pmat[j] > thresh && pmat[j] > best) begin
                    best = pmat[j];
                    id   = j;
                end
            end
            find_highest = id;
        end
    endfunction

    // Stage 1 half-encoder: finds the highest-priority source in a half-range.
    // Returns {best_prio[31:0], best_id[7:0]} so Stage 2 can compare priorities
    // without re-reading the r_prio_pe matrix.
    function [39:0] find_best_half;
        input [31:0] prio_pe [0:NUM_SRC-1];  // registered pending+enabled priorities
        input [31:0] thresh;
        input integer start_idx;
        input integer end_idx;
        reg   [31:0] best;
        reg   [7:0]  id;
        integer      j;
        begin
            best = 32'd0;
            id   = 8'd0;
            for (j = start_idx; j <= end_idx; j = j + 1) begin
                if (prio_pe[j] > thresh && prio_pe[j] > best) begin
                    best = prio_pe[j];
                    id   = j;
                end
            end
            find_best_half = {best, id};
        end
    endfunction

    // Split point: lower half = [1 .. HALF_MID], upper half = [HALF_MID+1 .. NUM_SRC-1]
    localparam integer HALF_MID = (NUM_SRC - 1) / 2;

    // Stage 1 combinational half-winners: {prio, id} per half per context
    wire [39:0] best_lower [0:NUM_CTX-1];
    wire [39:0] best_upper [0:NUM_CTX-1];

    // Stage 1 registers: latch the two half-winners
    reg  [7:0]  r_best_lower_id   [0:NUM_CTX-1];
    reg  [7:0]  r_best_upper_id   [0:NUM_CTX-1];
    reg  [31:0] r_best_lower_prio [0:NUM_CTX-1];
    reg  [31:0] r_best_upper_prio [0:NUM_CTX-1];

    // Stage 2 combinational: compare the two half-winners
    wire [7:0] highest_id [0:NUM_CTX-1];
    reg  [7:0] r_highest_id [0:NUM_CTX-1];
    wire       any_pending [0:NUM_CTX-1];

    genvar gi;
    generate
        for (gi = 0; gi < NUM_CTX; gi = gi + 1) begin : gen_ctx
            // Stage 1: find best in each half (combinational)
            assign best_lower[gi] = find_best_half(r_prio_pe[gi], r_threshold[gi], 1, HALF_MID);
            assign best_upper[gi] = find_best_half(r_prio_pe[gi], r_threshold[gi], HALF_MID + 1, NUM_SRC - 1);

            // Stage 2: pick the overall winner from the two registered half-winners
            wire lower_valid = (r_best_lower_id[gi]   != 8'd0) &&
                               (r_best_lower_prio[gi] > r_threshold[gi]);
            wire upper_valid = (r_best_upper_id[gi]   != 8'd0) &&
                               (r_best_upper_prio[gi] > r_threshold[gi]);
            assign highest_id[gi] = (!lower_valid && !upper_valid) ? 8'd0 :
                                     (upper_valid && (!lower_valid ||
                                      r_best_upper_prio[gi] > r_best_lower_prio[gi])) ?
                                     r_best_upper_id[gi] : r_best_lower_id[gi];
            assign any_pending[gi] = (r_highest_id[gi] != 8'd0);
        end
    endgenerate

    // =========================================================================
    // WSTRB-aware write data helpers
    // =========================================================================
    wire [31:0] wdata_prio_masked = (wr_addr_eff[7:2] < NUM_SRC) ?
        {(wr_wstrb_eff[3] ? wr_wdata_eff[31:24] : r_prio[wr_addr_eff[7:2]][31:24]),
         (wr_wstrb_eff[2] ? wr_wdata_eff[23:16] : r_prio[wr_addr_eff[7:2]][23:16]),
         (wr_wstrb_eff[1] ? wr_wdata_eff[15:8]  : r_prio[wr_addr_eff[7:2]][15:8]),
         (wr_wstrb_eff[0] ? wr_wdata_eff[7:0]   : r_prio[wr_addr_eff[7:2]][7:0])} : 32'd0;

    // Per-context enable WSTRB masking — computed for the addressed context
    wire [31:0] wdata_enable_masked [0:NUM_CTX-1];
    generate
        for (gi = 0; gi < NUM_CTX; gi = gi + 1) begin : gen_en_mask
            assign wdata_enable_masked[gi] =
                {(wr_wstrb_eff[3] ? wr_wdata_eff[31:24] : r_enable[gi][31:24]),
                 (wr_wstrb_eff[2] ? wr_wdata_eff[23:16] : r_enable[gi][23:16]),
                 (wr_wstrb_eff[1] ? wr_wdata_eff[15:8]  : r_enable[gi][15:8]),
                 (wr_wstrb_eff[0] ? wr_wdata_eff[7:0]   : r_enable[gi][7:0])};
        end
    endgenerate

    // Per-context threshold WSTRB masking
    wire [31:0] wdata_thresh_masked [0:NUM_CTX-1];
    generate
        for (gi = 0; gi < NUM_CTX; gi = gi + 1) begin : gen_th_mask
            assign wdata_thresh_masked[gi] =
                {(wr_wstrb_eff[3] ? wr_wdata_eff[31:24] : r_threshold[gi][31:24]),
                 (wr_wstrb_eff[2] ? wr_wdata_eff[23:16] : r_threshold[gi][23:16]),
                 (wr_wstrb_eff[1] ? wr_wdata_eff[15:8]  : r_threshold[gi][15:8]),
                 (wr_wstrb_eff[0] ? wr_wdata_eff[7:0]   : r_threshold[gi][7:0])};
        end
    endgenerate

    // =========================================================================
    // Register update logic
    // =========================================================================
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            rd_state <= RD_IDLE;
            rd_addr  <= 32'd0;
            r_rd_data <= 32'd0;
            rd_claim_id <= 8'd0;
            r_pending <= 32'd0;
            r_gw_en   <= {(NUM_SRC){1'b1}};
            o_eip     <= {NUM_CTX{1'b0}};
            for (ii = 0; ii < NUM_SRC; ii = ii + 1)
                r_prio[ii] <= 32'd0;
            for (ci = 0; ci < NUM_CTX; ci = ci + 1) begin
                r_enable[ci]    <= 32'd0;
                r_threshold[ci] <= 32'd0;
                r_highest_id[ci] <= 8'd0;
                r_best_lower_id[ci]   <= 8'd0;
                r_best_upper_id[ci]   <= 8'd0;
                r_best_lower_prio[ci] <= 32'd0;
                r_best_upper_prio[ci] <= 32'd0;
                for (ii = 0; ii < NUM_SRC; ii = ii + 1)
                    r_prio_pe[ci][ii] <= 32'd0;
            end
        end else begin
            // 1. Pending and gateway enable logic (shared, level-triggered)
            //    Defensive guard: when in RD_CLAIM_APPLY, exclude the claimed ID
            //    to prevent re-assertion of the interrupt being cleared.
            for (ii = 1; ii < NUM_SRC; ii = ii + 1) begin
                if (!(rd_state == RD_CLAIM_APPLY && ii == rd_claim_id)) begin
                    if (r_gw_en[ii] && src_irq[ii])
                        r_pending[ii] <= 1'b1;
                end
            end

            for (ii = 1; ii < NUM_SRC; ii = ii + 1) begin
                if (!src_irq[ii])
                    r_gw_en[ii] <= 1'b1;
            end

            // 1a. Stage 1 priority matrix: pre-compute pending+enabled priorities.
            //     Updated in the same always_ff as r_pending/r_enable so it reflects
            //     the latest state. This breaks the r_enable -> find_highest path.
            for (ci = 0; ci < NUM_CTX; ci = ci + 1) begin
                for (ii = 0; ii < NUM_SRC; ii = ii + 1) begin
                    r_prio_pe[ci][ii] <= (r_pending[ii] && r_enable[ci][ii])
                                         ? r_prio[ii] : 32'd0;
                end
            end

            // 1b. Stage 1 register: latch the two half-winners (combinational
            //     find_best_half results from r_prio_pe). This splits the
            //     25-level priority encoder into two ~15-level halves.
            for (ci = 0; ci < NUM_CTX; ci = ci + 1) begin
                r_best_lower_id[ci]   <= best_lower[ci][7:0];
                r_best_lower_prio[ci] <= best_lower[ci][39:8];
                r_best_upper_id[ci]   <= best_upper[ci][7:0];
                r_best_upper_prio[ci] <= best_upper[ci][39:8];
            end

            // 1c. Stage 2 register: latch the final highest_id (1 comparison)
            for (ci = 0; ci < NUM_CTX; ci = ci + 1) begin
                r_highest_id[ci] <= highest_id[ci];
            end

            // 1d. Register o_eip output
            for (ci = 0; ci < NUM_CTX; ci = ci + 1) begin
                o_eip[ci] <= any_pending[ci];
            end

            // 2. AXI4-Lite write operations (WSTRB-aware)

            // Priority write (shared)
            if (wr_fire && wr_addr_is_prio && (wr_addr_eff[7:2] < NUM_SRC))
                r_prio[wr_addr_eff[7:2]] <= wdata_prio_masked;

            // Enable write (per-context)
            if (wr_fire && wr_addr_is_enable) begin
                for (ci = 0; ci < NUM_CTX; ci = ci + 1) begin
                    if (wr_en_ctx == ci)
                        r_enable[ci] <= wdata_enable_masked[ci];
                end
            end

            // Threshold write (per-context)
            if (wr_fire && wr_addr_is_thresh) begin
                for (ci = 0; ci < NUM_CTX; ci = ci + 1) begin
                    if (wr_ctx == ci)
                        r_threshold[ci] <= wdata_thresh_masked[ci];
                end
            end

            // Claim/Complete write (per-context): Complete re-enables gateway
            if (wr_fire && wr_addr_is_claim) begin
                if (wr_wstrb_eff[0] && (wr_wdata_eff[7:0] >= 1) && (wr_wdata_eff[7:0] < NUM_SRC))
                    r_gw_en[wr_wdata_eff[7:0]] <= 1'b1;
            end

            // 3. Read request handling, including pipelined claim.
            case (rd_state)
                RD_IDLE: begin
                    if (s_axi_arvalid) begin
                        rd_addr  <= s_axi_araddr;
                        rd_claim_id <= 8'd0;
                        if ((s_axi_araddr[23:20] == 4'h2) && (s_axi_araddr[3:2] == 2'd1)) begin
                            // Claim read: latch the registered highest_id, defer clear to RD_CLAIM_APPLY
                            if (s_axi_araddr[15:12] == 4'd0) begin
                                rd_claim_id <= r_highest_id[0];
                            end else if ((NUM_CTX > 1) && (s_axi_araddr[15:12] == 4'd1)) begin
                                rd_claim_id <= r_highest_id[1];
                            end
                            rd_state <= RD_CLAIM_APPLY;
                        end else begin
                            rd_state <= RD_WAIT;
                        end
                    end
                end
                RD_CLAIM_APPLY: begin
                    // Apply the claim: clear pending and gateway enable for the latched ID
                    if (rd_claim_id != 8'd0) begin
                        r_pending[rd_claim_id] <= 1'b0;
                        r_gw_en[rd_claim_id]   <= 1'b0;
                    end
                    rd_state <= RD_WAIT;
                end
                RD_WAIT: begin
                    if (rd_addr_is_prio) begin
                        r_rd_data <= (rd_addr[7:2] < NUM_SRC) ? r_prio[rd_addr[7:2]] : 32'd0;
                    end else if (rd_addr_is_pend) begin
                        r_rd_data <= r_pending;
                    end else if (rd_addr_is_enable) begin
                        r_rd_data <= 32'd0;
                        if (rd_en_ctx == 0)
                            r_rd_data <= r_enable[0];
                        else if ((NUM_CTX > 1) && (rd_en_ctx == 1))
                            r_rd_data <= r_enable[1];
                    end else if (rd_addr_is_thresh) begin
                        r_rd_data <= 32'd0;
                        if (rd_ctx == 0)
                            r_rd_data <= r_threshold[0];
                        else if ((NUM_CTX > 1) && (rd_ctx == 1))
                            r_rd_data <= r_threshold[1];
                    end else if (rd_addr_is_claim) begin
                        r_rd_data <= {24'd0, rd_claim_id};
                    end else begin
                        r_rd_data <= 32'd0;
                    end
                    rd_state <= RD_RESP;
                end
                RD_RESP: begin
                    if (s_axi_rready)
                        rd_state <= RD_IDLE;
                end
                default: rd_state <= RD_IDLE;
            endcase

        end
    end

    // =========================================================================
    // Read data mux
    // =========================================================================
    always_comb begin
        s_axi_rdata = r_rd_data;
    end

endmodule
