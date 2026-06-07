`timescale 1ns / 1ps
`include "cache_def.svh"

module tlb #(
    parameter ENTRIES = 16
)(
    input              clk,
    input              reset,

    // ── Port A: i-side lookup (read-only) ──
    input  [19:0]      i_lookup_vpn,
    input  [8:0]       i_lookup_asid,
    input              i_lookup_req,
    output             i_lookup_hit,
    output [21:0]      i_lookup_ppn,
    output             i_lookup_r,
    output             i_lookup_w,
    output             i_lookup_x,
    output             i_lookup_u,
    output             i_lookup_a,
    output             i_lookup_d,
    output             i_lookup_g,
    output             i_lookup_is_megapage,
    output             i_lookup_valid,

    // ── Port B: d-side lookup (read) or PTW fill (write, priority) ──
    input  [19:0]      d_lookup_vpn,
    input  [8:0]       d_lookup_asid,
    input              d_lookup_req,
    output             d_lookup_hit,
    output [21:0]      d_lookup_ppn,
    output             d_lookup_r,
    output             d_lookup_w,
    output             d_lookup_x,
    output             d_lookup_u,
    output             d_lookup_a,
    output             d_lookup_d,
    output             d_lookup_g,
    output             d_lookup_is_megapage,
    output             d_lookup_valid,

    // ── Fill (uses Port B write, preempts d-lookup) ──
    input              fill_req,
    input  [19:0]      fill_vpn,
    input  [8:0]       fill_asid,
    input  [21:0]      fill_ppn,
    input              fill_r,
    input              fill_w,
    input              fill_x,
    input              fill_u,
    input              fill_a,
    input              fill_d,
    input              fill_g,
    input              fill_is_megapage,

    // ── Flush ──
    input              flush_all,
    output             flush_done
);

`ifdef USE_TLB_BRAM

// =========================================================================
// BRAM-based set-associative TLB (4-way x 4-set = 16 entries)
// Dual-port: Port A = i-side lookup, Port B = d-side lookup / fill
// =========================================================================

localparam NUM_WAYS      = `TLB_NUM_WAYS;
localparam NUM_SETS      = `TLB_NUM_SETS;
localparam SET_IDX_W     = `TLB_SET_IDX_WIDTH;
localparam WAY_W         = `TLB_WAY_WIDTH;
localparam FLAG_ENTRY_W  = `TLB_FLAG_ENTRY_WIDTH;
localparam DATA_ENTRY_W  = `TLB_DATA_ENTRY_WIDTH;

// --- State machine (simplified: no per-lookup FSM, MMU manages sequencing) ---
localparam S_RUN   = 2'd0;
localparam S_FLUSH = 2'd1;

reg [1:0] state;

// --- Set index: upper VPN bits only (no VPN[1:0]) ---
// This ensures all VPNs within a megapage (which differ only in VPN[1:0])
// map to the same set, so megapage entries don't need replication.
wire [SET_IDX_W-1:0] i_lookup_set_idx = i_lookup_vpn[SET_IDX_W+9:10];
wire [SET_IDX_W-1:0] d_lookup_set_idx = d_lookup_vpn[SET_IDX_W+9:10];
wire [SET_IDX_W-1:0] fill_set_idx     = fill_vpn[SET_IDX_W+9:10];

// --- Latched lookup values (for comparison when BRAM output valid) ---
reg [19:0]           i_latched_vpn;
reg [8:0]            i_latched_asid;
reg [SET_IDX_W-1:0]  i_latched_set_idx;

reg [19:0]           d_latched_vpn;
reg [8:0]            d_latched_asid;
reg [SET_IDX_W-1:0]  d_latched_set_idx;

// --- PLRU state per set ---
reg [NUM_WAYS-2:0] plru_state [0:NUM_SETS-1];

// --- Shadow valid bits (for victim way selection during fill) ---
reg valid_shadow [0:NUM_SETS-1][0:NUM_WAYS-1];

// --- Flush counter ---
reg [SET_IDX_W-1:0] flush_set;
reg flush_done_r;

// --- Valid pulses (1 cycle after corresponding req) ---
reg i_lookup_valid_r;
reg d_lookup_valid_r;

// =========================================================================
// Fill victim way selection (needed before BRAM Port B controls)
// =========================================================================
wire inv0_f = ~valid_shadow[fill_set_idx][0];
wire inv1_f = ~valid_shadow[fill_set_idx][1];
wire inv2_f = ~valid_shadow[fill_set_idx][2];
wire inv3_f = ~valid_shadow[fill_set_idx][3];

wire [WAY_W-1:0]    plru_victim_fill;
wire [NUM_WAYS-2:0] plru_next_fill;
tree_plru u_plru_fill(
    .plru_state (plru_state[fill_set_idx]),
    .victim_way (plru_victim_fill),
    .access_way (inv0_f ? 2'd0 :
                 inv1_f ? 2'd1 :
                 inv2_f ? 2'd2 :
                 inv3_f ? 2'd3 : plru_victim_fill),
    .next_state (plru_next_fill)
);

wire [WAY_W-1:0] fill_victim_way = inv0_f ? 2'd0 :
                                   inv1_f ? 2'd1 :
                                   inv2_f ? 2'd2 :
                                   inv3_f ? 2'd3 : plru_victim_fill;

// Megapage: normalize VPN[9:0] to 0
wire [19:0] fill_vpn_normalized = fill_is_megapage ? {fill_vpn[19:10], 10'b0} : fill_vpn;

// Pack flag entry for fill: {V(1), G(1), ASID(9), VPN(20), mega(1)}
wire [FLAG_ENTRY_W-1:0] fill_flag_entry = {1'b1, fill_g, fill_asid, fill_vpn_normalized, fill_is_megapage};

// Pack data entry for fill: {PPN(22), R(1), W(1), X(1), U(1), A(1), D(1), pad(4)}
wire [DATA_ENTRY_W-1:0] fill_data_entry = {fill_ppn, fill_r, fill_w, fill_x, fill_u, fill_a, fill_d, 4'b0};

// Place fill entry at victim way position in BRAM line
wire [`TLB_FLAG_BRAM_WIDTH-1:0] fill_flag_din;
assign fill_flag_din[FLAG_ENTRY_W*0 +: FLAG_ENTRY_W] = (fill_victim_way == 2'd0) ? fill_flag_entry : {FLAG_ENTRY_W{1'b0}};
assign fill_flag_din[FLAG_ENTRY_W*1 +: FLAG_ENTRY_W] = (fill_victim_way == 2'd1) ? fill_flag_entry : {FLAG_ENTRY_W{1'b0}};
assign fill_flag_din[FLAG_ENTRY_W*2 +: FLAG_ENTRY_W] = (fill_victim_way == 2'd2) ? fill_flag_entry : {FLAG_ENTRY_W{1'b0}};
assign fill_flag_din[FLAG_ENTRY_W*3 +: FLAG_ENTRY_W] = (fill_victim_way == 2'd3) ? fill_flag_entry : {FLAG_ENTRY_W{1'b0}};

