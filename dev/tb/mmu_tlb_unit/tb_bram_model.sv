`timescale 1ns / 1ps
// =========================================================================
// Behavioral BRAM models for TLB unit testing
// Replaces Xilinx IP cores tlb_flag / tlb_data with simple dual-port BRAM
// 
// Interface matches Xilinx BRAM IP generated for this project:
//   - 128-bit width, 4 entries, 2-bit address, 16-bit byte-write enable
//   - Registered output (1-cycle read latency)
//   - READ_FIRST behavior (read returns old data before write)
// =========================================================================

module tlb_flag(
    input         clka,
    input         ena,
    input  [15:0] wea,
    input  [1:0]  addra,
    input  [127:0] dina,
    output reg [127:0] douta,

    input         clkb,
    input         enb,
    input  [15:0] web,
    input  [1:0]  addrb,
    input  [127:0] dinb,
    output reg [127:0] doutb
);
    reg [127:0] mem [0:3];

    integer i;
    initial begin
        for (i = 0; i < 4; i = i + 1)
            mem[i] = 128'b0;
        douta = 128'b0;
        doutb = 128'b0;
    end

    // Single always block (clka == clkb == clk in this design)
    always @(posedge clka) begin
        // Port A: read-only (wea always 0 in TLB design)
        if (ena)
            douta <= mem[addra];

        // Port B: read + byte-write
        if (enb) begin
            doutb <= mem[addrb];  // READ_FIRST: old data
            for (i = 0; i < 16; i = i + 1) begin
                if (web[i])
                    mem[addrb][i*8 +: 8] <= dinb[i*8 +: 8];
            end
        end
    end
endmodule


module tlb_data(
    input         clka,
    input         ena,
    input  [15:0] wea,
    input  [1:0]  addra,
    input  [127:0] dina,
    output reg [127:0] douta,

    input         clkb,
    input         enb,
    input  [15:0] web,
    input  [1:0]  addrb,
    input  [127:0] dinb,
    output reg [127:0] doutb
);
    reg [127:0] mem [0:3];

    integer i;
    initial begin
        for (i = 0; i < 4; i = i + 1)
            mem[i] = 128'b0;
        douta = 128'b0;
        doutb = 128'b0;
    end

    always @(posedge clka) begin
        if (ena)
            douta <= mem[addra];

        if (enb) begin
            doutb <= mem[addrb];
            for (i = 0; i < 16; i = i + 1) begin
                if (web[i])
                    mem[addrb][i*8 +: 8] <= dinb[i*8 +: 8];
            end
        end
    end
endmodule
