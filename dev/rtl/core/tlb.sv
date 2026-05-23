`timescale 1ns / 1ps

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

    input              flush_all
);

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
            assign hit_vec[gi] = valid_i && (vpn_i == lookup_vpn) &&
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
                entries[rr_ptr] <= pack_entry(
                    1'b1, fill_g, fill_asid, fill_vpn, fill_ppn,
                    fill_r, fill_w, fill_x, fill_u, fill_a, fill_d, fill_is_megapage);
                rr_ptr <= rr_ptr + 1'b1;
            end
        end
    end

endmodule
