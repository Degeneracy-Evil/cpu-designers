`timescale 1ns / 1ps

module alu_32bit(
    input         clk,
    input         reset,
    input  [15:0] alu_control,
    input  [31:0] src1,
    input  [31:0] src2,
    output [31:0] result,
    output        done
);

    wire alu_mul;
    wire alu_div;
    wire alu_not;
    wire alu_add;
    wire alu_sub;
    wire alu_slt;
    wire alu_sltu;
    wire alu_and;
    wire alu_nor;
    wire alu_or;
    wire alu_xor;
    wire alu_sll;
    wire alu_srl;
    wire alu_sra;
    wire alu_lui;
    
    assign alu_mul  = alu_control[15];
    assign alu_div  = alu_control[14];
    assign alu_not  = alu_control[13];
    assign alu_add  = alu_control[12];
    assign alu_sub  = alu_control[11];
    assign alu_slt  = alu_control[10];
    assign alu_sltu = alu_control[9];
    assign alu_and  = alu_control[8];
    assign alu_nor  = alu_control[7];
    assign alu_or   = alu_control[6];
    assign alu_xor  = alu_control[5];
    assign alu_sll  = alu_control[4];
    assign alu_srl  = alu_control[3];
    assign alu_sra  = alu_control[2];
    assign alu_lui  = alu_control[1];
    
    wire [31:0] add_result;
    wire        add_cout;
    wire [31:0] sub_result;
    wire        sub_borrow;
    wire [31:0] and_result;
    wire [31:0] or_result;
    wire [31:0] not_result;
    wire [31:0] xor_result;
    wire [31:0] nor_result;
    wire [31:0] slt_result;
    wire [31:0] sltu_result;
    wire [31:0] sll_result;
    wire [31:0] srl_result;
    wire [31:0] sra_result;
    wire [31:0] lui_result;
    wire [63:0] mul_result;
    wire        mul_done;
    wire [31:0] div_quotient;
    wire [31:0] div_remainder;
    wire        div_done;
    
    cla_adder_32bit adder(
        .a(src1),
        .b(src2),
        .cin(1'b0),
        .sum(add_result),
        .cout(add_cout)
    );
    
    subtractor sub(
        .a(src1),
        .b(src2),
        .result(sub_result),
        .borrow(sub_borrow)
    );
    
    logic_unit logic_inst(
        .a(src1),
        .b(src2),
        .and_result(and_result),
        .or_result(or_result),
        .not_result(not_result),
        .xor_result(xor_result),
        .nor_result(nor_result),
        .slt_result(slt_result),
        .sltu_result(sltu_result)
    );
    
    shifter shift_sll_inst(
        .data(src2),
        .shamt(src1[4:0]),
        .shift_type(2'b00),
        .result(sll_result)
    );
    
    shifter shift_srl_inst(
        .data(src2),
        .shamt(src1[4:0]),
        .shift_type(2'b01),
        .result(srl_result)
    );
    
    shifter shift_sra_inst(
        .data(src2),
        .shamt(src1[4:0]),
        .shift_type(2'b10),
        .result(sra_result)
    );
    
    lui lui_inst(
        .imm(src2),
        .result(lui_result)
    );
    
    reg mul_start;
    reg div_start;
    reg [31:0] mul_src1_reg;
    reg [31:0] mul_src2_reg;
    reg [31:0] div_src1_reg;
    reg [31:0] div_src2_reg;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mul_start <= 1'b0;
            div_start <= 1'b0;
            mul_src1_reg <= 32'b0;
            mul_src2_reg <= 32'b0;
            div_src1_reg <= 32'b0;
            div_src2_reg <= 32'b0;
        end else begin
            if (alu_mul && !mul_start) begin
                mul_start <= 1'b1;
                mul_src1_reg <= src1;
                mul_src2_reg <= src2;
            end else if (mul_done) begin
                mul_start <= 1'b0;
            end
            
            if (alu_div && !div_start) begin
                div_start <= 1'b1;
                div_src1_reg <= src1;
                div_src2_reg <= src2;
            end else if (div_done) begin
                div_start <= 1'b0;
            end
        end
    end
    
    booth_multiplier multiplier(
        .clk(clk),
        .reset(reset),
        .multiplicand(mul_src1_reg),
        .multiplier(mul_src2_reg),
        .start(mul_start),
        .product(mul_result),
        .done(mul_done)
    );
    
    non_restoring_divider divider(
        .clk(clk),
        .reset(reset),
        .dividend(div_src1_reg),
        .divisor(div_src2_reg),
        .start(div_start),
        .quotient(div_quotient),
        .remainder(div_remainder),
        .done(div_done)
    );
    
    wire [31:0] mul_result_low;
    assign mul_result_low = mul_result[31:0];
    
    alu_result_selector result_mux(
        .mul_result(mul_result_low),
        .div_result(div_quotient),
        .not_result(not_result),
        .add_result(add_result),
        .sub_result(sub_result),
        .slt_result(slt_result),
        .sltu_result(sltu_result),
        .and_result(and_result),
        .nor_result(nor_result),
        .or_result(or_result),
        .xor_result(xor_result),
        .sll_result(sll_result),
        .srl_result(srl_result),
        .sra_result(sra_result),
        .lui_result(lui_result),
        .sel(alu_control),
        .y(result)
    );
    
    wire done_comb;
    wire done_mul_sel;
    wire done_div_sel;
    wire done_default;
    
    assign done_default = 1'b1;
    
    mux_2to1 #(1) mux_done_0(
        .a(done_default),
        .b(div_done),
        .sel(alu_div),
        .y(done_div_sel)
    );
    
    mux_2to1 #(1) mux_done_1(
        .a(done_div_sel),
        .b(mul_done),
        .sel(alu_mul),
        .y(done)
    );

endmodule