wire [`TLB_DATA_BRAM_WIDTH-1:0] fill_data_din;
assign fill_data_din[DATA_ENTRY_W*0 +: DATA_ENTRY_W] = (fill_victim_way == 2'd0) ? fill_data_entry : {DATA_ENTRY_W{1'b0}};
assign fill_data_din[DATA_ENTRY_W*1 +: DATA_ENTRY_W] = (fill_victim_way == 2'd1) ? fill_data_entry : {DATA_ENTRY_W{1'b0}};
assign fill_data_din[DATA_ENTRY_W*2 +: DATA_ENTRY_W] = (fill_victim_way == 2'd2) ? fill_data_entry : {DATA_ENTRY_W{1'b0}};
assign fill_data_din[DATA_ENTRY_W*3 +: DATA_ENTRY_W] = (fill_victim_way == 2'd3) ? fill_data_entry : {DATA_ENTRY_W{1'b0}};

// =========================================================================
// Flag BRAM (tlb_flag) — 128-bit x 4 deep
// Per-way flag entry (32 bits): {V(1), G(1), ASID(9), VPN(20), mega(1)}
// =========================================================================
wire [`TLB_FLAG_BRAM_WIDTH-1:0] flag_bram_douta;
wire [`TLB_FLAG_BRAM_WIDTH-1:0] flag_bram_doutb;

// Port B fill-active: fill preempts d-lookup on Port B
wire portb_fill = fill_req;

// Port A: i-side lookup (combinational controls, 1-cycle read latency)
wire        flag_bram_ena   = (state == S_RUN) && i_lookup_req && !flush_all;
wire [SET_IDX_W-1:0] flag_bram_addra = i_lookup_set_idx;

// Port B: d-side lookup (read) or fill (write) or flush (write) — combinational
wire        flag_bram_enb = (state == S_FLUSH) ? 1'b1 :
                            (state == S_RUN)   ? (portb_fill || (d_lookup_req && !flush_all)) : 1'b0;
wire [`TLB_FLAG_BRAM_WEA_WIDTH-1:0] flag_bram_web =
    (state == S_FLUSH) ? {`TLB_FLAG_BRAM_WEA_WIDTH{1'b1}} :
    (state == S_RUN && portb_fill) ? ({{(`TLB_FLAG_BRAM_WEA_WIDTH-4){1'b0}}, 4'hF} << ({fill_victim_way, 2'b0})) :
    {`TLB_FLAG_BRAM_WEA_WIDTH{1'b0}};
wire [SET_IDX_W-1:0] flag_bram_addrb =
    (state == S_FLUSH) ? flush_set :
    (state == S_RUN && portb_fill) ? fill_set_idx : d_lookup_set_idx;
wire [`TLB_FLAG_BRAM_WIDTH-1:0] flag_bram_dinb =
    (state == S_FLUSH) ? {`TLB_FLAG_BRAM_WIDTH{1'b0}} :
    (state == S_RUN && portb_fill) ? fill_flag_din : {`TLB_FLAG_BRAM_WIDTH{1'b0}};

tlb_flag u_tlb_flag(
    .clka   (clk),
    .ena    (flag_bram_ena),
    .wea    ({`TLB_FLAG_BRAM_WEA_WIDTH{1'b0}}),
    .addra  (flag_bram_addra),
    .dina   ({`TLB_FLAG_BRAM_WIDTH{1'b0}}),
    .douta  (flag_bram_douta),

    .clkb   (clk),
    .enb    (flag_bram_enb),
    .web    (flag_bram_web),
    .addrb  (flag_bram_addrb),
    .dinb   (flag_bram_dinb),
    .doutb  (flag_bram_doutb)
);

// =========================================================================
// Data BRAM (tlb_data) — 128-bit x 4 deep
// Per-way data entry (32 bits): {PPN(22), R(1), W(1), X(1), U(1), A(1), D(1), pad(4)}
// =========================================================================
wire [`TLB_DATA_BRAM_WIDTH-1:0] data_bram_douta;
wire [`TLB_DATA_BRAM_WIDTH-1:0] data_bram_doutb;

// Port A: i-side lookup (combinational)
wire        data_bram_ena   = (state == S_RUN) && i_lookup_req && !flush_all;
wire [SET_IDX_W-1:0] data_bram_addra = i_lookup_set_idx;

// Port B: d-side lookup or fill or flush — combinational
wire        data_bram_enb = (state == S_FLUSH) ? 1'b1 :
                            (state == S_RUN)   ? (portb_fill || (d_lookup_req && !flush_all)) : 1'b0;
wire [`TLB_DATA_BRAM_WEA_WIDTH-1:0] data_bram_web =
    (state == S_FLUSH) ? {`TLB_DATA_BRAM_WEA_WIDTH{1'b1}} :
    (state == S_RUN && portb_fill) ? ({{(`TLB_DATA_BRAM_WEA_WIDTH-4){1'b0}}, 4'hF} << ({fill_victim_way, 2'b0})) :
    {`TLB_DATA_BRAM_WEA_WIDTH{1'b0}};
wire [SET_IDX_W-1:0] data_bram_addrb =
    (state == S_FLUSH) ? flush_set :
    (state == S_RUN && portb_fill) ? fill_set_idx : d_lookup_set_idx;
wire [`TLB_DATA_BRAM_WIDTH-1:0] data_bram_dinb =
    (state == S_FLUSH) ? {`TLB_DATA_BRAM_WIDTH{1'b0}} :
    (state == S_RUN && portb_fill) ? fill_data_din : {`TLB_DATA_BRAM_WIDTH{1'b0}};

tlb_data u_tlb_data(
    .clka   (clk),
    .ena    (data_bram_ena),
    .wea    ({`TLB_DATA_BRAM_WEA_WIDTH{1'b0}}),
    .addra  (data_bram_addra),
    .dina   ({`TLB_DATA_BRAM_WIDTH{1'b0}}),
    .douta  (data_bram_douta),

    .clkb   (clk),
    .enb    (data_bram_enb),
    .web    (data_bram_web),
    .addrb  (data_bram_addrb),
    .dinb   (data_bram_dinb),
    .doutb  (data_bram_doutb)
);

// =========================================================================
// i-side 4-way parallel match (Port A output, valid 1 cycle after i_lookup_req)
// =========================================================================

wire [FLAG_ENTRY_W-1:0] i_flag_r0 = flag_bram_douta[FLAG_ENTRY_W*1-1:FLAG_ENTRY_W*0];
wire [FLAG_ENTRY_W-1:0] i_flag_r1 = flag_bram_douta[FLAG_ENTRY_W*2-1:FLAG_ENTRY_W*1];
wire [FLAG_ENTRY_W-1:0] i_flag_r2 = flag_bram_douta[FLAG_ENTRY_W*3-1:FLAG_ENTRY_W*2];
wire [FLAG_ENTRY_W-1:0] i_flag_r3 = flag_bram_douta[FLAG_ENTRY_W*4-1:FLAG_ENTRY_W*3];

wire [DATA_ENTRY_W-1:0] i_data_r0 = data_bram_douta[DATA_ENTRY_W*1-1:DATA_ENTRY_W*0];
wire [DATA_ENTRY_W-1:0] i_data_r1 = data_bram_douta[DATA_ENTRY_W*2-1:DATA_ENTRY_W*1];
wire [DATA_ENTRY_W-1:0] i_data_r2 = data_bram_douta[DATA_ENTRY_W*3-1:DATA_ENTRY_W*2];
wire [DATA_ENTRY_W-1:0] i_data_r3 = data_bram_douta[DATA_ENTRY_W*4-1:DATA_ENTRY_W*3];

// Flag entry layout: [31]=V, [30]=G, [29:21]=ASID, [20:1]=VPN, [0]=mega
wire i_valid0  = i_flag_r0[31], i_valid1  = i_flag_r1[31],
     i_valid2  = i_flag_r2[31], i_valid3  = i_flag_r3[31];
wire i_global0 = i_flag_r0[30], i_global1 = i_flag_r1[30],
     i_global2 = i_flag_r2[30], i_global3 = i_flag_r3[30];
wire [8:0]  i_asid0 = i_flag_r0[29:21], i_asid1 = i_flag_r1[29:21],
           i_asid2 = i_flag_r2[29:21], i_asid3 = i_flag_r3[29:21];
wire [19:0] i_vpn0  = i_flag_r0[20:1],  i_vpn1  = i_flag_r1[20:1],
           i_vpn2  = i_flag_r2[20:1],  i_vpn3  = i_flag_r3[20:1];
wire i_mega0  = i_flag_r0[0],  i_mega1  = i_flag_r1[0],
     i_mega2  = i_flag_r2[0],  i_mega3  = i_flag_r3[0];

wire i_vpn_match0 = i_mega0 ? (i_vpn0[19:10] == i_latched_vpn[19:10]) : (i_vpn0 == i_latched_vpn);
wire i_vpn_match1 = i_mega1 ? (i_vpn1[19:10] == i_latched_vpn[19:10]) : (i_vpn1 == i_latched_vpn);
wire i_vpn_match2 = i_mega2 ? (i_vpn2[19:10] == i_latched_vpn[19:10]) : (i_vpn2 == i_latched_vpn);
wire i_vpn_match3 = i_mega3 ? (i_vpn3[19:10] == i_latched_vpn[19:10]) : (i_vpn3 == i_latched_vpn);

wire i_hit0 = i_valid0 && i_vpn_match0 && (i_global0 || (i_asid0 == i_latched_asid));
wire i_hit1 = i_valid1 && i_vpn_match1 && (i_global1 || (i_asid1 == i_latched_asid));
wire i_hit2 = i_valid2 && i_vpn_match2 && (i_global2 || (i_asid2 == i_latched_asid));
wire i_hit3 = i_valid3 && i_vpn_match3 && (i_global3 || (i_asid3 == i_latched_asid));

wire i_tlb_hit = i_hit0 | i_hit1 | i_hit2 | i_hit3;
assign i_lookup_hit = i_tlb_hit;

wire [WAY_W-1:0] i_hit_way = i_hit0 ? 2'd0 :
                            i_hit1 ? 2'd1 :
                            i_hit2 ? 2'd2 : 2'd3;

wire [FLAG_ENTRY_W-1:0] i_hit_flag = i_hit0 ? i_flag_r0 :
                                    i_hit1 ? i_flag_r1 :
                                    i_hit2 ? i_flag_r2 : i_flag_r3;

wire [DATA_ENTRY_W-1:0] i_hit_data = i_hit0 ? i_data_r0 :
                                    i_hit1 ? i_data_r1 :
                                    i_hit2 ? i_data_r2 : i_data_r3;

// Data entry layout: [31:10]=PPN, [9]=R, [8]=W, [7]=X, [6]=U, [5]=A, [4]=D, [3:0]=pad
assign i_lookup_ppn         = i_hit_data[31:10];
assign i_lookup_r           = i_hit_data[9];
assign i_lookup_w           = i_hit_data[8];
assign i_lookup_x           = i_hit_data[7];
assign i_lookup_u           = i_hit_data[6];
assign i_lookup_a           = i_hit_data[5];
assign i_lookup_d           = i_hit_data[4];
assign i_lookup_g           = i_hit_flag[30];
assign i_lookup_is_megapage = i_hit_flag[0];

// =========================================================================
// d-side 4-way parallel match (Port B output, valid 1 cycle after d_lookup_req)
// =========================================================================

wire [FLAG_ENTRY_W-1:0] d_flag_r0 = flag_bram_doutb[FLAG_ENTRY_W*1-1:FLAG_ENTRY_W*0];
wire [FLAG_ENTRY_W-1:0] d_flag_r1 = flag_bram_doutb[FLAG_ENTRY_W*2-1:FLAG_ENTRY_W*1];
wire [FLAG_ENTRY_W-1:0] d_flag_r2 = flag_bram_doutb[FLAG_ENTRY_W*3-1:FLAG_ENTRY_W*2];
wire [FLAG_ENTRY_W-1:0] d_flag_r3 = flag_bram_doutb[FLAG_ENTRY_W*4-1:FLAG_ENTRY_W*3];

wire [DATA_ENTRY_W-1:0] d_data_r0 = data_bram_doutb[DATA_ENTRY_W*1-1:DATA_ENTRY_W*0];
wire [DATA_ENTRY_W-1:0] d_data_r1 = data_bram_doutb[DATA_ENTRY_W*2-1:DATA_ENTRY_W*1];
wire [DATA_ENTRY_W-1:0] d_data_r2 = data_bram_doutb[DATA_ENTRY_W*3-1:DATA_ENTRY_W*2];
wire [DATA_ENTRY_W-1:0] d_data_r3 = data_bram_doutb[DATA_ENTRY_W*4-1:DATA_ENTRY_W*3];

wire d_valid0  = d_flag_r0[31], d_valid1  = d_flag_r1[31],
     d_valid2  = d_flag_r2[31], d_valid3  = d_flag_r3[31];
wire d_global0 = d_flag_r0[30], d_global1 = d_flag_r1[30],
     d_global2 = d_flag_r2[30], d_global3 = d_flag_r3[30];
wire [8:0]  d_asid0 = d_flag_r0[29:21], d_asid1 = d_flag_r1[29:21],
           d_asid2 = d_flag_r2[29:21], d_asid3 = d_flag_r3[29:21];
wire [19:0] d_vpn0  = d_flag_r0[20:1],  d_vpn1  = d_flag_r1[20:1],
           d_vpn2  = d_flag_r2[20:1],  d_vpn3  = d_flag_r3[20:1];
wire d_mega0  = d_flag_r0[0],  d_mega1  = d_flag_r1[0],
     d_mega2  = d_flag_r2[0],  d_mega3  = d_flag_r3[0];

wire d_vpn_match0 = d_mega0 ? (d_vpn0[19:10] == d_latched_vpn[19:10]) : (d_vpn0 == d_latched_vpn);
wire d_vpn_match1 = d_mega1 ? (d_vpn1[19:10] == d_latched_vpn[19:10]) : (d_vpn1 == d_latched_vpn);
wire d_vpn_match2 = d_mega2 ? (d_vpn2[19:10] == d_latched_vpn[19:10]) : (d_vpn2 == d_latched_vpn);
wire d_vpn_match3 = d_mega3 ? (d_vpn3[19:10] == d_latched_vpn[19:10]) : (d_vpn3 == d_latched_vpn);

wire d_hit0 = d_valid0 && d_vpn_match0 && (d_global0 || (d_asid0 == d_latched_asid));
wire d_hit1 = d_valid1 && d_vpn_match1 && (d_global1 || (d_asid1 == d_latched_asid));
wire d_hit2 = d_valid2 && d_vpn_match2 && (d_global2 || (d_asid2 == d_latched_asid));
wire d_hit3 = d_valid3 && d_vpn_match3 && (d_global3 || (d_asid3 == d_latched_asid));

wire d_tlb_hit = d_hit0 | d_hit1 | d_hit2 | d_hit3;
assign d_lookup_hit = d_tlb_hit;

wire [WAY_W-1:0] d_hit_way = d_hit0 ? 2'd0 :
                            d_hit1 ? 2'd1 :
                            d_hit2 ? 2'd2 : 2'd3;

wire [FLAG_ENTRY_W-1:0] d_hit_flag = d_hit0 ? d_flag_r0 :
                                    d_hit1 ? d_flag_r1 :
                                    d_hit2 ? d_flag_r2 : d_flag_r3;

wire [DATA_ENTRY_W-1:0] d_hit_data = d_hit0 ? d_data_r0 :
                                    d_hit1 ? d_data_r1 :
                                    d_hit2 ? d_data_r2 : d_data_r3;

assign d_lookup_ppn         = d_hit_data[31:10];
assign d_lookup_r           = d_hit_data[9];
assign d_lookup_w           = d_hit_data[8];
assign d_lookup_x           = d_hit_data[7];
assign d_lookup_u           = d_hit_data[6];
assign d_lookup_a           = d_hit_data[5];
assign d_lookup_d           = d_hit_data[4];
assign d_lookup_g           = d_hit_flag[30];
assign d_lookup_is_megapage = d_hit_flag[0];

assign i_lookup_valid = i_lookup_valid_r;
assign d_lookup_valid = d_lookup_valid_r;
assign flush_done     = flush_done_r;

// =========================================================================
// PLRU for i-side lookup hit
// =========================================================================
wire [WAY_W-1:0]    i_plru_victim;
wire [NUM_WAYS-2:0] i_plru_next;
tree_plru u_i_plru(
    .plru_state (plru_state[i_latched_set_idx]),
    .victim_way (i_plru_victim),
    .access_way (i_hit_way),
    .next_state (i_plru_next)
);

// =========================================================================
// PLRU for d-side lookup hit
// =========================================================================
wire [WAY_W-1:0]    d_plru_victim;
wire [NUM_WAYS-2:0] d_plru_next;
tree_plru u_d_plru(
    .plru_state (plru_state[d_latched_set_idx]),
    .victim_way (d_plru_victim),
    .access_way (d_hit_way),
    .next_state (d_plru_next)
);

// =========================================================================
// State machine + latching + PLRU update
// =========================================================================
integer i;
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        state            <= S_FLUSH;   // BUG-9: start in S_FLUSH to zero BRAM on reset
        i_latched_vpn    <= 20'b0;
        i_latched_asid   <= 9'b0;
        i_latched_set_idx <= {SET_IDX_W{1'b0}};
        d_latched_vpn    <= 20'b0;
        d_latched_asid   <= 9'b0;
        d_latched_set_idx <= {SET_IDX_W{1'b0}};
        flush_set        <= {SET_IDX_W{1'b0}};
        flush_done_r     <= 1'b0;
        i_lookup_valid_r <= 1'b0;
        d_lookup_valid_r <= 1'b0;
        for (i = 0; i < NUM_SETS; i = i + 1) begin
            plru_state[i] <= {NUM_WAYS-1{1'b0}};
            for (integer w = 0; w < NUM_WAYS; w = w + 1)
                valid_shadow[i][w] <= 1'b0;
        end
    end else begin
        flush_done_r     <= 1'b0;
        i_lookup_valid_r <= 1'b0;
        d_lookup_valid_r <= 1'b0;

        case (state)
            S_RUN: begin
                if (flush_all) begin
                    state     <= S_FLUSH;
                    flush_set <= {SET_IDX_W{1'b0}};
                end else begin
                    // i-side latch (Port A read initiated by i_lookup_req)
                    if (i_lookup_req) begin
                        i_latched_vpn     <= i_lookup_vpn;
                        i_latched_asid    <= i_lookup_asid;
                        i_latched_set_idx <= i_lookup_set_idx;
                        i_lookup_valid_r  <= 1'b1;
                    end

                    // d-side latch (Port B read, only when not preempted by fill)
                    if (d_lookup_req && !fill_req) begin
                        d_latched_vpn     <= d_lookup_vpn;
                        d_latched_asid    <= d_lookup_asid;
                        d_latched_set_idx <= d_lookup_set_idx;
                        d_lookup_valid_r  <= 1'b1;
                    end

                    // Fill: update valid_shadow and PLRU
                    if (fill_req) begin
                        valid_shadow[fill_set_idx][fill_victim_way] <= 1'b1;
                        plru_state[fill_set_idx] <= plru_next_fill;
                    end

                    // PLRU update on lookup hits (gated by valid pulse)
                    // If both sides hit the same set in the same cycle, d-side wins
                    if (i_lookup_valid_r && i_tlb_hit && d_lookup_valid_r && d_tlb_hit &&
                        (i_latched_set_idx == d_latched_set_idx)) begin
                        plru_state[d_latched_set_idx] <= d_plru_next;
                    end else begin
                        if (i_lookup_valid_r && i_tlb_hit)
                            plru_state[i_latched_set_idx] <= i_plru_next;
                        if (d_lookup_valid_r && d_tlb_hit)
                            plru_state[d_latched_set_idx] <= d_plru_next;
                    end
                end
            end

            S_FLUSH: begin
                // Clear shadow valid bits for this set
                for (i = 0; i < NUM_WAYS; i = i + 1)
                    valid_shadow[flush_set][i] <= 1'b0;

                if (flush_set == NUM_SETS - 1) begin
                    for (i = 0; i < NUM_SETS; i = i + 1)
                        plru_state[i] <= {NUM_WAYS-1{1'b0}};
                    flush_done_r <= 1'b1;
                    state <= S_RUN;
                end else begin
                    flush_set <= flush_set + 1'b1;
                end
            end

            default: state <= S_RUN;
        endcase
    end
end

`else // !USE_TLB_BRAM

// =========================================================================
// Original fully-associative register array implementation (dual lookup)
// =========================================================================

localparam ENTRY_W = 1 + 1 + 9 + 20 + 22 + 1 + 1 + 1 + 1 + 1 + 1 + 1;

reg [ENTRY_W-1:0] entries [0:ENTRIES-1];
reg [$clog2(ENTRIES)-1:0] rr_ptr;

wire [ENTRY_W-1:0] e_out [0:ENTRIES-1];
genvar gi;
generate
    for (gi = 0; gi < ENTRIES; gi = gi + 1) begin : gen_entry
        assign e_out[gi] = entries[gi];
    end
endgenerate

// ── i-side hit vector ──
wire [ENTRIES-1:0] i_hit_vec;
generate
    for (gi = 0; gi < ENTRIES; gi = gi + 1) begin : gen_i_cmp
        wire valid_i  = e_out[gi][ENTRY_W-1];
        wire global_i = e_out[gi][ENTRY_W-2];
        wire [8:0]  asid_i  = e_out[gi][ENTRY_W-3 -: 9];
        wire [19:0] vpn_i   = e_out[gi][ENTRY_W-12 -: 20];
        wire        mega_i  = e_out[gi][0];
        wire vpn_match_i = mega_i ? (vpn_i[19:10] == i_lookup_vpn[19:10])
                                  : (vpn_i == i_lookup_vpn);
        assign i_hit_vec[gi] = valid_i && vpn_match_i &&
                               (global_i || (asid_i == i_lookup_asid));
    end
endgenerate

assign i_lookup_hit = |i_hit_vec;

reg [21:0] i_hit_ppn_r;
reg        i_hit_r_r, i_hit_w_r, i_hit_x_r, i_hit_u_r;
reg        i_hit_a_r, i_hit_d_r, i_hit_g_r;
reg        i_hit_mega_r;

// ── d-side hit vector ──
wire [ENTRIES-1:0] d_hit_vec;
generate
    for (gi = 0; gi < ENTRIES; gi = gi + 1) begin : gen_d_cmp
        wire valid_i  = e_out[gi][ENTRY_W-1];
        wire global_i = e_out[gi][ENTRY_W-2];
        wire [8:0]  asid_i  = e_out[gi][ENTRY_W-3 -: 9];
        wire [19:0] vpn_i   = e_out[gi][ENTRY_W-12 -: 20];
        wire        mega_i  = e_out[gi][0];
        wire vpn_match_i = mega_i ? (vpn_i[19:10] == d_lookup_vpn[19:10])
                                  : (vpn_i == d_lookup_vpn);
        assign d_hit_vec[gi] = valid_i && vpn_match_i &&
                               (global_i || (asid_i == d_lookup_asid));
    end
endgenerate

assign d_lookup_hit = |d_hit_vec;

reg [21:0] d_hit_ppn_r;
reg        d_hit_r_r, d_hit_w_r, d_hit_x_r, d_hit_u_r;
reg        d_hit_a_r, d_hit_d_r, d_hit_g_r;
reg        d_hit_mega_r;

integer i;
always_comb begin
    i_hit_ppn_r  = 22'b0;
    i_hit_r_r    = 1'b0;
    i_hit_w_r    = 1'b0;
    i_hit_x_r    = 1'b0;
    i_hit_u_r    = 1'b0;
    i_hit_a_r    = 1'b0;
    i_hit_d_r    = 1'b0;
    i_hit_g_r    = 1'b0;
    i_hit_mega_r = 1'b0;
    d_hit_ppn_r  = 22'b0;
    d_hit_r_r    = 1'b0;
    d_hit_w_r    = 1'b0;
    d_hit_x_r    = 1'b0;
    d_hit_u_r    = 1'b0;
    d_hit_a_r    = 1'b0;
    d_hit_d_r    = 1'b0;
    d_hit_g_r    = 1'b0;
    d_hit_mega_r = 1'b0;
    for (i = 0; i < ENTRIES; i = i + 1) begin
        if (i_hit_vec[i]) begin
            i_hit_ppn_r  = e_out[i][28:7];
            i_hit_r_r    = e_out[i][6];
            i_hit_w_r    = e_out[i][5];
            i_hit_x_r    = e_out[i][4];
            i_hit_u_r    = e_out[i][3];
            i_hit_a_r    = e_out[i][2];
            i_hit_d_r    = e_out[i][1];
            i_hit_g_r    = e_out[i][ENTRY_W-2];
            i_hit_mega_r = e_out[i][0];
        end
        if (d_hit_vec[i]) begin
            d_hit_ppn_r  = e_out[i][28:7];
            d_hit_r_r    = e_out[i][6];
            d_hit_w_r    = e_out[i][5];
            d_hit_x_r    = e_out[i][4];
            d_hit_u_r    = e_out[i][3];
            d_hit_a_r    = e_out[i][2];
            d_hit_d_r    = e_out[i][1];
            d_hit_g_r    = e_out[i][ENTRY_W-2];
            d_hit_mega_r = e_out[i][0];
        end
    end
end

assign i_lookup_ppn         = i_hit_ppn_r;
assign i_lookup_r           = i_hit_r_r;
assign i_lookup_w           = i_hit_w_r;
assign i_lookup_x           = i_hit_x_r;
assign i_lookup_u           = i_hit_u_r;
assign i_lookup_a           = i_hit_a_r;
assign i_lookup_d           = i_hit_d_r;
assign i_lookup_g           = i_hit_g_r;
assign i_lookup_is_megapage = i_hit_mega_r;

assign d_lookup_ppn         = d_hit_ppn_r;
assign d_lookup_r           = d_hit_r_r;
assign d_lookup_w           = d_hit_w_r;
assign d_lookup_x           = d_hit_x_r;
assign d_lookup_u           = d_hit_u_r;
assign d_lookup_a           = d_hit_a_r;
assign d_lookup_d           = d_hit_d_r;
assign d_lookup_g           = d_hit_g_r;
assign d_lookup_is_megapage = d_hit_mega_r;

// Non-BRAM: lookups are combinational, always valid
assign i_lookup_valid = 1'b1;
assign d_lookup_valid = 1'b1;
assign flush_done     = 1'b1;

function [ENTRY_W-1:0] pack_entry;
    input valid_i, global_i;
    input [8:0]  asid_i;
    input [19:0] vpn_i;
    input [21:0] ppn_i;
    input r_i, w_i, x_i, u_i, a_i, d_i, mega_i;
    begin
        pack_entry = {valid_i, global_i, asid_i, vpn_i, ppn_i,
                      r_i, w_i, x_i, u_i, a_i, d_i, mega_i};
    end
endfunction

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        rr_ptr <= '0;
        for (i = 0; i < ENTRIES; i = i + 1)
            entries[i] <= '0;
    end else begin
        if (flush_all) begin
            for (i = 0; i < ENTRIES; i = i + 1)
                entries[i][ENTRY_W-1] <= 1'b0;
        end else if (fill_req) begin
            entries[rr_ptr] <= pack_entry(
                1'b1, fill_g, fill_asid,
                fill_is_megapage ? {fill_vpn[19:10], 10'b0} : fill_vpn,
                fill_ppn,
                fill_r, fill_w, fill_x, fill_u, fill_a, fill_d, fill_is_megapage);
            rr_ptr <= rr_ptr + 1'b1;
        end
    end
end

`endif // USE_TLB_BRAM

endmodule
