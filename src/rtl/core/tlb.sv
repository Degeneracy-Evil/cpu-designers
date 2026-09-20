`timescale 1ns / 1ps

// Small unified Sv32 TLB. All entries are ordinary registers and lookup is
// fully associative. There is one lookup port because the in-order core only
// performs one architectural translation at a time.
module tlb #(
    parameter ENTRIES = 16
)(
    input              clk,
    input              resetn,

    input  [19:0]      lookup_vpn,
    input  [8:0]       lookup_asid,
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
    localparam INDEX_W = $clog2(ENTRIES);

    reg                valid_mem [0:ENTRIES-1];
    reg [19:0]         vpn_mem   [0:ENTRIES-1];
    reg [8:0]          asid_mem  [0:ENTRIES-1];
    reg [21:0]         ppn_mem   [0:ENTRIES-1];
    // {R, W, X, U, A, D, G, megapage}
    reg [7:0]          attr_mem  [0:ENTRIES-1];
    reg [INDEX_W-1:0]  victim_r;
    reg                flush_done_r;

    reg                hit_r;
    reg [INDEX_W-1:0]  hit_index_r;
    reg                fill_match_r;
    reg [INDEX_W-1:0]  fill_match_index_r;
    reg                invalid_found_r;
    reg [INDEX_W-1:0]  invalid_index_r;

    wire [19:0] normalized_fill_vpn = fill_is_megapage ?
                                      {fill_vpn[19:10], 10'b0} : fill_vpn;
    wire [7:0] fill_attr = {fill_r, fill_w, fill_x, fill_u,
                            fill_a, fill_d, fill_g, fill_is_megapage};
    wire [INDEX_W-1:0] fill_index = fill_match_r ? fill_match_index_r :
                                    invalid_found_r ? invalid_index_r : victim_r;

    integer lookup_idx;
    always_comb begin
        hit_r = 1'b0;
        hit_index_r = {INDEX_W{1'b0}};
        fill_match_r = 1'b0;
        fill_match_index_r = {INDEX_W{1'b0}};
        invalid_found_r = 1'b0;
        invalid_index_r = {INDEX_W{1'b0}};

        for (lookup_idx = 0; lookup_idx < ENTRIES; lookup_idx = lookup_idx + 1) begin
            if (!hit_r && valid_mem[lookup_idx] &&
                (attr_mem[lookup_idx][0] ?
                    (vpn_mem[lookup_idx][19:10] == lookup_vpn[19:10]) :
                    (vpn_mem[lookup_idx] == lookup_vpn)) &&
                (attr_mem[lookup_idx][1] ||
                    (asid_mem[lookup_idx] == lookup_asid))) begin
                hit_r = 1'b1;
                hit_index_r = lookup_idx[INDEX_W-1:0];
            end

            // Refill an existing mapping in place. This matters when a store
            // walks again solely to set the D bit.
            if (!fill_match_r && valid_mem[lookup_idx] &&
                (attr_mem[lookup_idx][0] == fill_is_megapage) &&
                (vpn_mem[lookup_idx] == normalized_fill_vpn) &&
                ((attr_mem[lookup_idx][1] && fill_g) ||
                    (!attr_mem[lookup_idx][1] && !fill_g &&
                     (asid_mem[lookup_idx] == fill_asid)))) begin
                fill_match_r = 1'b1;
                fill_match_index_r = lookup_idx[INDEX_W-1:0];
            end

            if (!invalid_found_r && !valid_mem[lookup_idx]) begin
                invalid_found_r = 1'b1;
                invalid_index_r = lookup_idx[INDEX_W-1:0];
            end
        end
    end

    wire [7:0] hit_attr = attr_mem[hit_index_r];

    assign lookup_hit = hit_r;
    assign lookup_ppn = hit_r ? ppn_mem[hit_index_r] : 22'b0;
    assign lookup_r = hit_r && hit_attr[7];
    assign lookup_w = hit_r && hit_attr[6];
    assign lookup_x = hit_r && hit_attr[5];
    assign lookup_u = hit_r && hit_attr[4];
    assign lookup_a = hit_r && hit_attr[3];
    assign lookup_d = hit_r && hit_attr[2];
    assign lookup_g = hit_r && hit_attr[1];
    assign lookup_is_megapage = hit_r && hit_attr[0];
    assign flush_done = flush_done_r;

    integer entry_idx;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            victim_r <= {INDEX_W{1'b0}};
            flush_done_r <= 1'b0;
            for (entry_idx = 0; entry_idx < ENTRIES; entry_idx = entry_idx + 1) begin
                valid_mem[entry_idx] <= 1'b0;
                vpn_mem[entry_idx] <= 20'b0;
                asid_mem[entry_idx] <= 9'b0;
                ppn_mem[entry_idx] <= 22'b0;
                attr_mem[entry_idx] <= 8'b0;
            end
        end else begin
            flush_done_r <= 1'b0;

            if (flush_all) begin
                for (entry_idx = 0; entry_idx < ENTRIES; entry_idx = entry_idx + 1)
                    valid_mem[entry_idx] <= 1'b0;
                victim_r <= {INDEX_W{1'b0}};
                flush_done_r <= 1'b1;
            end else if (fill_req) begin
                valid_mem[fill_index] <= 1'b1;
                vpn_mem[fill_index] <= normalized_fill_vpn;
                asid_mem[fill_index] <= fill_asid;
                ppn_mem[fill_index] <= fill_ppn;
                attr_mem[fill_index] <= fill_attr;

                if (fill_index == ENTRIES-1)
                    victim_r <= {INDEX_W{1'b0}};
                else
                    victim_r <= fill_index + 1'b1;
            end
        end
    end
endmodule
