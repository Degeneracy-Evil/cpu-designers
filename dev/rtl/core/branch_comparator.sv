`timescale 1ns / 1ps

module branch_comparator(
    input  [31:0] rs1_value,
    input  [31:0] rs2_value,
    input  [2:0]  branch_funct3,
    output        branch_cond_true
);

    wire rs1_eq_rs2   = (rs1_value == rs2_value);
    wire rs1_lt_rs2_s = ($signed(rs1_value) < $signed(rs2_value));
    wire rs1_lt_rs2_u = (rs1_value < rs2_value);

    assign branch_cond_true = (branch_funct3 == 3'b000) ?  rs1_eq_rs2   :
                              (branch_funct3 == 3'b001) ? ~rs1_eq_rs2   :
                              (branch_funct3 == 3'b100) ?  rs1_lt_rs2_s :
                              (branch_funct3 == 3'b101) ? ~rs1_lt_rs2_s :
                              (branch_funct3 == 3'b110) ?  rs1_lt_rs2_u :
                              (branch_funct3 == 3'b111) ? ~rs1_lt_rs2_u :
                                                           1'b0;

endmodule
