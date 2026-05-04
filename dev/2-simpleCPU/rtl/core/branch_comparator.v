`timescale 1ns / 1ps

module branch_comparator(
    input  [31:0] rs1_value,
    input  [31:0] rs2_value,
    input  [2:0]  branch_funct3,
    output        branch_cond_true
);

    wire rs1_eq_rs2;
    wire rs1_lt_rs2_s;
    wire rs1_lt_rs2_u;

    assign rs1_eq_rs2   = (rs1_value == rs2_value);
    assign rs1_lt_rs2_s = ($signed(rs1_value) < $signed(rs2_value));
    assign rs1_lt_rs2_u = (rs1_value < rs2_value);

    reg branch_cond_true_r;
    assign branch_cond_true = branch_cond_true_r;

    always @(*) begin
        case (branch_funct3)
            3'b000: branch_cond_true_r = rs1_eq_rs2;
            3'b001: branch_cond_true_r = !rs1_eq_rs2;
            3'b100: branch_cond_true_r = rs1_lt_rs2_s;
            3'b101: branch_cond_true_r = !rs1_lt_rs2_s;
            3'b110: branch_cond_true_r = rs1_lt_rs2_u;
            3'b111: branch_cond_true_r = !rs1_lt_rs2_u;
            default: branch_cond_true_r = 1'b0;
        endcase
    end

endmodule
