`timescale 1ns / 1ps

module tb_mu_unit;

  reg clk;
  reg reset;
  reg [1:0] mu_control;
  reg [31:0] src1;
  reg [31:0] src2;
  reg req_valid;
  reg flush;
  reg result_ready;

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

  localparam MU_MUL = 2'b01;
  localparam MU_DIV = 2'b10;

  mu_unit dut(
            .clk(clk),
            .reset(reset),
            .mu_control(mu_control),
            .src1(src1),
            .src2(src2),
            .req_valid(req_valid),
            .flush(flush),
            .result_ready(result_ready),
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

  initial
  begin
    pass_count = 0;
    fail_count = 0;
    rv_pulse_count = 0;
    result_valid_d = 1'b0;

    reset = 1'b1;
    mu_control = 2'b0;
    src1 = 32'b0;
    src2 = 32'b0;
    req_valid = 1'b0;
    flush = 1'b0;
    result_ready = 1'b1;

    repeat (3) @(posedge clk);
    reset = 1'b0;
    repeat (2) @(posedge clk);

    $display("========================================");
    $display("MU Unit Integration Test");
    $display("========================================");

    mu_control = MU_MUL;
    src1 = 32'd3;
    src2 = 32'd7;
    req_valid = 1'b1;

    timeout_count = 0;
    while (!result_valid && timeout_count < 120)
    begin
      @(posedge clk);
      timeout_count = timeout_count + 1;
    end

    expect_true(timeout_count < 120, "MUL result_valid arrives with held req_valid");
    expect_true(result == 32'd21, "MUL result is correct");

    repeat (6) @(posedge clk);
    expect_true(rv_pulse_count == 1, "Held req_valid does not retrigger MUL");

    req_valid = 1'b0;
    mu_control = 2'b0;
    repeat (2) @(posedge clk);

    rv_before = rv_pulse_count;
    mu_control = MU_DIV;
    src1 = 32'd1000;
    src2 = 32'd7;
    req_valid = 1'b1;
    @(posedge clk);
    req_valid = 1'b0;

    repeat (5) @(posedge clk);
    flush = 1'b1;
    @(posedge clk);
    flush = 1'b0;

    @(posedge clk);
    expect_true(mu_busy == 1'b0, "Flush clears busy state");

    repeat (50) @(posedge clk);
    expect_true(rv_pulse_count == rv_before, "Flushed DIV does not publish stale result");

    mu_control = MU_DIV;
    src1 = 32'd123;
    src2 = 32'd0;
    req_valid = 1'b1;
    @(posedge clk);
    req_valid = 1'b0;

    wait_result_valid(20, timeout_count);
    expect_true(timeout_count == 1, "DIV by zero returns quickly");
    expect_true(result == 32'd0, "DIV by zero quotient is zero");
    expect_true(div_by_zero == 1'b1, "DIV by zero flag is set");

    mu_control = MU_MUL;
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
