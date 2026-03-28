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
    
    assign step1_sll = (shamt[0] == 1'b0) ? data : {data[30:0], 1'b0};
    assign step1_srl = (shamt[0] == 1'b0) ? data : {1'b0, data[31:1]};
    assign step1_sra = (shamt[0] == 1'b0) ? data : {data[31], data[31:1]};
    
    assign step2_sll = (shamt[1] == 1'b0) ? step1_sll : {step1_sll[29:0], 2'b0};
    assign step2_srl = (shamt[1] == 1'b0) ? step1_srl : {2'b0, step1_srl[31:2]};
    assign step2_sra = (shamt[1] == 1'b0) ? step1_sra : {{2{step1_sra[31]}}, step1_sra[31:2]};
    
    assign step3_sll = (shamt[2] == 1'b0) ? step2_sll : {step2_sll[27:0], 4'b0};
    assign step3_srl = (shamt[2] == 1'b0) ? step2_srl : {4'b0, step2_srl[31:4]};
    assign step3_sra = (shamt[2] == 1'b0) ? step2_sra : {{4{step2_sra[31]}}, step2_sra[31:4]};
    
    assign step4_sll = (shamt[3] == 1'b0) ? step3_sll : {step3_sll[23:0], 8'b0};
    assign step4_srl = (shamt[3] == 1'b0) ? step3_srl : {8'b0, step3_srl[31:8]};
    assign step4_sra = (shamt[3] == 1'b0) ? step3_sra : {{8{step3_sra[31]}}, step3_sra[31:8]};
    
    assign step5_sll = (shamt[4] == 1'b0) ? step4_sll : {step4_sll[15:0], 16'b0};
    assign step5_srl = (shamt[4] == 1'b0) ? step4_srl : {16'b0, step4_srl[31:16]};
    assign step5_sra = (shamt[4] == 1'b0) ? step4_sra : {{16{step4_sra[31]}}, step4_sra[31:16]};
    
    assign result = (shift_type == 2'b00) ? step5_sll :
                    (shift_type == 2'b01) ? step5_srl :
                    step5_sra;
endmodule