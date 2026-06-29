`timescale 1ns / 1ps

module tb_fpu_divider_d;

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
    localparam [63:0] NEG_SIX        = 64'hC018000000000000;
    localparam [63:0] NEG_THREE      = 64'hC008000000000000;
    localparam [63:0] SEVEN          = 64'h401C000000000000;
    localparam [63:0] THREE_HALF     = 64'h400C000000000000; // 3.5

    // 1/3 in double = 0x3FD5555555555555
    localparam [63:0] ONE_THIRD      = 64'h3FD5555555555555;

    // Rounding mode constants
    localparam [2:0] RNE = 3'b000;
    localparam [2:0] RTZ = 3'b001;
    localparam [2:0] RDN = 3'b010;
    localparam [2:0] RUP = 3'b011;
    localparam [2:0] RMM = 3'b100;

    // fflags: {NV, DZ, OF, UF, NX}
    localparam [4:0] F_NONE   = 5'b00000;
    localparam [4:0] F_NV     = 5'b10000;
    localparam [4:0] F_DZ     = 5'b01000;
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
    fpu_divider_d dut (
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
    // run_op task (longer timeout for iterative divider: ~60 cycles)
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
        $display("  tb_fpu_divider_d: FDIV.D tests");
        $display("========================================");

        // --- Normal divide: 6.0 / 2.0 = 3.0 ---
        $display("--- Normal divide ---");
        run_op(SIX, TWO, RNE, THREE, F_NONE);

        // --- 1.0 / 2.0 = 0.5 ---
        run_op(ONE, TWO, RNE, HALF, F_NONE);

        // --- (-6.0) / 2.0 = -3.0 ---
        run_op(NEG_SIX, TWO, RNE, NEG_THREE, F_NONE);

        // --- 7.0 / 2.0 = 3.5 ---
        run_op(SEVEN, TWO, RNE, THREE_HALF, F_NONE);

        // --- Divide by zero: 1.0 / 0 = +Inf (DZ) ---
        $display("--- Divide by zero (DZ) ---");
        run_op(ONE, POS_ZERO, RNE, POS_INF, F_DZ);
        run_op(NEG_SIX, POS_ZERO, RNE, NEG_INF, F_DZ);

        // --- 0 / 0 = qNaN (NV) ---
        $display("--- 0 / 0 (NV) ---");
        run_op(POS_ZERO, POS_ZERO, RNE, QNAN, F_NV);

        // --- Inf / Inf = qNaN (NV) ---
        $display("--- Inf / Inf (NV) ---");
        run_op(POS_INF, POS_INF, RNE, QNAN, F_NV);

        // --- Inf / 2.0 = Inf ---
        $display("--- Inf / normal ---");
        run_op(POS_INF, TWO, RNE, POS_INF, F_NONE);

        // --- 2.0 / Inf = 0 ---
        $display("--- normal / Inf ---");
        run_op(TWO, POS_INF, RNE, POS_ZERO, F_NONE);

        // --- 0 / 2.0 = 0 ---
        $display("--- 0 / normal ---");
        run_op(POS_ZERO, TWO, RNE, POS_ZERO, F_NONE);

        // --- NaN propagation ---
        $display("--- NaN propagation ---");
        run_op(QNAN, ONE, RNE, QNAN, F_NONE);
        run_op(SNAN, ONE, RNE, QNAN, F_NV);
        run_op(ONE, QNAN, RNE, QNAN, F_NONE);

        // --- Inexact: 1.0 / 3.0 = 0.3333... (NX) ---
        $display("--- Inexact: 1.0 / 3.0 ---");
        run_op(ONE, THREE, RNE, ONE_THIRD, F_NX);

        // --- 1.0 / 1.0 = 1.0 ---
        run_op(ONE, ONE, RNE, ONE, F_NONE);

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
