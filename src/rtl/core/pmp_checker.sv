`timescale 1ns / 1ps
`include "axi4_def.svh"
`include "core_bus_types.svh"

// Combinational 16-entry base-PMP matcher.  The first entry overlapping any
// byte of the operation wins; partial coverage therefore denies the access.
module pmp_checker(
    input      [31:0] paddr,
    input      [2:0]  access_size,
    input access_class_t access_type,
    input priv_mode_t effective_priv,
    input      [127:0] pmpcfg_flat,
    input      [511:0] pmpaddr_flat,
    output reg         allow
);
    integer i;
    integer j;
    integer trailing_ones;
    reg counting_ones;
    reg found;
    reg valid_size;
    reg [7:0] cfg;
    reg [31:0] entry_addr;
    reg [31:0] previous_addr;
    reg [34:0] access_start;
    reg [34:0] access_end;
    reg [34:0] access_bytes;
    reg [34:0] raw_addr;
    reg [34:0] region_start;
    reg [34:0] region_end;
    reg [34:0] region_size;
    reg overlap;
    reg full_match;
    reg permission;

    always_comb begin
        valid_size = (access_size <= `AXI_SIZE_WORD);
        access_bytes = 35'd1 << access_size;
        access_start = {3'b000, paddr};
        access_end = access_start + access_bytes;
        allow = (effective_priv == PRIV_M);
        found = 1'b0;
        previous_addr = 32'b0;

        for (i = 0; i < 16; i = i + 1) begin
            cfg = pmpcfg_flat[i*8 +: 8];
            entry_addr = pmpaddr_flat[i*32 +: 32];
            raw_addr = {1'b0, entry_addr, 2'b00};
            region_start = 35'b0;
            region_end = 35'b0;
            region_size = 35'b0;

            case (cfg[4:3])
                2'b01: begin // TOR
                    region_start = {1'b0, previous_addr, 2'b00};
                    region_end = raw_addr;
                end
                2'b10: begin // NA4
                    region_start = raw_addr;
                    region_end = raw_addr + 35'd4;
                end
                2'b11: begin // NAPOT
                    trailing_ones = 0;
                    counting_ones = 1'b1;
                    for (j = 0; j < 32; j = j + 1) begin
                        if (counting_ones && entry_addr[j])
                            trailing_ones = trailing_ones + 1;
                        else
                            counting_ones = 1'b0;
                    end
                    if (trailing_ones == 32) begin
                        region_start = 35'b0;
                        // Saturation is above every 32-bit CPU access.
                        region_end = {35{1'b1}};
                    end else begin
                        region_size = 35'd1 << (trailing_ones + 3);
                        region_start = raw_addr & ~(region_size - 35'd1);
                        region_end = region_start + region_size;
                    end
                end
                default: begin // OFF
                    region_start = 35'b0;
                    region_end = 35'b0;
                end
            endcase

            overlap = valid_size && (cfg[4:3] != 2'b00) &&
                      (region_start < region_end) &&
                      (access_start < region_end) &&
                      (access_end > region_start);
            full_match = (access_start >= region_start) &&
                         (access_end <= region_end);
            permission = (access_type == ACCESS_FETCH) ? cfg[2] :
                         (access_type == ACCESS_LOAD)  ? cfg[0] : cfg[1];

            if (!found && overlap) begin
                found = 1'b1;
                if (!full_match)
                    allow = 1'b0;
                else if ((effective_priv == PRIV_M) && !cfg[7])
                    allow = 1'b1;
                else
                    allow = permission;
            end
            previous_addr = entry_addr;
        end

        if (!valid_size)
            allow = 1'b0;
    end
endmodule
