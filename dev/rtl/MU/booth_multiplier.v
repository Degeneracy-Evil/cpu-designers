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
  reg [32:0] A;
  reg [31:0] Q;
  reg Q_1;
  reg [32:0] M;

  wire [1:0] booth_pair;
  wire [32:0] add_result;
  wire [31:0] count_ext;
  wire [31:0] count_inc_ext;

  wire no_op = (booth_pair == 2'b00 || booth_pair == 2'b11);
  wire [32:0] shift_src = no_op ? A : add_result;

  assign booth_pair = {Q[0], Q_1};
  assign count_ext = {26'b0, count};

  wire [32:0] booth_pair_01_op;
  wire [32:0] booth_pair_10_op;
  wire [32:0] booth_pair_00_op;

  assign booth_pair_00_op = 33'b0;
  assign booth_pair_01_op = M;
  assign booth_pair_10_op = ~M;

  wire [32:0] add_op_b;
  mux_4to1 #(33) mux_add_op_b(
             .in0(booth_pair_00_op),
             .in1(booth_pair_01_op),
             .in2(booth_pair_10_op),
             .in3(booth_pair_00_op),
             .sel(booth_pair),
             .y(add_op_b)
           );

  wire add_cin;
  mux_4to1 #(1) mux_add_cin(
             .in0(1'b0),
             .in1(1'b0),
             .in2(1'b1),
             .in3(1'b0),
             .sel(booth_pair),
             .y(add_cin)
           );

  assign add_result = A + add_op_b + add_cin;

  cla_adder_32bit count_incrementer(
                    .a(count_ext),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(count_inc_ext),
                    .cout()
                  );

  always @(posedge clk or posedge reset)
  begin
    if (reset)
    begin
      state <= IDLE;
      count <= 6'b0;
      A <= 33'b0;
      Q <= 32'b0;
      Q_1 <= 1'b0;
      M <= 33'b0;
    end
    else
    begin
      case (state)
        IDLE:
        begin
          if (start)
          begin
            state <= COMPUTE;
            count <= 6'b0;
            A <= 33'b0;
            Q <= multiplier;
            Q_1 <= 1'b0;
            M <= {multiplicand[31], multiplicand};
          end
        end

        COMPUTE:
        begin
          if (count < 6'd32)
          begin
            A <= {shift_src[32], shift_src[32:1]};
            Q <= {shift_src[0], Q[31:1]};
            Q_1 <= Q[0];
            count <= count_inc_ext[5:0];
          end
          else
          begin
            state <= FINISH;
          end
        end

        FINISH:
        begin
          state <= IDLE;
        end

        default:
          state <= IDLE;
      endcase
    end
  end

  assign product = {A[31:0], Q};
  assign done = (state == FINISH);

endmodule
