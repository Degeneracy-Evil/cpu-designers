`timescale 1ns / 1ps

module tb_non_restoring_divider;

  reg clk;
  reg reset;
  reg [31:0] dividend;
  reg [31:0] divisor;
  reg start;
  reg is_unsigned;

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
                         .is_unsigned(is_unsigned),
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
      is_unsigned = 1'b0;
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

  task check_divu;
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
      is_unsigned = 1'b1;
      start = 1'b1;

      wait_for_done();
      got_q = quotient;
      got_r = remainder;
      @(negedge clk);
      start = 1'b0;
      is_unsigned = 1'b0;

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
    is_unsigned = 1'b0;
    test_count = 0;
    pass_count = 0;
    fail_count = 0;

    repeat (3)
    begin
      @(posedge clk);
    end
    reset = 1'b0;

    check_div(32'd1000, 32'd7, 32'd142, 32'd6, "1000 / 7");
    check_div(32'hFFFF_FC18, 32'd7, 32'hFFFF_FF72, 32'hFFFF_FFFA, "-1000 / 7");
    check_div(32'd1000, 32'hFFFF_FFF9, 32'hFFFF_FF72, 32'd6, "1000 / -7");
    check_div(32'hFFFF_FC18, 32'hFFFF_FFF9, 32'd142, 32'hFFFF_FFFA, "-1000 / -7");

    check_div(32'h8000_0000, 32'd1, 32'h8000_0000, 32'd0, "INT_MIN / 1");
    check_div(32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000, 32'd0, "INT_MIN / -1 overflow case");
    check_div(32'h8000_0000, 32'd2, 32'hC000_0000, 32'd0, "INT_MIN / 2");
    check_div(32'h8000_0000, 32'd3, 32'hD555_5556, 32'hFFFF_FFFE, "INT_MIN / 3");
    check_div(32'h8000_0000, 32'hFFFF_FFFD, 32'h2AAA_AAAA, 32'hFFFF_FFFE, "INT_MIN / -3");

    check_div(32'd123, 32'd0, 32'hFFFF_FFFF, 32'd123, "123 / 0 (signed, div-by-zero)");
    check_div(32'd0, 32'd7, 32'd0, 32'd0, "0 / 7");

    check_divu(32'd1000, 32'd7, 32'd142, 32'd6, "1000 /u 7");
    check_divu(32'hFFFF_FC18, 32'd7, 32'h2492_4895, 32'd5, "0xFFFFFC18 /u 7");
    check_divu(32'd100, 32'd10, 32'd10, 32'd0, "100 /u 10");
    check_divu(32'h8000_0000, 32'hFFFF_FFFF, 32'd0, 32'h8000_0000, "0x80000000 /u 0xFFFFFFFF");
    check_divu(32'd123, 32'd0, 32'hFFFF_FFFF, 32'd123, "123 /u 0 (unsigned div-by-zero)");
    check_divu(32'h8000_0000, 32'd2, 32'h4000_0000, 32'd0, "0x80000000 /u 2");
    check_divu(32'd0, 32'd7, 32'd0, 32'd0, "0 /u 7");
    check_divu(32'hFFFF_FFFF, 32'h8000_0001, 32'd1, 32'h7FFF_FFFE, "0xFFFFFFFF /u 0x80000001");
    check_divu(32'h8000_0000, 32'h8000_0000, 32'd1, 32'd0, "0x80000000 /u 0x80000000");
    check_divu(32'h7FFF_FFFF, 32'h8000_0000, 32'd0, 32'h7FFF_FFFF, "0x7FFFFFFF /u 0x80000000");

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
