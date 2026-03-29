`timescale 1ns / 1ps

module shifter(
    input  [31:0] data,
    input  [4:0]  shamt,
    input  [1:0]  shift_type,
    output [31:0] result
);
    wire [31:0] step1_sll, step1_srl, step1_sra;
    wire [31:0] step2_sll, step2_srl, step2_sra;
    wire [31:0] step3_sll, step3_srl, step3_sra;
    wire [31:0] step4_sll, step4_srl, step4_sra;
    wire [31:0] step5_sll, step5_srl, step5_sra;
    
    mux_2to1 #(32) mux_step1_sll(
        .a(data),
        .b({data[30:0], 1'b0}),
        .sel(shamt[0]),
        .y(step1_sll)
    );
    
    mux_2to1 #(32) mux_step1_srl(
        .a(data),
        .b({1'b0, data[31:1]}),
        .sel(shamt[0]),
        .y(step1_srl)
    );
    
    mux_2to1 #(32) mux_step1_sra(
        .a(data),
        .b({data[31], data[31:1]}),
        .sel(shamt[0]),
        .y(step1_sra)
    );
    
    mux_2to1 #(32) mux_step2_sll(
        .a(step1_sll),
        .b({step1_sll[29:0], 2'b0}),
        .sel(shamt[1]),
        .y(step2_sll)
    );
    
    mux_2to1 #(32) mux_step2_srl(
        .a(step1_srl),
        .b({2'b0, step1_srl[31:2]}),
        .sel(shamt[1]),
        .y(step2_srl)
    );
    
    mux_2to1 #(32) mux_step2_sra(
        .a(step1_sra),
        .b({{2{step1_sra[31]}}, step1_sra[31:2]}),
        .sel(shamt[1]),
        .y(step2_sra)
    );
    
    mux_2to1 #(32) mux_step3_sll(
        .a(step2_sll),
        .b({step2_sll[27:0], 4'b0}),
        .sel(shamt[2]),
        .y(step3_sll)
    );
    
    mux_2to1 #(32) mux_step3_srl(
        .a(step2_srl),
        .b({4'b0, step2_srl[31:4]}),
        .sel(shamt[2]),
        .y(step3_srl)
    );
    
    mux_2to1 #(32) mux_step3_sra(
        .a(step2_sra),
        .b({{4{step2_sra[31]}}, step2_sra[31:4]}),
        .sel(shamt[2]),
        .y(step3_sra)
    );
    
    mux_2to1 #(32) mux_step4_sll(
        .a(step3_sll),
        .b({step3_sll[23:0], 8'b0}),
        .sel(shamt[3]),
        .y(step4_sll)
    );
    
    mux_2to1 #(32) mux_step4_srl(
        .a(step3_srl),
        .b({8'b0, step3_srl[31:8]}),
        .sel(shamt[3]),
        .y(step4_srl)
    );
    
    mux_2to1 #(32) mux_step4_sra(
        .a(step3_sra),
        .b({{8{step3_sra[31]}}, step3_sra[31:8]}),
        .sel(shamt[3]),
        .y(step4_sra)
    );
    
    mux_2to1 #(32) mux_step5_sll(
        .a(step4_sll),
        .b({step4_sll[15:0], 16'b0}),
        .sel(shamt[4]),
        .y(step5_sll)
    );
    
    mux_2to1 #(32) mux_step5_srl(
        .a(step4_srl),
        .b({16'b0, step4_srl[31:16]}),
        .sel(shamt[4]),
        .y(step5_srl)
    );
    
    mux_2to1 #(32) mux_step5_sra(
        .a(step4_sra),
        .b({{16{step4_sra[31]}}, step4_sra[31:16]}),
        .sel(shamt[4]),
        .y(step5_sra)
    );
    
    mux_4to1 #(32) mux_result(
        .in0(step5_sll),
        .in1(step5_srl),
        .in2(step5_sra),
        .in3(32'b0),
        .sel(shift_type),
        .y(result)
    );
endmodule