`timescale 1ns / 1ps

module tb_alu_cpu_integration;

  reg [15:0] alu_control;
  reg [31:0] src1;
  reg [31:0] src2;

  wire [31:0] result;

  integer pass_count;
  integer fail_count;

  localparam OP_ADD = 16'b0001_0000_0000_0000;
  localparam OP_SUB = 16'b0000_1000_0000_0000;
  localparam OP_AND = 16'b0000_0001_0000_0000;
  localparam OP_OR  = 16'b0000_0000_0100_0000;
  localparam OP_XOR = 16'b0000_0000_0010_0000;
  localparam OP_SLL = 16'b0000_0000_0001_0000;
  localparam OP_SRL = 16'b0000_0000_0000_1000;
  localparam OP_SRA = 16'b0000_0000_0000_0100;
  localparam OP_LUI = 16'b0000_0000_0000_0010;
  localparam OP_SLT = 16'b0000_0100_0000_0000;
  localparam OP_SLTU = 16'b0000_0010_0000_0000;

  alu_32bit dut(
              .alu_control(alu_control),
              .src1(src1),
              .src2(src2),
              .result(result)
            );

  task expect_true;
    input cond;
    input [639:0] name;
    begin
      if (cond)
      begin
        pass_count = pass_count + 1;
        $display("PASS: %0s", name);
      end
      else
      begin
        fail_count = fail_count + 1;
        $display("FAIL: %0s", name);
      end
    end
  endtask

  initial
  begin
    pass_count = 0;
    fail_count = 0;

    $display("========================================");
    $display("ALU Single-Cycle Integration Test");
    $display("========================================");

    alu_control = OP_ADD;
    src1 = 32'd10;
    src2 = 32'd20;
    #1;
    expect_true(result == 32'd30, "ADD 10 + 20 = 30");

    alu_control = OP_SUB;
    src1 = 32'd100;
    src2 = 32'd30;
    #1;
    expect_true(result == 32'd70, "SUB 100 - 30 = 70");

    alu_control = OP_AND;
    src1 = 32'hFF00_FF00;
    src2 = 32'h0FF0_0FF0;
    #1;
    expect_true(result == 32'h0F00_0F00, "AND FF00.. & 0FF0.. = 0F00..");

    alu_control = OP_OR;
    src1 = 32'hFF00_FF00;
    src2 = 32'h0FF0_0FF0;
    #1;
    expect_true(result == 32'hFFF0_FFF0, "OR FF00.. | 0FF0.. = FFF0..");

    alu_control = OP_XOR;
    src1 = 32'hFF00_FF00;
    src2 = 32'h0FF0_0FF0;
    #1;
    expect_true(result == 32'hF0F0_F0F0, "XOR FF00.. ^ 0FF0.. = F0F0..");

    alu_control = OP_SLL;
    src1 = 32'h0000_0001;
    src2 = 32'd4;
    #1;
    expect_true(result == 32'h0000_0010, "SLL 1 << 4 = 16");

    alu_control = OP_SRL;
    src1 = 32'h8000_0000;
    src2 = 32'd4;
    #1;
    expect_true(result == 32'h0800_0000, "SRL 0x80000000 >> 4 = 0x08000000");

    alu_control = OP_SRA;
    src1 = 32'h8000_0000;
    src2 = 32'd4;
    #1;
    expect_true(result == 32'hF800_0000, "SRA 0x80000000 >>> 4 = 0xF8000000");

    alu_control = OP_SLT;
    src1 = 32'hFFFF_FFFF;
    src2 = 32'd0;
    #1;
    expect_true(result == 32'd1, "SLT -1 < 0 = 1");

    alu_control = OP_SLT;
    src1 = 32'd0;
    src2 = 32'hFFFF_FFFF;
    #1;
    expect_true(result == 32'd0, "SLT 0 < -1 = 0");

    alu_control = OP_SLTU;
    src1 = 32'd0;
    src2 = 32'hFFFF_FFFF;
    #1;
    expect_true(result == 32'd1, "SLTU 0 < 0xFFFFFFFF = 1");

    alu_control = OP_LUI;
    src1 = 32'd0;
    src2 = 32'h0001_0000;
    #1;
    expect_true(result == 32'h0000_0000, "LUI imm=0x00010000 result=0x00000000");

    $display("========================================");
    $display("ALU Single-Cycle Summary");
    $display("========================================");
    $display("Passed: %0d", pass_count);
    $display("Failed: %0d", fail_count);

    if (fail_count == 0)
    begin
      $display("ALL ALU TESTS PASSED");
    end
    else
    begin
      $display("ALU TESTS FAILED");
    end

    $finish;
  end

endmodule
