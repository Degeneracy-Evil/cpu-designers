`timescale 1ns / 1ps

// ============================================================
// tb_fpu_sqrt.sv — Standalone unit testbench for fpu_sqrt (FSQRT.S)
// ============================================================
//
// Directly instantiates fpu_sqrt. No core_top, no bus, no COE files.
// Tests: sqrt of normal, zero, negative, Inf, NaN, subnormal, rounding.
//
// ============================================================

module tb_fpu_sqrt;

    // ── IEEE 754 single-precision constants ──
    localparam [31:0] QNAN           = 32'h7FC00000;
    localparam [31:0] SNAN           = 32'h7F800001;
    localparam [31:0] POS_INF        = 32'h7F800000;
    localparam [31:0] NEG_INF        = 32'hFF800000;
    localparam [31:0] POS_ZERO       = 32'h00000000;
    localparam [31:0] NEG_ZERO       = 32'h80000000;
    localparam [31:0] ONE            = 32'h3F800000;
    localparam [31:0] TWO            = 32'h40000000;
    localparam [31:0] FOUR           = 32'h40800000;
    localparam [31:0] HALF           = 32'h3F000000;
    localparam [31:0] QUARTER        = 32'h3E800000;
    localparam [31:0] MAX_FLOAT      = 32'h7F7FFFFF;
    localparam [31:0] SMALLEST_NORMAL = 32'h00800000;
    localparam [31:0] NEG_ONE        = 32'hBF800000;

    // ── Rounding mode constants ──
    localparam [2:0] RNE = 3'b000;
    localparam [2:0] RTZ = 3'b001;
    localparam [2:0] RDN = 3'b010;
    localparam [2:0] RUP = 3'b011;
    localparam [2:0] RMM = 3'b100;

    // ── fflags bit positions: {NV, DZ, OF, UF, NX} ──

    // ── Clock & reset ──
    reg        clk;
    reg        resetn;

    always #5 clk = ~clk;   // 10 ns period, 5 ns half-period

    // ── DUT wires ──
    reg  [31:0] src1;
    reg  [2:0]  rm;
    reg        start;
    wire [31:0] result;
    wire [4:0]  fflags;
    wire        done;

    // ── Scoreboard ──
    integer pass_count;
    integer fail_count;

    // ── Instantiate DUT ──
    fpu_sqrt dut (
        .clk    (clk),
        .resetn (resetn),
        .src1   (src1),
        .rm     (rm),
        .start  (start),
        .result (result),
        .fflags (fflags),
        .done   (done)
    );

    // ── run_op task ──
    // Drives src1, rm; asserts start for 1 cycle; waits for done
    // (timeout 500 cycles); compares result & fflags; updates counters.
    task run_op;
        input  [31:0] src1_val;
        input  [2:0]  rm_val;
        input  [31:0] expected_result;
        input  [4:0]  expected_fflags;
        reg    [31:0] got_result;
        reg    [4:0]  got_fflags;
        integer timeout;
        begin
            // Drive inputs
            src1  = src1_val;
            rm    = rm_val;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            // Wait for done with timeout
            timeout = 0;
            while (done === 1'b0 && timeout < 500) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 500) begin
                $display("FAIL: sqrt(0x%08H) rm=%0d — TIMEOUT after 500 cycles",
                         src1_val, rm_val);
                fail_count = fail_count + 1;
            end else begin
                // Capture on the cycle done==1
                got_result = result;
                got_fflags = fflags;

                if (got_result !== expected_result || got_fflags !== expected_fflags) begin
                    $display("FAIL: sqrt(0x%08H) rm=%0d — expected 0x%08H fflags=%05b, got 0x%08H fflags=%05b",
                             src1_val, rm_val,
                             expected_result, expected_fflags,
                             got_result, got_fflags);
                    fail_count = fail_count + 1;
                end else begin
                    $display("PASS: sqrt(0x%08H) rm=%0d = 0x%08H fflags=%05b",
                             src1_val, rm_val, got_result, got_fflags);
                    pass_count = pass_count + 1;
                end
            end

            // Wait one more cycle for FSM to return to IDLE
            @(posedge clk);
        end
    endtask

    // ── Main stimulus ──
    initial begin
        clk   = 1'b0;
        resetn = 1'b0;
        src1  = 32'b0;
        rm    = RNE;
        start = 1'b0;
        pass_count = 0;
        fail_count = 0;

        // Assert reset for 5 cycles
        repeat (5) @(posedge clk);
        resetn = 1'b1;
        @(posedge clk);

        // ────────────────────────────────────────────
        // a. sqrt(1.0) = 1.0
        // ────────────────────────────────────────────
        run_op(ONE, RNE, ONE, 5'b00000);

        // ────────────────────────────────────────────
        // b. sqrt(4.0) = 2.0
        // ────────────────────────────────────────────
        run_op(FOUR, RNE, TWO, 5'b00000);

        // ────────────────────────────────────────────
        // c. sqrt(0.25) = 0.5
        // ────────────────────────────────────────────
        run_op(QUARTER, RNE, HALF, 5'b00000);

        // ────────────────────────────────────────────
        // d. sqrt(2.0) = 1.4142... (RNE)
        //    Exact sqrt(2) ≈ 1.414213562...
        //    SP RNE: 0x3FB504F3, inexact (NX=1)
        // ────────────────────────────────────────────
        run_op(TWO, RNE, 32'h3FB504F3, 5'b00001);

        // ────────────────────────────────────────────
        // e. sqrt(+0) = +0
        // ────────────────────────────────────────────
        run_op(POS_ZERO, RNE, POS_ZERO, 5'b00000);

        // ────────────────────────────────────────────
        // f. sqrt(-1.0) = qNaN, NV=1
        // ────────────────────────────────────────────
        run_op(NEG_ONE, RNE, QNAN, 5'b10000);

        // ────────────────────────────────────────────
        // g. sqrt(+Inf) = +Inf
        // ────────────────────────────────────────────
        run_op(POS_INF, RNE, POS_INF, 5'b00000);

        // ────────────────────────────────────────────
        // h. sqrt(-Inf) = qNaN, NV=1
        // ────────────────────────────────────────────
        run_op(NEG_INF, RNE, QNAN, 5'b10000);

        // ────────────────────────────────────────────
        // i. sqrt(sNaN) = qNaN, NV=1
        // ────────────────────────────────────────────
        run_op(SNAN, RNE, QNAN, 5'b10000);

        // ────────────────────────────────────────────
        // i2. sqrt(qNaN) = qNaN, NV=0
        // ────────────────────────────────────────────
        run_op(QNAN, RNE, QNAN, 5'b00000);

        // ────────────────────────────────────────────
        // j. sqrt(subnormal) — sqrt(2^-127) = 2^(-63.5)
        //    0x00400000 = 2^-127 (subnormal)
        //    sqrt(2^-127) = sqrt(2) * 2^-64
        //    Result: 0x1FB504F3, inexact (NX=1)
        // ────────────────────────────────────────────
        run_op(32'h00400000, RNE, 32'h1FB504F3, 5'b00001);

        // ────────────────────────────────────────────
        // j2. sqrt(largest subnormal 0x007FFFFF)
        //     Value ≈ (2^23-1)*2^-149 ≈ 2^-126 * (1 - 2^-23)
        //     sqrt ≈ 1.0842021e-19 = 0x1FFFFFFF, inexact (NX=1)
        // ────────────────────────────────────────────
        run_op(32'h007FFFFF, RNE, 32'h1FFFFFFF, 5'b00001);

        // ────────────────────────────────────────────
        // j3. sqrt(smallest subnormal 0x00000001) = sqrt(2^-149)
        //     = 2^-74.5 = sqrt(2) * 2^-75 ≈ 3.743e-23
        //     Result: 0x1A3504F3, inexact (NX=1)
        //     BUG-FIX: subnormal exponent was wrong (exp 53 instead of 52)
        // ────────────────────────────────────────────
        run_op(32'h00000001, RNE, 32'h1A3504F3, 5'b00001);

        // ────────────────────────────────────────────
        // j4. sqrt(0x00100000) = sqrt(2^-129) = 2^-64.5
        //     = sqrt(2) * 2^-65, lz_c=2 (even)
        //     Result: 0x1F3504F3, inexact (NX=1)
        // ────────────────────────────────────────────
        run_op(32'h00100000, RNE, 32'h1F3504F3, 5'b00001);

        // ────────────────────────────────────────────
        // j5. sqrt(0x00200000) = sqrt(2^-128) = 2^-64
        //     lz_c=1 (odd) — exact result
        //     Result: 0x1F800000, exact (NX=0)
        // ────────────────────────────────────────────
        run_op(32'h00200000, RNE, 32'h1F800000, 5'b00000);

        // ────────────────────────────────────────────
        // j6. sqrt(0x00000002) = sqrt(2^-148) = 2^-74
        //     lz_c=21 (odd) — exact result
        //     Result: 0x1A800000, exact (NX=0)
        // ────────────────────────────────────────────
        run_op(32'h00000002, RNE, 32'h1A800000, 5'b00000);

        // ────────────────────────────────────────────
        // j7. sqrt(0x00010000) = sqrt(2^-133) = 2^-66.5
        //     = sqrt(2) * 2^-67, lz_c=6 (even)
        //     Result: 0x1E3504F3, inexact (NX=1)
        // ────────────────────────────────────────────
        run_op(32'h00010000, RNE, 32'h1E3504F3, 5'b00001);

        // ────────────────────────────────────────────
        // j8. sqrt(0x00000100) = sqrt(2^-141) = 2^-70.5
        //     = sqrt(2) * 2^-71, lz_c=14 (even)
        //     Result: 0x1C3504F3, inexact (NX=1)
        // ────────────────────────────────────────────
        run_op(32'h00000100, RNE, 32'h1C3504F3, 5'b00001);

        // ────────────────────────────────────────────
        // j9. Random subnormal tests (various lz_c parities)
        //     Verifies correct sqrt for subnormal inputs across the range
        // ────────────────────────────────────────────
        run_op(32'h000E4019, RNE, 32'h1F2AD5E6, 5'b00001);
        run_op(32'h0003338E, RNE, 32'h1EA1F194, 5'b00001);
        run_op(32'h001F589E, RNE, 32'h1F7D5F03, 5'b00001);
        run_op(32'h001C922C, RNE, 32'h1F71E538, 5'b00001);
        run_op(32'h0011DC61, RNE, 32'h1F3F41A7, 5'b00001);
        run_op(32'h000D1E90, RNE, 32'h1F23EA88, 5'b00001);
        run_op(32'h007232F1, RNE, 32'h1FF1CE33, 5'b00001);
        run_op(32'h0045CE93, RNE, 32'h1FBD0DA5, 5'b00001);
        run_op(32'h00360189, RNE, 32'h1FA6493E, 5'b00001);
        run_op(32'h00041175, RNE, 32'h1EB68E4A, 5'b00001);
        run_op(32'h0051D8BD, RNE, 32'h1FCCB551, 5'b00001);
        run_op(32'h005EEB21, RNE, 32'h1FDC733B, 5'b00001);
        run_op(32'h0023342A, RNE, 32'h1F864135, 5'b00001);
        run_op(32'h005E44B1, RNE, 32'h1FDBB19F, 5'b00001);
        run_op(32'h00569E17, RNE, 32'h1FD2970F, 5'b00001);
        run_op(32'h005ECE34, RNE, 32'h1FDC51A2, 5'b00001);
        run_op(32'h004B9543, RNE, 32'h1FC4B82B, 5'b00001);
        run_op(32'h000B20D0, RNE, 32'h1F16F719, 5'b00001);
        run_op(32'h0003D066, RNE, 32'h1EB0C308, 5'b00001);
        run_op(32'h000BFE35, RNE, 32'h1F1CB8BA, 5'b00001);

        // ────────────────────────────────────────────
        // k. Rounding: sqrt(2.0) with RTZ (truncate)
        //    Same as RNE for this value: 0x3FB504F3, NX=1
        // ────────────────────────────────────────────
        run_op(TWO, RTZ, 32'h3FB504F3, 5'b00001);

        // ────────────────────────────────────────────
        // k2. Rounding: sqrt(2.0) with RUP (round toward +∞)
        //     Rounds up to 0x3FB504F4, NX=1
        // ────────────────────────────────────────────
        run_op(TWO, RUP, 32'h3FB504F4, 5'b00001);

        // ────────────────────────────────────────────
        // k3. Rounding: sqrt(2.0) with RDN (round toward -∞)
        //     Same as RTZ for positive: 0x3FB504F3, NX=1
        // ────────────────────────────────────────────
        run_op(TWO, RDN, 32'h3FB504F3, 5'b00001);

        // ────────────────────────────────────────────
        // k4. Rounding: sqrt(2.0) with RMM (round to nearest, ties to max magnitude)
        //     No tie here, same as RNE: 0x3FB504F3, NX=1
        // ────────────────────────────────────────────
        run_op(TWO, RMM, 32'h3FB504F3, 5'b00001);

        // ────────────────────────────────────────────
        // Additional: sqrt(-0) = -0
        // ────────────────────────────────────────────
        run_op(NEG_ZERO, RNE, NEG_ZERO, 5'b00000);

        // ────────────────────────────────────────────
        // Additional: sqrt(max_float) — should be large but finite
        //    sqrt(3.4028235e38) ≈ 1.8446743e19
        //    1.8446743e19 in SP: exp=158 (biased), mant=...
        //    2^127 * sqrt(2 - 2^-23) ≈ 2^127 * 1.4142... ≈ 2^127.5
        //    = sqrt(2) * 2^127
        //    Biased exp = 127 + 127/2 = 190... wait
        //    max_float = (2 - 2^-23) * 2^127
        //    sqrt(max_float) = sqrt(2 - 2^-23) * 2^63.5
        //    = sqrt(2 - 2^-23) * sqrt(2) * 2^63
        //    ≈ 1.4142... * 1.4142... * 2^63
        //    ≈ 2.0 * 2^63 = 2^64
        //    Actually: sqrt((2-2^-23)*2^127) = sqrt(2-2^-23) * 2^63.5
        //    = sqrt(2-2^-23) * sqrt(2) * 2^63
        //    sqrt(2-2^-23) ≈ 1.41421356... (very close to sqrt(2))
        //    So result ≈ sqrt(2)*sqrt(2)*2^63 = 2*2^63 = 2^64
        //    But slightly less: sqrt(2-2^-23)*sqrt(2) = sqrt(2*(2-2^-23))
        //    = sqrt(4 - 2^-22) ≈ 2 - 2^-23
        //    So result ≈ (2 - 2^-23) * 2^63 = 2^64 - 2^40
        //    In SP: exp=191 (biased), mant=0x7FFFFF (all ones)
        //    = 0xBF7FFFFF... no, positive: 0x7F7FFFFF
        //    Wait: 2^64 has biased exponent 64+127=191=0xBF
        //    (2-2^-23)*2^63 = 2^64 - 2^40
        //    In SP: sign=0, exp=191=0xBF, mant=0x7FFFFF
        //    = 0x5F7FFFFF (positive; 0xBF7FFFFF was negative — testbench bug)
        //    But this is inexact, so NX=1
        // ────────────────────────────────────────────
        run_op(MAX_FLOAT, RNE, 32'h5F7FFFFF, 5'b00001);

        // ────────────────────────────────────────────
        // Additional: sqrt(smallest normal 2^-126)
        //    sqrt(2^-126) = 2^-63
        //    2^-63 in SP: exp = 127-63 = 64 = 0x40, mant = 0
        //    = 0x20000000 (testbench had 0x38000000 which is 2^-15 — wrong)
        //    exact (NX=0)
        // ────────────────────────────────────────────
        run_op(SMALLEST_NORMAL, RNE, 32'h20000000, 5'b00000);

        // ────────────────────────────────────────────
        // Additional: sqrt(0.5) — sqrt(2^-1) = 2^-0.5 = 1/sqrt(2)
        //    = 0.7071067811865475...
        //    In SP: exp=126 (biased), mant = (0.7071...*2 - 1)*2^23
        //    = (1.41421356... - 1)*2^23 = 0.41421356...*8388608
        //    = 3474675.4... → 3474675 = 0x3504F3
        //    Result: 0x3F3504F3, inexact (NX=1)
        // ────────────────────────────────────────────
        run_op(HALF, RNE, 32'h3F3504F3, 5'b00001);

        // ────────────────────────────────────────────
        // Additional: sqrt(9.0) = 3.0
        //    9.0 = 0x41100000, 3.0 = 0x40400000
        // ────────────────────────────────────────────
        run_op(32'h41100000, RNE, 32'h40400000, 5'b00000);

        // ────────────────────────────────────────────
        // Additional: sqrt(0.75) — not exact, tests odd exponent path
        //    0.75 = 0x3F400000
        //    sqrt(0.75) = 0.8660254037844386...
        //    In SP: exp=126, mant = (0.8660...*2 - 1)*2^23
        //    = (1.73205080... - 1)*2^23 = 0.73205080...*8388608
        //    = 6143327.47... → 6143327 = 0x5DB3D7 (correctly rounded)
        //    Result: 0x3F5DB3D7, inexact (NX=1)
        //    (testbench had 0x3F5DB3CE — miscalculated mantissa)
        // ────────────────────────────────────────────
        run_op(32'h3F400000, RNE, 32'h3F5DB3D7, 5'b00001);

        // ────────────────────────────────────────────
        // Summary
        // ────────────────────────────────────────────
        $display("");
        $display("========================================");
        $display("  tb_fpu_sqrt summary: pass=%0d fail=%0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("");

        $finish;
    end

endmodule
