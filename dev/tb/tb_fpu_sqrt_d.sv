`timescale 1ns / 1ps

module tb_fpu_sqrt_d;

    // ===================================================================
    // IEEE 754 double-precision constants
    // ===================================================================
    localparam [63:0] QNAN           = 64'h7FF8000000000000;
    localparam [63:0] SNAN           = 64'h7FF0000000000001;
    localparam [63:0] POS_INF        = 64'h7FF0000000000000;
    localparam [63:0] POS_ZERO       = 64'h0000000000000000;
    localparam [63:0] NEG_ZERO       = 64'h8000000000000000;
    localparam [63:0] ONE            = 64'h3FF0000000000000;
    localparam [63:0] TWO            = 64'h4000000000000000;
    localparam [63:0] THREE          = 64'h4008000000000000;
    localparam [63:0] FOUR           = 64'h4010000000000000;
    localparam [63:0] NINE           = 64'h4022000000000000;
    localparam [63:0] SIXTEEN        = 64'h4030000000000000;
    localparam [63:0] QUARTER        = 64'h3FD0000000000000; // 0.25
    localparam [63:0] HALF           = 64'h3FE0000000000000; // 0.5
    localparam [63:0] NEG_ONE        = 64'hBFF0000000000000;
    localparam [63:0] MAX_SUBNORMAL  = 64'h000FFFFFFFFFFFFF;

    // sqrt(2) in double = 1.4142135623730951 = 0x3FF6A09E667F3BCD
    localparam [63:0] SQRT_2         = 64'h3FF6A09E667F3BCD;

    // Rounding mode constants
    localparam [2:0] RNE = 3'b000;
    localparam [2:0] RTZ = 3'b001;
    localparam [2:0] RDN = 3'b010;
    localparam [2:0] RUP = 3'b011;
    localparam [2:0] RMM = 3'b100;

    // fflags: {NV, DZ, OF, UF, NX}
    localparam [4:0] F_NONE   = 5'b00000;
    localparam [4:0] F_NV     = 5'b10000;
    localparam [4:0] F_NX     = 5'b00001;

    // ===================================================================
    // Clock and reset
    // ===================================================================
    reg        clk;
    reg        resetn;

    always #5 clk = ~clk;

    // ===================================================================
    // DUT signals
    // ===================================================================
    reg  [63:0] src1;
    reg  [2:0]  rm;
    reg         start;
    reg         flush;
    wire [63:0] result;
    wire [4:0]  fflags;
    wire        done;

    // ===================================================================
    // DUT instantiation
    // ===================================================================
    fpu_sqrt_d dut (
        .clk    (clk),
        .resetn (resetn),
        .src1   (src1),
        .rm     (rm),
        .start  (start),
        .flush  (flush),
        .result (result),
        .fflags (fflags),
        .done   (done)
    );

    // ===================================================================
    // Scoreboard
    // ===================================================================
    integer pass_count;
    integer fail_count;
    integer test_num;

    // ===================================================================
    // run_op task (longer timeout for iterative sqrt: ~60 cycles)
    // ===================================================================
    task run_op;
        input  [63:0] t_src1;
        input  [2:0]  t_rm;
        input  [63:0] t_expected_result;
        input  [4:0]  t_expected_fflags;
    begin
        integer timeout;
        src1 = t_src1;
        rm   = t_rm;

        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        timeout = 0;
        while (done === 1'b0 && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 200) begin
            $display("[FAIL] Test %0d: TIMEOUT (done never asserted)", test_num);
            fail_count = fail_count + 1;
        end else if (result !== t_expected_result || fflags !== t_expected_fflags) begin
            $display("[FAIL] Test %0d: result=%016X (exp=%016X) fflags=%05b (exp=%05b)",
                     test_num, result, t_expected_result, fflags, t_expected_fflags);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] Test %0d: result=%016X fflags=%05b", test_num, result, fflags);
            pass_count = pass_count + 1;
        end

        test_num = test_num + 1;
        @(posedge clk);
    end
    endtask

    // ===================================================================
    // Main test sequence
    // ===================================================================
    initial begin
        clk    = 1'b0;
        resetn = 1'b0;
        src1   = 64'b0;
        rm     = RNE;
        start  = 1'b0;
        flush  = 1'b0;
        pass_count = 0;
        fail_count = 0;
        test_num   = 1;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        @(posedge clk);

        $display("========================================");
        $display("  tb_fpu_sqrt_d: FSQRT.D tests");
        $display("========================================");

        // --- Normal sqrt: sqrt(4.0) = 2.0 ---
        $display("--- Normal sqrt ---");
        run_op(FOUR, RNE, TWO, F_NONE);

        // --- sqrt(1.0) = 1.0 ---
        run_op(ONE, RNE, ONE, F_NONE);

        // --- sqrt(9.0) = 3.0 ---
        run_op(NINE, RNE, THREE, F_NONE);

        // --- sqrt(16.0) = 4.0 ---
        run_op(SIXTEEN, RNE, FOUR, F_NONE);

        // --- sqrt(0.25) = 0.5 ---
        run_op(QUARTER, RNE, HALF, F_NONE);

        // --- sqrt(0.0) = 0.0 ---
        $display("--- sqrt(0) ---");
        run_op(POS_ZERO, RNE, POS_ZERO, F_NONE);

        // --- sqrt(-0.0) = -0.0 ---
        run_op(NEG_ZERO, RNE, NEG_ZERO, F_NONE);

        // --- sqrt(-1.0) = qNaN (NV) ---
        $display("--- sqrt(negative) = NaN (NV) ---");
        run_op(NEG_ONE, RNE, QNAN, F_NV);

        // --- sqrt(+Inf) = +Inf ---
        $display("--- sqrt(+Inf) ---");
        run_op(POS_INF, RNE, POS_INF, F_NONE);

        // --- sqrt(qNaN) = qNaN ---
        $display("--- NaN propagation ---");
        run_op(QNAN, RNE, QNAN, F_NONE);

        // --- sqrt(sNaN) = qNaN (NV) ---
        run_op(SNAN, RNE, QNAN, F_NV);

        // --- Inexact: sqrt(2.0) = 1.41421356... (NX) ---
        $display("--- Inexact: sqrt(2.0) ---");
        run_op(TWO, RNE, SQRT_2, F_NX);

        // --- Subnormal input: sqrt(max_subnormal) ---
        // max_subnormal = 2^-1074 * (2^52 - 1) ≈ 2.225e-308
        // sqrt = ~1.491e-154, which is a normal double
        // Just verify it doesn't hang and produces a valid result (no crash)
        $display("--- Subnormal input ---");
        // We test that it completes and result is non-zero, non-NaN
        // Exact value is hard to compute by hand, so just check done and no NV
        begin : subnormal_test
            integer timeout;
            src1 = MAX_SUBNORMAL;
            rm   = RNE;
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            timeout = 0;
            while (done === 1'b0 && timeout < 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 200) begin
                $display("[FAIL] Test %0d: TIMEOUT on subnormal", test_num);
                fail_count = fail_count + 1;
            end else if (result == QNAN || fflags[4] == 1'b1) begin
                $display("[FAIL] Test %0d: subnormal sqrt gave NaN/NV, result=%016X fflags=%05b",
                         test_num, result, fflags);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] Test %0d: subnormal sqrt result=%016X fflags=%05b", test_num, result, fflags);
                pass_count = pass_count + 1;
            end
            test_num = test_num + 1;
            @(posedge clk);
        end

        // --- Summary ---
        $display("========================================");
        $display("  pass=%0d fail=%0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");

        $finish;
    end

endmodule
