`timescale 1ns / 1ps
`include "cache_def.svh"

module tlb #(
    parameter ENTRIES = 16
)(
    input              clk,
    input              reset,

    input  [19:0]      lookup_vpn,
    input  [8:0]       lookup_asid,
    input              lookup_req,
    output             lookup_hit,
    output [21:0]      lookup_ppn,
    output             lookup_r,
    output             lookup_w,
    output             lookup_x,
    output             lookup_u,
    output             lookup_a,
    output             lookup_d,
    output             lookup_g,
    output             lookup_is_megapage,
    output             lookup_valid,

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

    input              flush_all,
    output             flush_done
);

`ifdef USE_TLB_BRAM

// =========================================================================
// BRAM-based set-associative TLB (4-way x 4-set = 16 entries)
// =========================================================================

localparam NUM_WAYS      = `TLB_NUM_WAYS;
localparam NUM_SETS      = `TLB_NUM_SETS;
localparam SET_IDX_W     = `TLB_SET_IDX_WIDTH;
localparam WAY_W         = `TLB_WAY_WIDTH;
localparam FLAG_ENTRY_W  = `TLB_FLAG_ENTRY_WIDTH;
localparam DATA_ENTRY_W  = `TLB_DATA_ENTRY_WIDTH;

// --- State machine ---
localparam S_IDLE   = 3'd0;
localparam S_LOOKUP = 3'd1;
localparam S_FLUSH  = 3'd2;

reg [2:0] state;

// --- Set index: upper VPN bits only (no VPN[1:0]) ---
// This ensures all VPNs within a megapage (which differ only in VPN[1:0])
// map to the same set, so megapage entries don't need replication.
wire [SET_IDX_W-1:0] lookup_set_idx = lookup_vpn[SET_IDX_W+9:10];
wire [SET_IDX_W-1:0] fill_set_idx   = fill_vpn[SET_IDX_W+9:10];

// --- Latched lookup values (for comparison in S_LOOKUP) ---
reg [19:0]      latched_vpn;
reg [8:0]       latched_asid;
reg [SET_IDX_W-1:0] latched_set_idx;

// --- PLRU state per set ---
reg [NUM_WAYS-2:0] plru_state [0:NUM_SETS-1];

// --- Shadow valid bits (for victim way selection during fill) ---
reg valid_shadow [0:NUM_SETS-1][0:NUM_WAYS-1];

// --- Flush counter ---
reg [SET_IDX_W-1:0] flush_set;
reg flush_done_r;

// =========================================================================
// Flag BRAM (tlb_flag) — 128-bit x 4 deep, Byte_Size=32, 4-bit WEA
// Per-way flag entry (32 bits): {V(1), G(1), ASID(9), VPN(20), mega(1)}
// =========================================================================
wire [`TLB_FLAG_BRAM_WIDTH-1:0] flag_bram_douta;
wire [`TLB_FLAG_BRAM_WIDTH-1:0] flag_bram_doutb;

wire        flag_bram_ena   = (state == S_IDLE) && lookup_req && !flush_all;
wire [SET_IDX_W-1:0] flag_bram_addra = lookup_set_idx;

reg                                flag_bram_enb_r;
reg [`TLB_FLAG_BRAM_WEA_WIDTH-1:0] flag_bram_web_r;
reg [SET_IDX_W-1:0]               flag_bram_addrb_r;
reg [`TLB_FLAG_BRAM_WIDTH-1:0]     flag_bram_dinb_r;

tlb_flag u_tlb_flag(
    .clka   (clk),
    .ena    (flag_bram_ena),
    .wea    ({`TLB_FLAG_BRAM_WEA_WIDTH{1'b0}}),
    .addra  (flag_bram_addra),
    .dina   ({`TLB_FLAG_BRAM_WIDTH{1'b0}}),
    .douta  (flag_bram_douta),

    .clkb   (clk),
    .enb    (flag_bram_enb_r),
    .web    (flag_bram_web_r),
    .addrb  (flag_bram_addrb_r),
    .dinb   (flag_bram_dinb_r),
    .doutb  (flag_bram_doutb)
);

// =========================================================================
// Data BRAM (tlb_data) — 128-bit x 4 deep, Byte_Size=32, 4-bit WEA
// Per-way data entry (32 bits): {PPN(22), R(1), W(1), X(1), U(1), A(1), D(1), pad(4)}
// =========================================================================
wire [`TLB_DATA_BRAM_WIDTH-1:0] data_bram_douta;
wire [`TLB_DATA_BRAM_WIDTH-1:0] data_bram_doutb;

wire        data_bram_ena   = (state == S_IDLE) && lookup_req && !flush_all;
wire [SET_IDX_W-1:0] data_bram_addra = lookup_set_idx;

reg                                data_bram_enb_r;
reg [`TLB_DATA_BRAM_WEA_WIDTH-1:0] data_bram_web_r;
reg [SET_IDX_W-1:0]               data_bram_addrb_r;
reg [`TLB_DATA_BRAM_WIDTH-1:0]     data_bram_dinb_r;

tlb_data u_tlb_data(
    .clka   (clk),
    .ena    (data_bram_ena),
    .wea    ({`TLB_DATA_BRAM_WEA_WIDTH{1'b0}}),
    .addra  (data_bram_addra),
    .dina   ({`TLB_DATA_BRAM_WIDTH{1'b0}}),
    .douta  (data_bram_douta),

    .clkb   (clk),
    .enb    (data_bram_enb_r),
    .web    (data_bram_web_r),
    .addrb  (data_bram_addrb_r),
    .dinb   (data_bram_dinb_r),
    .doutb  (data_bram_doutb)
);

// =========================================================================
// 4-way parallel match (in S_LOOKUP, BRAM output valid)
// =========================================================================

// Extract per-way flag entries from BRAM Port A output
wire [FLAG_ENTRY_W-1:0] flag_r0 = flag_bram_douta[FLAG_ENTRY_W*1-1:FLAG_ENTRY_W*0];
wire [FLAG_ENTRY_W-1:0] flag_r1 = flag_bram_douta[FLAG_ENTRY_W*2-1:FLAG_ENTRY_W*1];
wire [FLAG_ENTRY_W-1:0] flag_r2 = flag_bram_douta[FLAG_ENTRY_W*3-1:FLAG_ENTRY_W*2];
wire [FLAG_ENTRY_W-1:0] flag_r3 = flag_bram_douta[FLAG_ENTRY_W*4-1:FLAG_ENTRY_W*3];

// Extract per-way data entries from BRAM Port A output
wire [DATA_ENTRY_W-1:0] data_r0 = data_bram_douta[DATA_ENTRY_W*1-1:DATA_ENTRY_W*0];
wire [DATA_ENTRY_W-1:0] data_r1 = data_bram_douta[DATA_ENTRY_W*2-1:DATA_ENTRY_W*1];
wire [DATA_ENTRY_W-1:0] data_r2 = data_bram_douta[DATA_ENTRY_W*3-1:DATA_ENTRY_W*2];
wire [DATA_ENTRY_W-1:0] data_r3 = data_bram_douta[DATA_ENTRY_W*4-1:DATA_ENTRY_W*3];

// Flag entry layout: [31]=V, [30]=G, [29:21]=ASID, [20:1]=VPN, [0]=mega
wire valid0  = flag_r0[31], valid1  = flag_r1[31],
     valid2  = flag_r2[31], valid3  = flag_r3[31];
wire global0 = flag_r0[30], global1 = flag_r1[30],
     global2 = flag_r2[30], global3 = flag_r3[30];
wire [8:0]  asid0 = flag_r0[29:21], asid1 = flag_r1[29:21],
            asid2 = flag_r2[29:21], asid3 = flag_r3[29:21];
wire [19:0] vpn0  = flag_r0[20:1],  vpn1  = flag_r1[20:1],
            vpn2  = flag_r2[20:1],  vpn3  = flag_r3[20:1];
wire mega0  = flag_r0[0],  mega1  = flag_r1[0],
     mega2  = flag_r2[0],  mega3  = flag_r3[0];

// VPN match (megapage: only compare VPN[19:10])
wire vpn_match0 = mega0 ? (vpn0[19:10] == latched_vpn[19:10]) : (vpn0 == latched_vpn);
wire vpn_match1 = mega1 ? (vpn1[19:10] == latched_vpn[19:10]) : (vpn1 == latched_vpn);
wire vpn_match2 = mega2 ? (vpn2[19:10] == latched_vpn[19:10]) : (vpn2 == latched_vpn);
wire vpn_match3 = mega3 ? (vpn3[19:10] == latched_vpn[19:10]) : (vpn3 == latched_vpn);

// Hit vector
wire hit0 = valid0 && vpn_match0 && (global0 || (asid0 == latched_asid));
wire hit1 = valid1 && vpn_match1 && (global1 || (asid1 == latched_asid));
wire hit2 = valid2 && vpn_match2 && (global2 || (asid2 == latched_asid));
wire hit3 = valid3 && vpn_match3 && (global3 || (asid3 == latched_asid));

wire tlb_hit = hit0 | hit1 | hit2 | hit3;
assign lookup_hit = tlb_hit;

// Hit way encoding
wire [WAY_W-1:0] hit_way = hit0 ? 2'd0 :
                           hit1 ? 2'd1 :
                           hit2 ? 2'd2 : 2'd3;

// Output mux: select hit way's flag and data entries
wire [FLAG_ENTRY_W-1:0] hit_flag = hit0 ? flag_r0 :
                                  hit1 ? flag_r1 :
                                  hit2 ? flag_r2 : flag_r3;

wire [DATA_ENTRY_W-1:0] hit_data = hit0 ? data_r0 :
                                   hit1 ? data_r1 :
                                   hit2 ? data_r2 : data_r3;

// Data entry layout: [31:10]=PPN, [9]=R, [8]=W, [7]=X, [6]=U, [5]=A, [4]=D, [3:0]=pad
assign lookup_ppn         = hit_data[31:10];
assign lookup_r           = hit_data[9];
assign lookup_w           = hit_data[8];
assign lookup_x           = hit_data[7];
assign lookup_u           = hit_data[6];
assign lookup_a           = hit_data[5];
assign lookup_d           = hit_data[4];
assign lookup_g           = hit_flag[30];
assign lookup_is_megapage = hit_flag[0];

assign lookup_valid = (state == S_LOOKUP);
assign flush_done   = flush_done_r;

// =========================================================================
// PLRU for lookup hit
// =========================================================================
wire [WAY_W-1:0]      plru_victim_lookup;
wire [NUM_WAYS-2:0]   plru_next_lookup;
tree_plru u_plru_lookup(
    .plru_state (plru_state[latched_set_idx]),
    .victim_way (plru_victim_lookup),
    .access_way (hit_way),
    .next_state (plru_next_lookup)
);

// =========================================================================
// Fill victim way selection
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
// State machine
// =========================================================================
integer i;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state            <= S_IDLE;
        latched_vpn      <= 20'b0;
        latched_asid     <= 9'b0;
        latched_set_idx  <= {SET_IDX_W{1'b0}};
        flush_set        <= {SET_IDX_W{1'b0}};
        flush_done_r     <= 1'b0;
        flag_bram_enb_r  <= 1'b0;
        flag_bram_web_r  <= {`TLB_FLAG_BRAM_WEA_WIDTH{1'b0}};
        flag_bram_addrb_r <= {SET_IDX_W{1'b0}};
        flag_bram_dinb_r <= {`TLB_FLAG_BRAM_WIDTH{1'b0}};
        data_bram_enb_r  <= 1'b0;
        data_bram_web_r  <= {`TLB_DATA_BRAM_WEA_WIDTH{1'b0}};
        data_bram_addrb_r <= {SET_IDX_W{1'b0}};
        data_bram_dinb_r <= {`TLB_DATA_BRAM_WIDTH{1'b0}};
        for (i = 0; i < NUM_SETS; i = i + 1) begin
            plru_state[i] <= {NUM_WAYS-1{1'b0}};
            for (integer w = 0; w < NUM_WAYS; w = w + 1)
                valid_shadow[i][w] <= 1'b0;
        end
    end else begin
        flush_done_r    <= 1'b0;
        flag_bram_enb_r <= 1'b0;
        data_bram_enb_r <= 1'b0;

        case (state)
            S_IDLE: begin
                if (flush_all) begin
                    state     <= S_FLUSH;
                    flush_set <= {SET_IDX_W{1'b0}};
                end else begin
                    // Fill logic (Port B write, independent of Port A)
                    if (fill_req) begin
                        flag_bram_enb_r   <= 1'b1;
                        flag_bram_web_r   <= ({{(`TLB_FLAG_BRAM_WEA_WIDTH-4){1'b0}}, 4'hF} << ({fill_victim_way, 2'b0}));
                        flag_bram_addrb_r <= fill_set_idx;
                        flag_bram_dinb_r  <= fill_flag_din;
                        data_bram_enb_r   <= 1'b1;
                        data_bram_web_r   <= ({{(`TLB_DATA_BRAM_WEA_WIDTH-4){1'b0}}, 4'hF} << ({fill_victim_way, 2'b0}));
                        data_bram_addrb_r <= fill_set_idx;
                        data_bram_dinb_r  <= fill_data_din;
                        valid_shadow[fill_set_idx][fill_victim_way] <= 1'b1;
                        plru_state[fill_set_idx] <= plru_next_fill;
                    end
                    // Start lookup
                    if (lookup_req) begin
                        latched_vpn     <= lookup_vpn;
                        latched_asid    <= lookup_asid;
                        latched_set_idx <= lookup_set_idx;
                        state           <= S_LOOKUP;
                    end
                end
            end

            S_LOOKUP: begin
                if (flush_all) begin
                    // Abort lookup, start flush
                    state     <= S_FLUSH;
                    flush_set <= {SET_IDX_W{1'b0}};
                end else begin
                    // Fill logic (Port B write, independent of Port A)
                    if (fill_req) begin
                        flag_bram_enb_r   <= 1'b1;
                        flag_bram_web_r   <= ({{(`TLB_FLAG_BRAM_WEA_WIDTH-4){1'b0}}, 4'hF} << ({fill_victim_way, 2'b0}));
                        flag_bram_addrb_r <= fill_set_idx;
                        flag_bram_dinb_r  <= fill_flag_din;
                        data_bram_enb_r   <= 1'b1;
                        data_bram_web_r   <= ({{(`TLB_DATA_BRAM_WEA_WIDTH-4){1'b0}}, 4'hF} << ({fill_victim_way, 2'b0}));
                        data_bram_addrb_r <= fill_set_idx;
                        data_bram_dinb_r  <= fill_data_din;
                        valid_shadow[fill_set_idx][fill_victim_way] <= 1'b1;
                        plru_state[fill_set_idx] <= plru_next_fill;
                    end
                    // BRAM output valid, update PLRU on hit
                    if (tlb_hit) begin
                        plru_state[latched_set_idx] <= plru_next_lookup;
                    end
                    state <= S_IDLE;
                end
            end

            S_FLUSH: begin
                // Write all zeros to Flag BRAM Port B for flush_set
                flag_bram_enb_r   <= 1'b1;
                flag_bram_web_r   <= {`TLB_FLAG_BRAM_WEA_WIDTH{1'b1}};
                flag_bram_addrb_r <= flush_set;
                flag_bram_dinb_r  <= {`TLB_FLAG_BRAM_WIDTH{1'b0}};

                // Clear shadow valid bits for this set
                for (i = 0; i < NUM_WAYS; i = i + 1)
                    valid_shadow[flush_set][i] <= 1'b0;

                if (flush_set == NUM_SETS - 1) begin
                    for (i = 0; i < NUM_SETS; i = i + 1)
                        plru_state[i] <= {NUM_WAYS-1{1'b0}};
                    flush_done_r <= 1'b1;
                    state <= S_IDLE;
                end else begin
                    flush_set <= flush_set + 1'b1;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

`else // !USE_TLB_BRAM

// =========================================================================
// Original fully-associative register array implementation
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

    wire [ENTRIES-1:0] hit_vec;
    generate
        for (gi = 0; gi < ENTRIES; gi = gi + 1) begin : gen_cmp
            wire valid_i  = e_out[gi][ENTRY_W-1];
            wire global_i = e_out[gi][ENTRY_W-2];
            wire [8:0]  asid_i  = e_out[gi][ENTRY_W-3 -: 9];
            wire [19:0] vpn_i   = e_out[gi][ENTRY_W-12 -: 20];
            wire        mega_i  = e_out[gi][0];
            // megapage: only match VPN[1] (upper 10 bits), VPN[0] is page offset
            wire vpn_match_i = mega_i ? (vpn_i[19:10] == lookup_vpn[19:10])
                                      : (vpn_i == lookup_vpn);
            assign hit_vec[gi] = valid_i && vpn_match_i &&
                                 (global_i || (asid_i == lookup_asid));
        end
    endgenerate

    assign lookup_hit = |hit_vec;

    reg [21:0] hit_ppn_r;
    reg        hit_r_r, hit_w_r, hit_x_r, hit_u_r;
    reg        hit_a_r, hit_d_r, hit_g_r;
    reg        hit_mega_r;

    integer i;
    always @(*) begin
        hit_ppn_r  = 22'b0;
        hit_r_r    = 1'b0;
        hit_w_r    = 1'b0;
        hit_x_r    = 1'b0;
        hit_u_r    = 1'b0;
        hit_a_r    = 1'b0;
        hit_d_r    = 1'b0;
        hit_g_r    = 1'b0;
        hit_mega_r = 1'b0;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (hit_vec[i]) begin
                hit_ppn_r  = e_out[i][28:7];
                hit_r_r    = e_out[i][6];
                hit_w_r    = e_out[i][5];
                hit_x_r    = e_out[i][4];
                hit_u_r    = e_out[i][3];
                hit_a_r    = e_out[i][2];
                hit_d_r    = e_out[i][1];
                hit_g_r    = e_out[i][ENTRY_W-2];
                hit_mega_r = e_out[i][0];
            end
        end
    end

    assign lookup_ppn         = hit_ppn_r;
    assign lookup_r           = hit_r_r;
    assign lookup_w           = hit_w_r;
    assign lookup_x           = hit_x_r;
    assign lookup_u           = hit_u_r;
    assign lookup_a           = hit_a_r;
    assign lookup_d           = hit_d_r;
    assign lookup_g           = hit_g_r;
    assign lookup_is_megapage = hit_mega_r;

    // Non-BRAM: lookup is combinational, always valid
    assign lookup_valid = 1'b1;
    assign flush_done   = 1'b1;

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

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rr_ptr <= '0;
            for (i = 0; i < ENTRIES; i = i + 1)
                entries[i] <= '0;
        end else begin
            if (flush_all) begin
                for (i = 0; i < ENTRIES; i = i + 1)
                    entries[i][ENTRY_W-1] <= 1'b0;
            end else if (fill_req) begin
                // megapage: normalize VPN[0] to zero (only VPN[1] matters for matching)
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
