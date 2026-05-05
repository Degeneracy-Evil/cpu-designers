`timescale 1ns / 1ps

module cla_adder_16bit(
    input  [15:0] a,
    input  [15:0] b,
    input         cin,
    output [15:0] sum,
    output        cout
  );
  wire c4, c8, c12;

  cla_adder_4bit cla0(
                    .a(a[3:0]),
                    .b(b[3:0]),
                    .cin(cin),
                    .sum(sum[3:0]),
                    .cout(c4),
                    .g(),
                    .p()
                  );

  cla_adder_4bit cla1(
                    .a(a[7:4]),
                    .b(b[7:4]),
                    .cin(c4),
                    .sum(sum[7:4]),
                    .cout(c8),
                    .g(),
                    .p()
                  );

  cla_adder_4bit cla2(
                    .a(a[11:8]),
                    .b(b[11:8]),
                    .cin(c8),
                    .sum(sum[11:8]),
                    .cout(c12),
                    .g(),
                    .p()
                  );

  cla_adder_4bit cla3(
                    .a(a[15:12]),
                    .b(b[15:12]),
                    .cin(c12),
                    .sum(sum[15:12]),
                    .cout(cout),
                    .g(),
                    .p()
                  );
endmodule
