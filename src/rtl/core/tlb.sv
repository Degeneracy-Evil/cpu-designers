`timescale 1ns / 1ps

module tlb #(
    parameter ENTRIES = 16
)(
    input              clk,
    input              resetn,

    // Instruction-side lookup
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

    // Data-side lookup
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

    // PTW fill. ITLB and DTLB are independent 16-entry banks.
    input              fill_req,
    input              fill_is_instruction,
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
    localparam NUM_WAYS  = 2;
    localparam NUM_SETS  = ENTRIES / NUM_WAYS;
    localparam SET_IDX_W = $clog2(NUM_SETS);

    // Index with VPN[12:10]. VPN[9:0] must not participate because all 4 KiB
    // pages covered by one Sv32 megapage need to find the same entry.
    wire [SET_IDX_W-1:0] i_set = i_lookup_vpn[SET_IDX_W+9:10];
    wire [SET_IDX_W-1:0] d_set = d_lookup_vpn[SET_IDX_W+9:10];
    wire [SET_IDX_W-1:0] fill_set = fill_vpn[SET_IDX_W+9:10];

    reg                  i_valid_mem [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [19:0]           i_vpn_mem   [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [8:0]            i_asid_mem  [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [21:0]           i_ppn_mem   [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [7:0]            i_attr_mem  [0:NUM_SETS-1][0:NUM_WAYS-1];

    reg                  d_valid_mem [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [19:0]           d_vpn_mem   [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [8:0]            d_asid_mem  [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [21:0]           d_ppn_mem   [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [7:0]            d_attr_mem  [0:NUM_SETS-1][0:NUM_WAYS-1];

    // attr = {R, W, X, U, A, D, G, megapage}
    reg i_victim [0:NUM_SETS-1];
    reg d_victim [0:NUM_SETS-1];

    reg [19:0] i_vpn_r;
    reg [8:0]  i_asid_r;
    reg [SET_IDX_W-1:0] i_set_r;
    reg [19:0] d_vpn_r;
    reg [8:0]  d_asid_r;
    reg [SET_IDX_W-1:0] d_set_r;
    reg i_lookup_valid_r;
    reg d_lookup_valid_r;
    reg flush_done_r;

    wire i_vpn_match0 = i_attr_mem[i_set_r][0][0] ?
                        (i_vpn_mem[i_set_r][0][19:10] == i_vpn_r[19:10]) :
                        (i_vpn_mem[i_set_r][0] == i_vpn_r);
    wire i_vpn_match1 = i_attr_mem[i_set_r][1][0] ?
                        (i_vpn_mem[i_set_r][1][19:10] == i_vpn_r[19:10]) :
                        (i_vpn_mem[i_set_r][1] == i_vpn_r);
    wire i_hit0 = i_valid_mem[i_set_r][0] && i_vpn_match0 &&
                  (i_attr_mem[i_set_r][0][1] || (i_asid_mem[i_set_r][0] == i_asid_r));
    wire i_hit1 = i_valid_mem[i_set_r][1] && i_vpn_match1 &&
                  (i_attr_mem[i_set_r][1][1] || (i_asid_mem[i_set_r][1] == i_asid_r));
    wire i_hit_way = i_hit1;
    wire [7:0] i_hit_attr = i_attr_mem[i_set_r][i_hit_way];

    wire d_vpn_match0 = d_attr_mem[d_set_r][0][0] ?
                        (d_vpn_mem[d_set_r][0][19:10] == d_vpn_r[19:10]) :
                        (d_vpn_mem[d_set_r][0] == d_vpn_r);
    wire d_vpn_match1 = d_attr_mem[d_set_r][1][0] ?
                        (d_vpn_mem[d_set_r][1][19:10] == d_vpn_r[19:10]) :
                        (d_vpn_mem[d_set_r][1] == d_vpn_r);
    wire d_hit0 = d_valid_mem[d_set_r][0] && d_vpn_match0 &&
                  (d_attr_mem[d_set_r][0][1] || (d_asid_mem[d_set_r][0] == d_asid_r));
    wire d_hit1 = d_valid_mem[d_set_r][1] && d_vpn_match1 &&
                  (d_attr_mem[d_set_r][1][1] || (d_asid_mem[d_set_r][1] == d_asid_r));
    wire d_hit_way = d_hit1;
    wire [7:0] d_hit_attr = d_attr_mem[d_set_r][d_hit_way];

    assign i_lookup_hit = i_lookup_valid_r && (i_hit0 || i_hit1);
    assign i_lookup_ppn = i_ppn_mem[i_set_r][i_hit_way];
    assign i_lookup_r = i_hit_attr[7];
    assign i_lookup_w = i_hit_attr[6];
    assign i_lookup_x = i_hit_attr[5];
    assign i_lookup_u = i_hit_attr[4];
    assign i_lookup_a = i_hit_attr[3];
    assign i_lookup_d = i_hit_attr[2];
    assign i_lookup_g = i_hit_attr[1];
    assign i_lookup_is_megapage = i_hit_attr[0];
    assign i_lookup_valid = i_lookup_valid_r;

    assign d_lookup_hit = d_lookup_valid_r && (d_hit0 || d_hit1);
    assign d_lookup_ppn = d_ppn_mem[d_set_r][d_hit_way];
    assign d_lookup_r = d_hit_attr[7];
    assign d_lookup_w = d_hit_attr[6];
    assign d_lookup_x = d_hit_attr[5];
    assign d_lookup_u = d_hit_attr[4];
    assign d_lookup_a = d_hit_attr[3];
    assign d_lookup_d = d_hit_attr[2];
    assign d_lookup_g = d_hit_attr[1];
    assign d_lookup_is_megapage = d_hit_attr[0];
    assign d_lookup_valid = d_lookup_valid_r;
    assign flush_done = flush_done_r;

    wire i_fill_way = !i_valid_mem[fill_set][0] ? 1'b0 :
                      !i_valid_mem[fill_set][1] ? 1'b1 : i_victim[fill_set];
    wire d_fill_way = !d_valid_mem[fill_set][0] ? 1'b0 :
                      !d_valid_mem[fill_set][1] ? 1'b1 : d_victim[fill_set];
    wire [19:0] normalized_fill_vpn = fill_is_megapage ?
                                      {fill_vpn[19:10], 10'b0} : fill_vpn;
    wire [7:0] fill_attr = {fill_r, fill_w, fill_x, fill_u,
                            fill_a, fill_d, fill_g, fill_is_megapage};

    integer set_idx;
    integer way_idx;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            i_vpn_r <= 20'b0;
            i_asid_r <= 9'b0;
            i_set_r <= {SET_IDX_W{1'b0}};
            d_vpn_r <= 20'b0;
            d_asid_r <= 9'b0;
            d_set_r <= {SET_IDX_W{1'b0}};
            i_lookup_valid_r <= 1'b0;
            d_lookup_valid_r <= 1'b0;
            flush_done_r <= 1'b0;
            for (set_idx = 0; set_idx < NUM_SETS; set_idx = set_idx + 1) begin
                i_victim[set_idx] <= 1'b0;
                d_victim[set_idx] <= 1'b0;
                for (way_idx = 0; way_idx < NUM_WAYS; way_idx = way_idx + 1) begin
                    i_valid_mem[set_idx][way_idx] <= 1'b0;
                    d_valid_mem[set_idx][way_idx] <= 1'b0;
                    i_vpn_mem[set_idx][way_idx] <= 20'b0;
                    d_vpn_mem[set_idx][way_idx] <= 20'b0;
                    i_asid_mem[set_idx][way_idx] <= 9'b0;
                    d_asid_mem[set_idx][way_idx] <= 9'b0;
                    i_ppn_mem[set_idx][way_idx] <= 22'b0;
                    d_ppn_mem[set_idx][way_idx] <= 22'b0;
                    i_attr_mem[set_idx][way_idx] <= 8'b0;
                    d_attr_mem[set_idx][way_idx] <= 8'b0;
                end
            end
        end else begin
            flush_done_r <= 1'b0;
            i_lookup_valid_r <= i_lookup_req && !flush_all;
            d_lookup_valid_r <= d_lookup_req && !flush_all;

            if (i_lookup_req && !flush_all) begin
                i_vpn_r <= i_lookup_vpn;
                i_asid_r <= i_lookup_asid;
                i_set_r <= i_set;
            end
            if (d_lookup_req && !flush_all) begin
                d_vpn_r <= d_lookup_vpn;
                d_asid_r <= d_lookup_asid;
                d_set_r <= d_set;
            end

            if (flush_all) begin
                for (set_idx = 0; set_idx < NUM_SETS; set_idx = set_idx + 1) begin
                    i_victim[set_idx] <= 1'b0;
                    d_victim[set_idx] <= 1'b0;
                    for (way_idx = 0; way_idx < NUM_WAYS; way_idx = way_idx + 1) begin
                        i_valid_mem[set_idx][way_idx] <= 1'b0;
                        d_valid_mem[set_idx][way_idx] <= 1'b0;
                    end
                end
                flush_done_r <= 1'b1;
            end else begin
                if (fill_req && fill_is_instruction) begin
                    i_valid_mem[fill_set][i_fill_way] <= 1'b1;
                    i_vpn_mem[fill_set][i_fill_way] <= normalized_fill_vpn;
                    i_asid_mem[fill_set][i_fill_way] <= fill_asid;
                    i_ppn_mem[fill_set][i_fill_way] <= fill_ppn;
                    i_attr_mem[fill_set][i_fill_way] <= fill_attr;
                    i_victim[fill_set] <= ~i_fill_way;
                end else if (i_lookup_valid_r && i_lookup_hit) begin
                    i_victim[i_set_r] <= ~i_hit_way;
                end

                if (fill_req && !fill_is_instruction) begin
                    d_valid_mem[fill_set][d_fill_way] <= 1'b1;
                    d_vpn_mem[fill_set][d_fill_way] <= normalized_fill_vpn;
                    d_asid_mem[fill_set][d_fill_way] <= fill_asid;
                    d_ppn_mem[fill_set][d_fill_way] <= fill_ppn;
                    d_attr_mem[fill_set][d_fill_way] <= fill_attr;
                    d_victim[fill_set] <= ~d_fill_way;
                end else if (d_lookup_valid_r && d_lookup_hit) begin
                    d_victim[d_set_r] <= ~d_hit_way;
                end
            end
        end
    end
endmodule
