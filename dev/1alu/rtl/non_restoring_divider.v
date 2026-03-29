`timescale 1ns / 1ps

module non_restoring_divider(
    input         clk,
    input         reset,
    input  [31:0] dividend,
    input  [31:0] divisor,
    input         start,
    output [31:0] quotient,
    output [31:0] remainder,
    output        done
);

    localparam IDLE    = 2'b00;
    localparam COMPUTE = 2'b01;
    localparam FINISH  = 2'b10;

    reg [1:0] state;
    reg [5:0] count;
    reg [31:0] R;
    reg [31:0] Q;
    reg [31:0] D;
    reg sign_dividend;
    reg sign_divisor;
    
    wire [31:0] shifted_R;
    wire shifted_Q_msb;
    
    assign shifted_R = {R[30:0], Q[31]};
    assign shifted_Q_msb = Q[30];
    
    wire [31:0] sub_result;
    wire [31:0] add_result;
    wire sub_cout;
    wire add_cout;
    
    wire [31:0] sub_op;
    assign sub_op = ~D;
    
    cla_adder_32bit subtracter(
        .a(shifted_R),
        .b(sub_op),
        .cin(1'b1),
        .sum(sub_result),
        .cout(sub_cout)
    );
    
    cla_adder_32bit adder(
        .a(sub_result),
        .b(D),
        .cin(1'b0),
        .sum(add_result),
        .cout(add_cout)
    );
    
    wire [31:0] abs_dividend_comb;
    wire [31:0] abs_divisor_comb;
    
    wire [31:0] neg_dividend;
    wire [31:0] neg_divisor;
    
    assign neg_dividend = ~dividend + 1'b1;
    assign neg_divisor = ~divisor + 1'b1;
    
    mux_2to1 #(32) mux_abs_dividend(
        .a(dividend),
        .b(neg_dividend),
        .sel(dividend[31]),
        .y(abs_dividend_comb)
    );
    
    mux_2to1 #(32) mux_abs_divisor(
        .a(divisor),
        .b(neg_divisor),
        .sel(divisor[31]),
        .y(abs_divisor_comb)
    );
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            count <= 6'b0;
            R <= 32'b0;
            Q <= 32'b0;
            D <= 32'b0;
            sign_dividend <= 1'b0;
            sign_divisor <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= COMPUTE;
                        count <= 6'b0;
                        R <= 32'b0;
                        Q <= abs_dividend_comb;
                        D <= abs_divisor_comb;
                        sign_dividend <= dividend[31];
                        sign_divisor <= divisor[31];
                    end
                end
                
                COMPUTE: begin
                    if (count < 32) begin
                        if (sub_result[31]) begin
                            R <= shifted_R;
                            Q <= {Q[30:0], 1'b0};
                        end else begin
                            R <= sub_result;
                            Q <= {Q[30:0], 1'b1};
                        end
                        count <= count + 1'b1;
                    end else begin
                        state <= FINISH;
                    end
                end
                
                FINISH: begin
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    wire result_sign;
    assign result_sign = sign_dividend ^ sign_divisor;
    
    wire [31:0] final_quotient;
    wire [31:0] final_remainder;
    
    wire [31:0] neg_Q;
    wire [31:0] neg_R;
    
    assign neg_Q = ~Q + 1'b1;
    assign neg_R = ~R + 1'b1;
    
    mux_2to1 #(32) mux_final_quotient(
        .a(Q),
        .b(neg_Q),
        .sel(result_sign),
        .y(final_quotient)
    );
    
    mux_2to1 #(32) mux_final_remainder(
        .a(R),
        .b(neg_R),
        .sel(sign_dividend),
        .y(final_remainder)
    );
    
    assign quotient = final_quotient;
    assign remainder = final_remainder;
    assign done = (state == FINISH);

endmodule