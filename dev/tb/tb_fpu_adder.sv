`timescale 1ns / 1ps

module tb_fpu_adder;

    // ===================================================================
    // IEEE 754 single-precision constants
    // ===================================================================
    localparam [31:0] QNAN           = 32'h7FC00000;
    localparam [31:0] SNAN           = 32'h7F800001;
    localparam [31:0] POS_INF        = 32'h7F800000;
    localparam [31:0] NEG_INF        = 32'hFF800000;
    localparam [31:0] POS_ZERO       = 32'h00000000;
    localparam [31:0] NEG_ZERO       = 32'h80000000;
    localparam [31:0] ONE            = 32'h3F800000;
    localparam [31:0] TWO            = 32'h40000000;
    localparam [31:0] THREE          = 32'h40400000;
    localparam [31:0] HALF           = 32'h3F000000;
    localparam [31:0] ONE_DOT_FIVE   = 32'h3FC00000;
    localparam [31:0] MAX_FLOAT      = 32'h7F7FFFFF;
    localparam [31:0] SMALLEST_NORMAL = 32'h00800000;

    // 1.0 + 2^-24 = 1.0 with LSB set in fraction (next representable after 1.0)
    localparam [31:0] ONE_PLUS_ULP   = 32'h3F800001;

    // Rounding mode constants
    localparam [2:0] RNE = 3'b000;
    localparam [2:0] RTZ = 3'b001;
    localparam [2:0] RDN = 3'b010;
    localparam [2:0] RUP = 3'b011;
    localparam [2:0] RMM = 3'b100;

    // fflags: {NV, DZ, OF, UF, NX}
    localparam [4:0] F_NONE = 5'b00000;
    localparam [4:0] F_NV   = 5'b10000;
    localparam [4:0] F_OF   = 5'b00100;
    localparam [4:0] F_UF   = 5'b00010;
    localparam [4:0] F_NX   = 5'b00001;
    localparam [4:0] F_OF_NX = 5'b00101;
    localparam [4:0] F_UF_NX = 5'b00011;

    // ===================================================================
    // Clock and reset
    // ===================================================================
    reg        clk;
    reg        resetn;

    always #5 clk = ~clk;   // 10ns period, 5ns half-period

    // ===================================================================
    // DUT signals
    // ===================================================================
    reg  [31:0] src1;
    reg  [31:0] src2;
    reg         is_sub;
    reg  [2:0]  rm;
    reg         start;
    wire [31:0] result;
    wire [4:0]  fflags;
    wire        done;

    // ===================================================================
    // DUT instantiation
    // ===================================================================
    fpu_adder dut (
        .clk    (clk),
        .resetn (resetn),
        .src1   (src1),
        .src2   (src2),
        .is_sub (is_sub),
        .rm     (rm),
        .start  (start),
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
        input  [31:0] t_src1;
        input  [31:0] t_src2;
        input         t_is_sub;
        input  [2:0]  t_rm;
        input  [31:0] t_expected_result;
        input  [4:0]  t_expected_fflags;
    begin
        integer timeout;
        // Drive inputs
        src1   = t_src1;
        src2   = t_src2;
        is_sub = t_is_sub;
        rm     = t_rm;

        // Assert start for 1 cycle
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // Wait for done with timeout
        timeout = 0;
        while (done === 1'b0 && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 100) begin
            $display("[FAIL] Test %0d: TIMEOUT (done never asserted)", test_num);
            fail_count = fail_count + 1;
        end else if (result !== t_expected_result || fflags !== t_expected_fflags) begin
            $display("[FAIL] Test %0d: result=%08X (exp=%08X) fflags=%05b (exp=%05b)",
                     test_num, result, t_expected_result, fflags, t_expected_fflags);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] Test %0d: result=%08X fflags=%05b", test_num, result, fflags);
            pass_count = pass_count + 1;
        end

        test_num = test_num + 1;
        // Wait one extra cycle for clean state
        @(posedge clk);
    end
    endtask

    // ===================================================================
    // Main test sequence
    // ===================================================================
    initial begin
        // Initialize
        clk   = 1'b0;
        resetn = 1'b0;
        src1  = 32'b0;
        src2  = 32'b0;
        is_sub = 1'b0;
        rm    = RNE;
        start = 1'b0;
        pass_count = 0;
        fail_count = 0;
        test_num   = 1;

        // Assert reset for 5 cycles
        repeat (5) @(posedge clk);
        resetn = 1'b1;
        @(posedge clk);

        $display("========================================");
        $display("  tb_fpu_adder: FADD.S / FSUB.S tests");
        $display("========================================");

        // ---------------------------------------------------------------
        // a. Normal add: 1.0 + 2.0 = 3.0
        // ---------------------------------------------------------------
        $display("--- Normal add ---");
        run_op(ONE, TWO, 1'b0, RNE, THREE, F_NONE);

        // ---------------------------------------------------------------
        // b. Normal sub: 3.0 - 1.0 = 2.0
        // ---------------------------------------------------------------
        $display("--- Normal sub ---");
        run_op(THREE, ONE, 1'b1, RNE, TWO, F_NONE);

        // ---------------------------------------------------------------
        // c. Add with different signs: 1.5 + (-0.5) = 1.0
        //    -0.5 = 0xBF000000
        // ---------------------------------------------------------------
        $display("--- Add with different signs ---");
        run_op(ONE_DOT_FIVE, 32'hBF000000, 1'b0, RNE, ONE, F_NONE);

        // ---------------------------------------------------------------
        // d. Sub resulting negative: 1.0 - 2.0 = -1.0
        //    -1.0 = 0xBF800000
        // ---------------------------------------------------------------
        $display("--- Sub resulting negative ---");
        run_op(ONE, TWO, 1'b1, RNE, 32'hBF800000, F_NONE);

        // ---------------------------------------------------------------
        // e. NaN + anything = qNaN
        //    qNaN input does NOT set NV (only sNaN sets NV per IEEE 754)
        // ---------------------------------------------------------------
        $display("--- NaN propagation ---");
        // qNaN + 1.0 → qNaN, no NV
        run_op(QNAN, ONE, 1'b0, RNE, QNAN, F_NONE);
        // sNaN + 1.0 → qNaN, NV=1
        run_op(SNAN, ONE, 1'b0, RNE, QNAN, F_NV);
        // 1.0 + qNaN → qNaN, no NV
        run_op(ONE, QNAN, 1'b0, RNE, QNAN, F_NONE);

        // ---------------------------------------------------------------
        // f. Inf + Inf = Inf
        // ---------------------------------------------------------------
        $display("--- Inf + Inf ---");
        run_op(POS_INF, POS_INF, 1'b0, RNE, POS_INF, F_NONE);

        // ---------------------------------------------------------------
        // g. Inf + (-Inf) = qNaN (NV=1)
        // ---------------------------------------------------------------
        $display("--- Inf + (-Inf) ---");
        run_op(POS_INF, NEG_INF, 1'b0, RNE, QNAN, F_NV);

        // ---------------------------------------------------------------
        // h. 0 + 0 = +0
        // ---------------------------------------------------------------
        $display("--- Zero + Zero ---");
        run_op(POS_ZERO, POS_ZERO, 1'b0, RNE, POS_ZERO, F_NONE);

        // ---------------------------------------------------------------
        // i. +0 + (-0) = +0 (RNE)
        // ---------------------------------------------------------------
        $display("--- +0 + (-0) RNE ---");
        run_op(POS_ZERO, NEG_ZERO, 1'b0, RNE, POS_ZERO, F_NONE);

        // ---------------------------------------------------------------
        // j. Overflow: max_float + max_float -> Inf (OF=1, NX=1)
        // ---------------------------------------------------------------
        $display("--- Overflow ---");
        run_op(MAX_FLOAT, MAX_FLOAT, 1'b0, RNE, POS_INF, F_OF_NX);

        // ---------------------------------------------------------------
        // k. Underflow: smallest_normal/2 - smallest_normal/2 = +0
        //    smallest_normal/2 is subnormal: 0x00400000
        // ---------------------------------------------------------------
        $display("--- Underflow (subnormal cancellation) ---");
        run_op(32'h00400000, 32'h00400000, 1'b1, RNE, POS_ZERO, F_NONE);

        // ---------------------------------------------------------------
        // l. Rounding: 1.0 + 2^-24 with all 5 rounding modes
        //    2^-24 as float = 0x33800000
        //    1.0 + 2^-24 is exactly the midpoint between 1.0 and 1.0+ULP
        //    RNE: round to even → 1.0 (LSB=0, even), NX=1
        //    RTZ: round toward zero → 1.0, NX=1
        //    RDN: round toward -inf → 1.0, NX=1
        //    RUP: round toward +inf → 1.0+ULP, NX=1
        //    RMM: round to max magnitude → 1.0+ULP, NX=1
        // ---------------------------------------------------------------
        $display("--- Rounding: 1.0 + 2^-24 ---");
        run_op(ONE, 32'h33800000, 1'b0, RNE, ONE, F_NX);
        run_op(ONE, 32'h33800000, 1'b0, RTZ, ONE, F_NX);
        run_op(ONE, 32'h33800000, 1'b0, RDN, ONE, F_NX);
        run_op(ONE, 32'h33800000, 1'b0, RUP, ONE_PLUS_ULP, F_NX);
        run_op(ONE, 32'h33800000, 1'b0, RMM, ONE_PLUS_ULP, F_NX);

        // ---------------------------------------------------------------
        // Additional: rounding that actually exercises rounding logic
        //   1.0 + 1.5*2^-24 (midpoint between 1.0 and 1.0+ULP)
        //   1.5*2^-24 = 2^-24 + 2^-25
        //   2^-25 as float: exp=127-25=102=0x66, frac=0 => 0x33000000
        //   But we can't represent 1.5*2^-24 exactly as a single float.
        //   Instead, test: (1.0 + 2^-23) + 2^-23 where 2^-23 = 0x34000000
        //   1.0 + 2^-23 = 1.0 with bit 22 set = 0x3F800002 (exact)
        //   Then + 2^-23 = 1.0 with bit 22 set twice = 0x3F800004 (exact)
        //   This doesn't exercise rounding either.
        //
        //   Better: test overflow with RTZ (should give MAX_FLOAT, not Inf)
        // ---------------------------------------------------------------
        $display("--- Overflow with RTZ (should give MAX_FLOAT) ---");
        run_op(MAX_FLOAT, MAX_FLOAT, 1'b0, RTZ, MAX_FLOAT, F_OF_NX);

        $display("--- Overflow with RDN (positive, should give MAX_FLOAT) ---");
        run_op(MAX_FLOAT, MAX_FLOAT, 1'b0, RDN, MAX_FLOAT, F_OF_NX);

        $display("--- Overflow with RUP (positive, should give Inf) ---");
        run_op(MAX_FLOAT, MAX_FLOAT, 1'b0, RUP, POS_INF, F_OF_NX);

        // ---------------------------------------------------------------
        // Additional: -Inf + -Inf = -Inf
        // ---------------------------------------------------------------
        $display("--- -Inf + -Inf ---");
        run_op(NEG_INF, NEG_INF, 1'b0, RNE, NEG_INF, F_NONE);

        // ---------------------------------------------------------------
        // Additional: Inf - (-Inf) = Inf (is_sub flips sign of src2)
        // ---------------------------------------------------------------
        $display("--- Inf - (-Inf) => Inf + Inf = Inf ---");
        run_op(POS_INF, NEG_INF, 1'b1, RNE, POS_INF, F_NONE);

        // ---------------------------------------------------------------
        // Additional: -Inf + Inf = qNaN (NV=1)
        // ---------------------------------------------------------------
        $display("--- -Inf + Inf ---");
        run_op(NEG_INF, POS_INF, 1'b0, RNE, QNAN, F_NV);

        // ---------------------------------------------------------------
        // Additional: 0 + normal = normal
        // ---------------------------------------------------------------
        $display("--- Zero + normal ---");
        run_op(POS_ZERO, ONE, 1'b0, RNE, ONE, F_NONE);
        run_op(ONE, POS_ZERO, 1'b0, RNE, ONE, F_NONE);

        // ---------------------------------------------------------------
        // Additional: +0 + (-0) with RDN => -0
        // ---------------------------------------------------------------
        $display("--- +0 + (-0) RDN => -0 ---");
        run_op(POS_ZERO, NEG_ZERO, 1'b0, RDN, NEG_ZERO, F_NONE);

        // ---------------------------------------------------------------
        // Additional: NaN - NaN = qNaN (sNaN sets NV, qNaN does not)
        // ---------------------------------------------------------------
        $display("--- NaN - NaN ---");
        run_op(QNAN, QNAN, 1'b1, RNE, QNAN, F_NONE);

        // ---------------------------------------------------------------
        // Additional: Inf - Inf = qNaN (NV=1)
        // ---------------------------------------------------------------
        $display("--- Inf - Inf ---");
        run_op(POS_INF, POS_INF, 1'b1, RNE, QNAN, F_NV);

        // ---------------------------------------------------------------
        // Additional: subnormal add
        //    smallest_normal/2 = 0x00400000 (subnormal)
        //    smallest_normal/2 + smallest_normal/2 = smallest_normal
        // ---------------------------------------------------------------
        $display("--- Subnormal + Subnormal = smallest_normal ---");
        run_op(32'h00400000, 32'h00400000, 1'b0, RNE, SMALLEST_NORMAL, F_NONE);

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
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
