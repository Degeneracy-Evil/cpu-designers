`timescale 1ns / 1ps

// Booth乘法器 - 支持32位有符号数乘法
// 算法: Booth算法，通过检查乘数相邻位决定操作
// 周期: 32个时钟周期完成
module booth_multiplier(
    input         clk,
    input         reset,
    input  [31:0] multiplicand,  // 被乘数
    input  [31:0] multiplier,    // 乘数
    input         start,         // 开始信号
    output [63:0] product,       // 乘积(64位)
    output        done           // 完成标志
  );

  // 状态机状态定义
  localparam IDLE    = 2'b00;  // 空闲状态
  localparam COMPUTE = 2'b01;  // 计算状态
  localparam FINISH  = 2'b10;  // 完成状态

  reg [1:0] state;
  reg [5:0] count;      // 迭代计数器
  reg [31:0] A;         // 累加器
  reg [31:0] Q;         // 乘数寄存器
  reg Q_1;              // Q的扩展位(Q[-1])
  reg [31:0] M;         // 被乘数寄存器

  wire [1:0] booth_pair;  // Booth对: {Q[0], Q_1}
  wire [31:0] add_result;
  wire [31:0] sub_result;
  wire add_cout;
  wire sub_cout;
  wire [31:0] count_ext;
  wire [31:0] count_inc_ext;
  wire count_inc_cout;

  assign booth_pair = {Q[0], Q_1};
  assign count_ext = {26'b0, count};

  // 根据Booth对选择操作数
  // 00或11: 不操作(add_op_b=0)
  // 01: A = A + M
  // 10: A = A - M = A + ~M + 1
  wire [31:0] add_op_b;
  wire add_cin;

  wire [31:0] booth_pair_01_op;
  wire [31:0] booth_pair_10_op;
  wire [31:0] booth_pair_00_op;

  assign booth_pair_00_op = 32'b0;
  assign booth_pair_01_op = M;
  assign booth_pair_10_op = ~M;  // 用于减法

  // 使用MUX选择加法操作数，避免使用?:运算符
  mux_4to1 #(32) mux_add_op_b(
             .in0(booth_pair_00_op),  // 00: 不操作
             .in1(booth_pair_01_op),  // 01: 加M
             .in2(booth_pair_10_op),  // 10: 加~M
             .in3(booth_pair_00_op),  // 11: 不操作
             .sel(booth_pair),
             .y(add_op_b)
           );

  // 选择进位输入(10时需要+1完成减法)
  mux_4to1 #(1) mux_add_cin(
             .in0(1'b0),
             .in1(1'b0),
             .in2(1'b1),  // 10: cin=1完成A-M
             .in3(1'b0),
             .sel(booth_pair),
             .y(add_cin)
           );

  cla_adder_32bit adder(
                    .a(A),
                    .b(add_op_b),
                    .cin(add_cin),
                    .sum(add_result),
                    .cout(add_cout)
                  );

  cla_adder_32bit count_incrementer(
                    .a(count_ext),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(count_inc_ext),
                    .cout(count_inc_cout)
                  );

  // 状态机
  always @(posedge clk or posedge reset)
  begin
    if (reset)
    begin
      state <= IDLE;
      count <= 6'b0;
      A <= 32'b0;
      Q <= 32'b0;
      Q_1 <= 1'b0;
      M <= 32'b0;
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
            A <= 32'b0;
            Q <= multiplier;
            Q_1 <= 1'b0;
            M <= multiplicand;
          end
        end

        COMPUTE:
        begin
          if (count < 32)
          begin
            // Booth算法核心: 根据Booth对决定操作
            if (booth_pair == 2'b00 || booth_pair == 2'b11)
            begin
              // 不操作，直接算术右移
              A <= {A[31], A[31:1]};
              Q <= {A[0], Q[31:1]};
              Q_1 <= Q[0];
            end
            else
            begin
              // 先加减，再算术右移
              A <= {add_result[31], add_result[31:1]};
              Q <= {add_result[0], Q[31:1]};
              Q_1 <= Q[0];
            end
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

  // 输出: 乘积 = {A, Q}
  assign product = {A, Q};
  assign done = (state == FINISH);

endmodule
