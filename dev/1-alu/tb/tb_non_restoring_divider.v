`timescale 1ns / 1ps

module tb_non_restoring_divider;

  reg clk;
  reg reset;
  reg [31:0] dividend;
  reg [31:0] divisor;
  reg start;

  wire [31:0] quotient;
  wire [31:0] remainder;
  wire done;

  integer test_count;
  integer pass_count;
  integer fail_count;
  reg [31:0] got_q;
  reg [31:0] got_r;

  non_restoring_divider dut(
                         .clk(clk),
                         .reset(reset),
                         .dividend(dividend),
                         .divisor(divisor),
                         .start(start),
                         .quotient(quotient),
                         .remainder(remainder),
                         .done(done)
                       );

  always #5 clk = ~clk;

  task wait_for_done;
    begin
      while (done !== 1'b1)
      begin
        @(posedge clk);
      end
    end
  endtask

  task check_div;
    input [31:0] in_dividend;
    input [31:0] in_divisor;
    input [31:0] expected_q;
    input [31:0] expected_r;
    input [8*80:1] description;
    begin
      while (done === 1'b1)
      begin
        @(posedge clk);
      end

      test_count = test_count + 1;

      @(negedge clk);
      dividend = in_dividend;
      divisor = in_divisor;
      start = 1'b1;

      wait_for_done();
      got_q = quotient;
      got_r = remainder;
      @(negedge clk);
      start = 1'b0;

      if ((got_q === expected_q) && (got_r === expected_r))
      begin
        pass_count = pass_count + 1;
        $display("PASS[%0d] %0s", test_count, description);
        $display("  Q exp/got: %h / %h", expected_q, got_q);
        $display("  R exp/got: %h / %h", expected_r, got_r);
      end
      else
      begin
        fail_count = fail_count + 1;
        $display("FAIL[%0d] %0s", test_count, description);
        $display("  Q exp/got: %h / %h", expected_q, got_q);
        $display("  R exp/got: %h / %h", expected_r, got_r);
      end

      repeat (2)
      begin
        @(posedge clk);
      end
    end
  endtask

  initial
  begin
    clk = 1'b0;
    reset = 1'b1;
    dividend = 32'b0;
    divisor = 32'b0;
    start = 1'b0;
    test_count = 0;
    pass_count = 0;
    fail_count = 0;

    repeat (3)
    begin
      @(posedge clk);
    end
    reset = 1'b0;

    // 基本功能
    check_div(32'd1000, 32'd7, 32'd142, 32'd6, "1000 / 7");
    check_div(32'hFFFF_FC18, 32'd7, 32'hFFFF_FF72, 32'hFFFF_FFFA, "-1000 / 7");
    check_div(32'd1000, 32'hFFFF_FFF9, 32'hFFFF_FF72, 32'd6, "1000 / -7");
    check_div(32'hFFFF_FC18, 32'hFFFF_FFF9, 32'd142, 32'hFFFF_FFFA, "-1000 / -7");

    // 你要求的边界：被除数 = -2^31
    check_div(32'h8000_0000, 32'd1, 32'h8000_0000, 32'd0, "INT_MIN / 1");
    // 约定采用二补码截断语义：INT_MIN / -1 -> INT_MIN, remainder=0
    check_div(32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000, 32'd0, "INT_MIN / -1 overflow case");
    check_div(32'h8000_0000, 32'd2, 32'hC000_0000, 32'd0, "INT_MIN / 2");
    check_div(32'h8000_0000, 32'd3, 32'hD555_5556, 32'hFFFF_FFFE, "INT_MIN / 3");
    check_div(32'h8000_0000, 32'hFFFF_FFFD, 32'h2AAA_AAAA, 32'hFFFF_FFFE, "INT_MIN / -3");

    // 其他约定
    check_div(32'd123, 32'd0, 32'd0, 32'd123, "123 / 0");
    check_div(32'd0, 32'd7, 32'd0, 32'd0, "0 / 7");

    $display("========================================");
    $display("Divider Test Summary");
    $display("========================================");
    $display("Total tests: %0d", test_count);
    $display("Passed:      %0d", pass_count);
    $display("Failed:      %0d", fail_count);

    if (fail_count == 0)
    begin
      $display("ALL DIVIDER TESTS PASSED");
    end
    else
    begin
      $display("DIVIDER TESTS FAILED");
    end

    $finish;
  end

endmodule
