`timescale 1ns / 1ps

// ============================================================
// tb_fpu_multiplier.sv — Standalone unit testbench for fpu_multiplier
// ============================================================
//
// Tests: FMUL.S with comprehensive test vectors
// Subtests: 13
//
// ============================================================

module tb_fpu_multiplier;

    // ── IEEE 754 constants ──
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

    // ── DUT inputs ──
    reg  [31:0] src1;
    reg  [31:0] src2;
    reg  [2:0]  rm;
    reg         start;

    // ── DUT outputs ──
    wire [31:0] result;
    wire [4:0]  fflags;
    wire        done;

    // ── Scoreboard ──
    integer pass_count;
    integer fail_count;

    // ── Clock generation: 10 ns period ──
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ── DUT instantiation ──
    fpu_multiplier dut (
        .clk    (clk),
        .resetn (resetn),
        .src1   (src1),
        .src2   (src2),
        .rm     (rm),
        .start  (start),
        .result (result),
        .fflags (fflags),
        .done   (done)
    );

    // ── run_op task: drive inputs, wait for done, compare ──
    task run_op;
        input  [31:0] t_src1;
        input  [31:0] t_src2;
        input  [2:0]  t_rm;
        input  [31:0] t_exp_result;
        input  [4:0]  t_exp_fflags;
        begin
            // Drive inputs
            src1  = t_src1;
            src2  = t_src2;
            rm    = t_rm;

            // Assert start for 1 cycle
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            // Wait for done with timeout (100 cycles)
            begin : wait_done
                integer timeout;
                timeout = 0;
                while (done === 1'b0 && timeout < 100) begin
                    @(posedge clk);
                    timeout = timeout + 1;
                end
                if (timeout >= 100) begin
                    $display("[FAIL] Timeout waiting for done");
                    fail_count = fail_count + 1;
                    disable wait_done;
                end
            end

            // Compare result and fflags
            if (result === t_exp_result && fflags === t_exp_fflags) begin
                $display("[PASS] src1=%08h src2=%08h rm=%0d => result=%08h fflags=%05b",
                         t_src1, t_src2, t_rm, result, fflags);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] src1=%08h src2=%08h rm=%0d => result=%08h fflags=%05b (expected result=%08h fflags=%05b)",
                         t_src1, t_src2, t_rm, result, fflags, t_exp_result, t_exp_fflags);
                fail_count = fail_count + 1;
            end

            // Idle for 1 cycle between tests
            @(posedge clk);
        end
    endtask

    // ── Main stimulus ──
    initial begin
        pass_count = 0;
        fail_count = 0;
        src1       = 32'b0;
        src2       = 32'b0;
        rm         = RNE;
        start      = 1'b0;

        // Assert reset for 5 cycles
        resetn = 1'b0;
        repeat (5) @(posedge clk);
        resetn = 1'b1;
        @(posedge clk);

        // ============================================================
        // Test vectors
        // ============================================================

        // a. 1.0 * 2.0 = 2.0  (no flags)
        run_op(ONE, TWO, RNE, TWO, 5'b00000);

        // b. 1.5 * 2.0 = 3.0  (no flags)
        run_op(ONE_DOT_FIVE, TWO, RNE, THREE, 5'b00000);

        // c. -1.0 * 2.0 = -2.0  (no flags)
        run_op({1'b1, ONE[30:0]}, TWO, RNE, {1'b1, TWO[30:0]}, 5'b00000);

        // d. -1.0 * -2.0 = 2.0  (no flags)
        run_op({1'b1, ONE[30:0]}, {1'b1, TWO[30:0]}, RNE, TWO, 5'b00000);

        // e. 0 * anything = +0  (no flags)
        run_op(POS_ZERO, ONE, RNE, POS_ZERO, 5'b00000);

        // f. Inf * 0 = qNaN  (NV=1)
        run_op(POS_INF, POS_ZERO, RNE, QNAN, 5'b10000);

        // g. Inf * Inf = +Inf  (no flags)
        run_op(POS_INF, POS_INF, RNE, POS_INF, 5'b00000);

        // h. Inf * normal = +Inf  (no flags)
        run_op(POS_INF, TWO, RNE, POS_INF, 5'b00000);

        // i. qNaN * anything = qNaN  (no NV for qNaN input per IEEE 754)
        run_op(QNAN, TWO, RNE, QNAN, 5'b00000);

        // j. Overflow: max_float * 2.0 → +Inf  (OF=1, NX=1)
        run_op(MAX_FLOAT, TWO, RNE, POS_INF, 5'b00101);

        // k. Underflow (exact subnormal): smallest_normal * 0.5 = 2^-127
        //    2^-127 as subnormal: exp=0, frac=2^22 → 0x00400000, no flags
        run_op(SMALLEST_NORMAL, HALF, RNE, 32'h00400000, 5'b00000);

        // k2. Extreme underflow (inexact): smallest_normal^2 = 2^-252 → flushes to +0
        //     Correct flags: UF=1 + NX=1 (no OF). Was buggy: OF=1 from unsigned
        //     comparison of negative 10-bit exponent (BUG-93 follow-up).
        run_op(SMALLEST_NORMAL, SMALLEST_NORMAL, RNE, POS_ZERO, 5'b00011);

        // l. Rounding: (1+2^-23)^2 = 1+2^-22+2^-46, 2^-46 below precision
        //    RNE rounds to 1+2^-22 = 3F800002, NX=1
        run_op(32'h3F800001, 32'h3F800001, RNE, 32'h3F800002, 5'b00001);

        // m. Extreme underflow #2: smallest_normal × smallest_subnormal
        //    2^-126 × 2^-149 = 2^-275 → flushes to +0
        //    Expected: UF=1, NX=1, OF=0 (5'b00011)
        run_op(SMALLEST_NORMAL, 32'h00000001, RNE, POS_ZERO, 5'b00011);

        // ============================================================
        // Summary
        // ============================================================
        $display("");
        $display("========================================");
        $display("  tb_fpu_multiplier summary");
        $display("  pass=%0d fail=%0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  TEST FAILED");
        $display("========================================");

        $finish;
    end

endmodule
