`timescale 1ns / 1ps

// Simple data memory with request/ready/valid handshake.
module data_mem #(
    parameter MEM_DEPTH = 256
)(
    input         clk,
    input         reset,
    input         req,
    input         write_en,
    input  [31:0] addr,
    input  [31:0] wdata,
    input  [3:0]  wstrb,
    output reg [31:0] rdata,
    output        ready,
    output reg    rvalid,
    output reg    wdone
);

    reg [31:0] mem[0:MEM_DEPTH-1];
    integer i;
    wire [31:0] word_addr;
    reg [31:0] old_word;
    reg [31:0] new_word;

    assign word_addr = {2'b00, addr[31:2]};
    assign ready = 1'b1;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < MEM_DEPTH; i = i + 1)
                mem[i] <= 32'b0;
            rdata <= 32'b0;
            rvalid <= 1'b0;
            wdone <= 1'b0;
        end else begin
            rvalid <= 1'b0;
            wdone <= 1'b0;

            if (req) begin
                if (word_addr < MEM_DEPTH) begin
                    if (write_en) begin
                        old_word = mem[word_addr];
                        new_word = old_word;
                        if (wstrb[0])
                            new_word[7:0] = wdata[7:0];
                        if (wstrb[1])
                            new_word[15:8] = wdata[15:8];
                        if (wstrb[2])
                            new_word[23:16] = wdata[23:16];
                        if (wstrb[3])
                            new_word[31:24] = wdata[31:24];
                        mem[word_addr] <= new_word;
                        wdone <= 1'b1;
                    end else begin
                        rdata <= mem[word_addr];
                        rvalid <= 1'b1;
                    end
                end else begin
                    if (write_en)
                        wdone <= 1'b1;
                    else begin
                        rdata <= 32'b0;
                        rvalid <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
