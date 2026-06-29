`timescale 1ns / 1ps

module tb_fpu_adder_d;

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
    localparam [63:0] ONE_DOT_FIVE   = 64'h3FF8000000000000;
    localparam [63:0] NEG_HALF       = 64'hBFE0000000000000;
    localparam [63:0] NEG_ONE        = 64'hBFF0000000000000;
    localparam [63:0] MAX_DOUBLE     = 64'h7FEFFFFFFFFFFFFF;
    localparam [63:0] SMALLEST_NORMAL = 64'h0010000000000000;
    localparam [63:0] HALF_SUBNORMAL = 64'h0008000000000000; // smallest_normal/2

    // 1.0 + 2^-52 = next representable after 1.0 (ULP)
    localparam [63:0] ONE_PLUS_ULP   = 64'h3FF0000000000001;

    // 2^-53 as double: exp = 1023-53 = 970 = 0x3CA, frac = 0
    localparam [63:0] TWO_NEG_53     = 64'h3CA0000000000000;

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
    reg         is_sub;
    reg  [2:0]  rm;
    reg         start;
    reg         flush;
    wire [63:0] result;
    wire [4:0]  fflags;
    wire        done;

    // ===================================================================
    // DUT instantiation
    // ===================================================================
    fpu_adder_d dut (
        .clk    (clk),
        .resetn (resetn),
        .src1   (src1),
        .src2   (src2),
        .is_sub (is_sub),
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
    // run_op task: drive inputs, wait for done, compare results
    // ===================================================================
    task run_op;
        input  [63:0] t_src1;
        input  [63:0] t_src2;
        input         t_is_sub;
        input  [2:0]  t_rm;
        input  [63:0] t_expected_result;
        input  [4:0]  t_expected_fflags;
    begin
        integer timeout;
        src1   = t_src1;
        src2   = t_src2;
        is_sub = t_is_sub;
        rm     = t_rm;

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
        is_sub = 1'b0;
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
        $display("  tb_fpu_adder_d: FADD.D / FSUB.D tests");
        $display("========================================");

        // --- Normal add: 1.0 + 2.0 = 3.0 ---
        $display("--- Normal add ---");
        run_op(ONE, TWO, 1'b0, RNE, THREE, F_NONE);

        // --- Normal sub: 3.0 - 1.0 = 2.0 ---
        $display("--- Normal sub ---");
        run_op(THREE, ONE, 1'b1, RNE, TWO, F_NONE);

        // --- Add with different signs: 1.5 + (-0.5) = 1.0 ---
        $display("--- Add with different signs ---");
        run_op(ONE_DOT_FIVE, NEG_HALF, 1'b0, RNE, ONE, F_NONE);

        // --- Sub resulting negative: 1.0 - 2.0 = -1.0 ---
        $display("--- Sub resulting negative ---");
        run_op(ONE, TWO, 1'b1, RNE, NEG_ONE, F_NONE);

        // --- NaN propagation ---
        $display("--- NaN propagation ---");
        run_op(QNAN, ONE, 1'b0, RNE, QNAN, F_NONE);
        run_op(SNAN, ONE, 1'b0, RNE, QNAN, F_NV);
        run_op(ONE, QNAN, 1'b0, RNE, QNAN, F_NONE);

        // --- Inf + Inf = Inf ---
        $display("--- Inf + Inf ---");
        run_op(POS_INF, POS_INF, 1'b0, RNE, POS_INF, F_NONE);

        // --- Inf + (-Inf) = qNaN (NV) ---
        $display("--- Inf + (-Inf) ---");
        run_op(POS_INF, NEG_INF, 1'b0, RNE, QNAN, F_NV);

        // --- Zero + Zero ---
        $display("--- Zero + Zero ---");
        run_op(POS_ZERO, POS_ZERO, 1'b0, RNE, POS_ZERO, F_NONE);

        // --- +0 + (-0) RNE => +0 ---
        $display("--- +0 + (-0) RNE ---");
        run_op(POS_ZERO, NEG_ZERO, 1'b0, RNE, POS_ZERO, F_NONE);

        // --- Overflow: max + max -> Inf (OF, NX) ---
        $display("--- Overflow ---");
        run_op(MAX_DOUBLE, MAX_DOUBLE, 1'b0, RNE, POS_INF, F_OF_NX);

        // --- Rounding: 1.0 + 2^-53 (midpoint between 1.0 and 1.0+ULP) ---
        $display("--- Rounding: 1.0 + 2^-53 ---");
        run_op(ONE, TWO_NEG_53, 1'b0, RNE, ONE, F_NX);
        run_op(ONE, TWO_NEG_53, 1'b0, RTZ, ONE, F_NX);
        run_op(ONE, TWO_NEG_53, 1'b0, RDN, ONE, F_NX);
        run_op(ONE, TWO_NEG_53, 1'b0, RUP, ONE_PLUS_ULP, F_NX);
        run_op(ONE, TWO_NEG_53, 1'b0, RMM, ONE_PLUS_ULP, F_NX);

        // --- Overflow with RTZ (should give MAX_DOUBLE) ---
        $display("--- Overflow with RTZ ---");
        run_op(MAX_DOUBLE, MAX_DOUBLE, 1'b0, RTZ, MAX_DOUBLE, F_OF_NX);

        // --- Overflow with RDN (positive, should give MAX_DOUBLE) ---
        $display("--- Overflow with RDN ---");
        run_op(MAX_DOUBLE, MAX_DOUBLE, 1'b0, RDN, MAX_DOUBLE, F_OF_NX);

        // --- Overflow with RUP (positive, should give Inf) ---
        $display("--- Overflow with RUP ---");
        run_op(MAX_DOUBLE, MAX_DOUBLE, 1'b0, RUP, POS_INF, F_OF_NX);

        // --- -Inf + -Inf = -Inf ---
        $display("--- -Inf + -Inf ---");
        run_op(NEG_INF, NEG_INF, 1'b0, RNE, NEG_INF, F_NONE);

        // --- Inf - (-Inf) => Inf + Inf = Inf ---
        $display("--- Inf - (-Inf) ---");
        run_op(POS_INF, NEG_INF, 1'b1, RNE, POS_INF, F_NONE);

        // --- -Inf + Inf = qNaN (NV) ---
        $display("--- -Inf + Inf ---");
        run_op(NEG_INF, POS_INF, 1'b0, RNE, QNAN, F_NV);

        // --- Zero + normal = normal ---
        $display("--- Zero + normal ---");
        run_op(POS_ZERO, ONE, 1'b0, RNE, ONE, F_NONE);
        run_op(ONE, POS_ZERO, 1'b0, RNE, ONE, F_NONE);

        // --- +0 + (-0) with RDN => -0 ---
        $display("--- +0 + (-0) RDN => -0 ---");
        run_op(POS_ZERO, NEG_ZERO, 1'b0, RDN, NEG_ZERO, F_NONE);

        // --- NaN - NaN = qNaN ---
        $display("--- NaN - NaN ---");
        run_op(QNAN, QNAN, 1'b1, RNE, QNAN, F_NONE);

        // --- Inf - Inf = qNaN (NV) ---
        $display("--- Inf - Inf ---");
        run_op(POS_INF, POS_INF, 1'b1, RNE, QNAN, F_NV);

        // --- Subnormal + Subnormal = smallest_normal ---
        $display("--- Subnormal + Subnormal = smallest_normal ---");
        run_op(HALF_SUBNORMAL, HALF_SUBNORMAL, 1'b0, RNE, SMALLEST_NORMAL, F_NONE);

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
