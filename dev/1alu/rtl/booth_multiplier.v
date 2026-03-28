`timescale 1ns / 1ps

module booth_multiplier(
    input         clk,
    input         reset,
    input  [31:0] multiplicand,
    input  [31:0] multiplier,
    input         start,
    output [63:0] product,
    output        done
);

    localparam IDLE    = 2'b00;
    localparam COMPUTE = 2'b01;
    localparam FINISH  = 2'b10;

    reg [1:0] state;
    reg [5:0] count;
    reg [31:0] A;
    reg [31:0] Q;
    reg Q_1;
    reg [31:0] M;
    
    wire [1:0] booth_pair;
    wire [31:0] add_result;
    wire [31:0] sub_result;
    wire add_cout;
    wire sub_cout;
    
    assign booth_pair = {Q[0], Q_1};
    
    wire [31:0] add_op_b;
    wire add_cin;
    
    assign add_op_b = (booth_pair == 2'b01) ? M :
                      (booth_pair == 2'b10) ? (~M) :
                      32'b0;
    assign add_cin = (booth_pair == 2'b10) ? 1'b1 : 1'b0;
    
    cla_adder_32bit adder(
        .a(A),
        .b(add_op_b),
        .cin(add_cin),
        .sum(add_result),
        .cout(add_cout)
    );
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            count <= 6'b0;
            A <= 32'b0;
            Q <= 32'b0;
            Q_1 <= 1'b0;
            M <= 32'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= COMPUTE;
                        count <= 6'b0;
                        A <= 32'b0;
                        Q <= multiplier;
                        Q_1 <= 1'b0;
                        M <= multiplicand;
                    end
                end
                
                COMPUTE: begin
                    if (count < 32) begin
                        if (booth_pair == 2'b00 || booth_pair == 2'b11) begin
                            A <= {A[31], A[31:1]};
                            Q <= {A[0], Q[31:1]};
                            Q_1 <= Q[0];
                        end else begin
                            A <= {add_result[31], add_result[31:1]};
                            Q <= {add_result[0], Q[31:1]};
                            Q_1 <= Q[0];
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
    
    assign product = {A, Q};
    assign done = (state == FINISH);

endmodule