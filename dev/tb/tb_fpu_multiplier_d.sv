`timescale 1ns / 1ps

module tb_fpu_multiplier_d;

    // ===================================================================
    // IEEE 754 double-precision constants
    // ===================================================================
    localparam [63:0] QNAN           = 64'h7FF8000000000000;
    localparam [63:0] SNAN           = 64'h7FF0000000000001;
    localparam [63:0] POS_INF        = 64'h7FF0000000000000;
    localparam [63:0] NEG_INF        = 64'hFFF0000000000000;
    localparam [63:0] POS_ZERO       = 64'h0000000000000000;
    localparam [63:0] NEG_ZERO       = 64'h8000000000000000;
    localparam [63:0] ONE            = 64'h3FF0000000000000;
    localparam [63:0] TWO            = 64'h4000000000000000;
    localparam [63:0] THREE          = 64'h4008000000000000;
    localparam [63:0] HALF           = 64'h3FE0000000000000;
    localparam [63:0] SIX            = 64'h4018000000000000;
    localparam [63:0] NEG_ONE        = 64'hBFF0000000000000;
    localparam [63:0] NEG_TWO        = 64'hC000000000000000;
    localparam [63:0] NEG_HALF       = 64'hBFE0000000000000;
    localparam [63:0] MAX_DOUBLE     = 64'h7FEFFFFFFFFFFFFF;
    localparam [63:0] SMALLEST_NORMAL = 64'h0010000000000000;

    // Rounding mode constants
    localparam [2:0] RNE = 3'b000;
    localparam [2:0] RTZ = 3'b001;
    localparam [2:0] RDN = 3'b010;
    localparam [2:0] RUP = 3'b011;
    localparam [2:0] RMM = 3'b100;

    // fflags: {NV, DZ, OF, UF, NX}
    localparam [4:0] F_NONE   = 5'b00000;
    localparam [4:0] F_NV     = 5'b10000;
    localparam [4:0] F_OF_NX  = 5'b00101;
    localparam [4:0] F_UF_NX  = 5'b00011;
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
    reg  [63:0] src2;
    reg  [2:0]  rm;
    reg         start;
    reg         flush;
    wire [63:0] result;
    wire [4:0]  fflags;
    wire        done;

    // ===================================================================
    // DUT instantiation
    // ===================================================================
    fpu_multiplier_d dut (
        .clk    (clk),
        .resetn (resetn),
        .src1   (src1),
        .src2   (src2),
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
    // run_op task
    // ===================================================================
    task run_op;
        input  [63:0] t_src1;
        input  [63:0] t_src2;
        input  [2:0]  t_rm;
        input  [63:0] t_expected_result;
        input  [4:0]  t_expected_fflags;
    begin
        integer timeout;
        src1 = t_src1;
        src2 = t_src2;
        rm   = t_rm;

        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        timeout = 0;
        while (done === 1'b0 && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 100) begin
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
        src2   = 64'b0;
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
        $display("  tb_fpu_multiplier_d: FMUL.D tests");
        $display("========================================");

        // --- Normal multiply: 3.0 * 2.0 = 6.0 ---
        $display("--- Normal multiply ---");
        run_op(THREE, TWO, RNE, SIX, F_NONE);

        // --- 2.0 * 0.5 = 1.0 ---
        run_op(TWO, HALF, RNE, ONE, F_NONE);

        // --- (-1.0) * 2.0 = -2.0 ---
        run_op(NEG_ONE, TWO, RNE, NEG_TWO, F_NONE);

        // --- (-0.5) * (-2.0) = 1.0 ---
        run_op(NEG_HALF, NEG_TWO, RNE, ONE, F_NONE);

        // --- 1.0 * 1.0 = 1.0 ---
        run_op(ONE, ONE, RNE, ONE, F_NONE);

        // --- NaN propagation ---
        $display("--- NaN propagation ---");
        run_op(QNAN, ONE, RNE, QNAN, F_NONE);
        run_op(SNAN, ONE, RNE, QNAN, F_NV);
        run_op(ONE, QNAN, RNE, QNAN, F_NONE);

        // --- Inf * 0 = qNaN (NV) ---
        $display("--- Inf * 0 ---");
        run_op(POS_INF, POS_ZERO, RNE, QNAN, F_NV);
        run_op(POS_ZERO, POS_INF, RNE, QNAN, F_NV);

        // --- Inf * 2.0 = Inf ---
        $display("--- Inf * normal ---");
        run_op(POS_INF, TWO, RNE, POS_INF, F_NONE);
        run_op(NEG_INF, TWO, RNE, NEG_INF, F_NONE);

        // --- 0 * normal = 0 ---
        $display("--- Zero * normal ---");
        run_op(POS_ZERO, ONE, RNE, POS_ZERO, F_NONE);
        run_op(ONE, POS_ZERO, RNE, POS_ZERO, F_NONE);
        run_op(NEG_ZERO, ONE, RNE, NEG_ZERO, F_NONE);

        // --- 0 * 0 = 0 ---
        run_op(POS_ZERO, POS_ZERO, RNE, POS_ZERO, F_NONE);

        // --- Overflow: max * max -> Inf (OF, NX) ---
        $display("--- Overflow ---");
        run_op(MAX_DOUBLE, MAX_DOUBLE, RNE, POS_INF, F_OF_NX);

        // --- Overflow: max * 2 -> Inf (OF, NX) ---
        run_op(MAX_DOUBLE, TWO, RNE, POS_INF, F_OF_NX);

        // --- Overflow with RTZ -> MAX_DOUBLE ---
        run_op(MAX_DOUBLE, MAX_DOUBLE, RTZ, MAX_DOUBLE, F_OF_NX);

        // --- Underflow: smallest_normal * smallest_normal -> 0 (UF, NX) ---
        // This verifies the Task 6 fix: UF is set, NOT OF
        $display("--- Underflow (verify UF not OF) ---");
        run_op(SMALLEST_NORMAL, SMALLEST_NORMAL, RNE, POS_ZERO, F_UF_NX);

        // --- Underflow with RTZ -> 0 (UF, NX) ---
        run_op(SMALLEST_NORMAL, SMALLEST_NORMAL, RTZ, POS_ZERO, F_UF_NX);

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
