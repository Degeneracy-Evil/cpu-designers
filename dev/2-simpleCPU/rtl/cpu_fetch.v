`timescale 1ns / 1ps

module cpu_fetch(
    input              clk,
    input              reset,
    input         if_valid,
    input  [31:0] pc,
    input  [31:0] inst_data,
    output        icache_en,
    output [10:0] icache_addr,
    output        if_done,
    output [95:0] if_id_bus,

    output [31:0] if_pc,
    output [31:0] if_inst
);

    wire [31:0] pc_plus4;
    assign pc_plus4 = pc + 32'd4;

    assign icache_en = if_valid;
    assign icache_addr = pc[12:2];

    reg r_bram_sent;
    always @(posedge clk or posedge reset) begin
        if (reset)
            r_bram_sent <= 1'b0;
        else if (if_valid)
            r_bram_sent <= 1'b1;
        else
            r_bram_sent <= 1'b0;
    end

    assign if_done = if_valid && r_bram_sent;
    assign if_id_bus = {pc_plus4, pc, inst_data};

    assign if_pc = pc;
    assign if_inst = inst_data;

endmodule
