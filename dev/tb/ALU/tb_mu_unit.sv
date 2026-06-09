`timescale 1ns / 1ps

module tb_mu_unit;

  reg clk;
  reg resetn;
  reg [2:0] mu_funct3;
  reg [31:0] src1;
  reg [31:0] src2;
  reg req_valid;
  reg flush;
  reg result_got;

  wire [31:0] result;
  wire        mu_busy;
  wire        mu_ready;
  wire        result_valid;
  wire        div_by_zero;

  integer pass_count;
  integer fail_count;
  integer rv_pulse_count;
  integer timeout_count;
  integer rv_before;
  reg result_valid_d;

  localparam FN3_MUL    = 3'b000;
  localparam FN3_MULH   = 3'b001;
  localparam FN3_MULHSU = 3'b010;
  localparam FN3_MULHU  = 3'b011;
  localparam FN3_DIV    = 3'b100;
  localparam FN3_DIVU   = 3'b101;
  localparam FN3_REM    = 3'b110;
  localparam FN3_REMU   = 3'b111;

  mu_unit dut(
            .clk(clk),
            .resetn(resetn),
            .mu_funct3(mu_funct3),
            .src1(src1),
            .src2(src2),
            .req_valid(req_valid),
            .flush(flush),
            .result_got(result_got),
            .result(result),
            .mu_busy(mu_busy),
            .mu_ready(mu_ready),
            .result_valid(result_valid),
            .div_by_zero(div_by_zero)
          );

  initial
  begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always @(posedge clk)
  begin
    result_valid_d <= result_valid;
    if (result_valid && !result_valid_d)
    begin
      rv_pulse_count = rv_pulse_count + 1;
    end
  end

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

  task wait_result_valid;
    input integer max_cycles;
    output integer hit;
    integer i;
    begin
      hit = 0;
      for (i = 0; i < max_cycles; i = i + 1)
      begin
        @(posedge clk);
        if (result_valid)
        begin
          hit = 1;
          i = max_cycles;
        end
      end
    end
  endtask

  task run_mu;
    input [2:0] fn3;
    input [31:0] a;
    input [31:0] b;
    input integer max_wait;
    input [31:0] expected;
    input [639:0] desc;
    integer hit;
    begin
      mu_funct3 = fn3;
      src1 = a;
      src2 = b;
      req_valid = 1'b1;
      wait_result_valid(max_wait, hit);
      expect_true(hit == 1, desc);
      if (result !== expected)
        $display("  Expected: %h, Got: %h", expected, result);
      expect_true(result == expected, {desc, " value"});
      req_valid = 1'b0;
      mu_funct3 = 3'b0;
      repeat (3) @(posedge clk);
    end
  endtask

  initial
  begin
    pass_count = 0;
    fail_count = 0;
    rv_pulse_count = 0;
    result_valid_d = 1'b0;

    resetn = 1'b0;
    mu_funct3 = 3'b0;
    src1 = 32'b0;
    src2 = 32'b0;
    req_valid = 1'b0;
    flush = 1'b0;
    result_got = 1'b1;

    repeat (3) @(posedge clk);
    resetn = 1'b1;
    repeat (2) @(posedge clk);

    $display("========================================");
    $display("MU Unit Integration Test");
    $display("========================================");

    run_mu(FN3_MUL, 32'd3, 32'd7, 60, 32'd21, "MUL 3*7");
    run_mu(FN3_MUL, 32'hFFFF_FFFF, 32'd2, 60, 32'hFFFF_FFFE, "MUL -1*2");
    run_mu(FN3_MUL, 32'h8000_0000, 32'd2, 60, 32'd0, "MUL INT_MIN*2 lower32");

    run_mu(FN3_MULH, 32'd3, 32'd7, 60, 32'd0, "MULH 3*7 upper");
    run_mu(FN3_MULH, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 60, 32'd0, "MULH -1*-1 upper");
    run_mu(FN3_MULH, 32'h8000_0000, 32'd2, 60, 32'hFFFF_FFFF, "MULH INT_MIN*2 upper");

    run_mu(FN3_MULHSU, 32'hFFFF_FFFF, 32'd1, 60, 32'hFFFF_FFFF, "MULHSU -1*1u upper");
    run_mu(FN3_MULHSU, 32'hFFFF_FFFF, 32'h8000_0000, 60, 32'hFFFF_FFFF, "MULHSU -1*0x80000000u upper");

    run_mu(FN3_MULHU, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 60, 32'hFFFF_FFFE, "MULHU 0xFFFFFFFF*0xFFFFFFFF upper");
    run_mu(FN3_MULHU, 32'd1, 32'd1, 60, 32'd0, "MULHU 1*1 upper");

    run_mu(FN3_DIV, 32'd100, 32'd7, 60, 32'd14, "DIV 100/7");
    run_mu(FN3_DIV, 32'hFFFF_FFFF, 32'd7, 60, 32'd0, "DIV -1/7");

    run_mu(FN3_DIVU, 32'd100, 32'd7, 60, 32'd14, "DIVU 100/7");
    run_mu(FN3_DIVU, 32'hFFFF_FFFF, 32'd7, 60, 32'h2492_4924, "DIVU 0xFFFFFFFF/7");

    run_mu(FN3_REM, 32'd100, 32'd7, 60, 32'd2, "REM 100%7");
    run_mu(FN3_REM, 32'hFFFF_FFFF, 32'd7, 60, 32'hFFFF_FFFF, "REM -1%7");

    run_mu(FN3_REMU, 32'd100, 32'd7, 60, 32'd2, "REMU 100%7");
    run_mu(FN3_REMU, 32'hFFFF_FFFF, 32'd7, 60, 32'd3, "REMU 0xFFFFFFFF%7");

    rv_before = rv_pulse_count;
    mu_funct3 = FN3_DIV;
    src1 = 32'd123;
    src2 = 32'd0;
    req_valid = 1'b1;
    @(posedge clk);
    req_valid = 1'b0;

    wait_result_valid(20, timeout_count);
    expect_true(timeout_count == 1, "DIV by zero returns quickly");
    expect_true(result == 32'hFFFF_FFFF, "DIV by zero quotient is all 1s");
    expect_true(div_by_zero == 1'b1, "DIV by zero flag is set");

    repeat (5) @(posedge clk);
    rv_before = rv_pulse_count;
    flush = 1'b1;
    @(posedge clk);
    flush = 1'b0;

    @(posedge clk);
    expect_true(mu_busy == 1'b0, "Flush clears busy state");

    repeat (50) @(posedge clk);
    expect_true(rv_pulse_count == rv_before, "Flushed op does not publish stale result");

    mu_funct3 = FN3_MUL;
    src1 = 32'd1;
    src2 = 32'd2;
    req_valid = 1'b1;
    @(posedge clk);
    req_valid = 1'b0;
    wait_result_valid(60, timeout_count);
    expect_true(div_by_zero == 1'b0, "DIV by zero flag clears on next valid request");

    $display("========================================");
    $display("MU Unit Summary");
    $display("========================================");
    $display("Passed: %0d", pass_count);
    $display("Failed: %0d", fail_count);

    if (fail_count == 0)
    begin
      $display("ALL MU UNIT TESTS PASSED");
    end
    else
    begin
      $display("MU UNIT TESTS FAILED");
    end

    $finish;
  end

endmodule
