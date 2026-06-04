`timescale 1ns / 1ps

module tb_fpu_cvt;

    // ===================================================================
    // IEEE 754 single-precision constants
    // ===================================================================
    localparam [31:0] QNAN     = 32'h7FC00000;
    localparam [31:0] POS_INF  = 32'h7F800000;
    localparam [31:0] NEG_INF  = 32'hFF800000;
    localparam [31:0] POS_ZERO = 32'h00000000;
    localparam [31:0] NEG_ZERO = 32'h80000000;
    localparam [31:0] ONE      = 32'h3F800000;
    localparam [31:0] NEG_ONE  = 32'hBF800000;
    localparam [31:0] TWO      = 32'h40000000;
    localparam [31:0] HALF     = 32'h3F000000;

    // Integer boundary constants
    localparam [31:0] INT_MAX  = 32'h7FFFFFFF;
    localparam [31:0] INT_MIN  = 32'h80000000;
    localparam [31:0] UINT_MAX = 32'hFFFFFFFF;

    // Additional float constants for test vectors
    localparam [31:0] ONE_DOT_FIVE = 32'h3FC00000;  // 1.5
    localparam [31:0] TWO_POW_31   = 32'h4F000000;  // 2^31 as float
    localparam [31:0] NEG_TWO_POW_31 = 32'hCF000000; // -2^31 as float
    localparam [31:0] TWO_POW_32   = 32'h4F800000;  // 2^32 as float (4294967296.0)

    // Rounding mode constants
    localparam [2:0] RNE = 3'b000;
    localparam [2:0] RTZ = 3'b001;
    localparam [2:0] RDN = 3'b010;
    localparam [2:0] RUP = 3'b011;
    localparam [2:0] RMM = 3'b100;

    // fflags: {NV, DZ, OF, UF, NX}
    localparam [4:0] F_NONE = 5'b00000;
    localparam [4:0] F_NV   = 5'b10000;
    localparam [4:0] F_NX   = 5'b00001;
    localparam [4:0] F_NV_NX = 5'b10001;

    // Conversion function codes
    localparam [2:0] FCVT_W_S  = 3'd0;   // float -> signed int32
    localparam [2:0] FCVT_WU_S = 3'd1;   // float -> unsigned int32
    localparam [2:0] FCVT_S_W  = 3'd2;   // signed int32 -> float
    localparam [2:0] FCVT_S_WU = 3'd3;   // unsigned int32 -> float

    // ===================================================================
    // Clock and reset
    // ===================================================================
    reg        clk;
    reg        reset;

    always #5 clk = ~clk;   // 10ns period, 5ns half-period

    // ===================================================================
    // DUT signals
    // ===================================================================
    reg  [31:0] src1;
    reg  [2:0]  cvt_funct;
    reg  [2:0]  rm;
    reg         start;
    wire [31:0] result;
    wire [4:0]  fflags;
    wire        done;

    // ===================================================================
    // DUT instantiation
    // ===================================================================
    fpu_cvt dut (
        .clk       (clk),
        .reset     (reset),
        .src1      (src1),
        .cvt_funct (cvt_funct),
        .rm        (rm),
        .start     (start),
        .result    (result),
        .fflags    (fflags),
        .done      (done)
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
        input  [2:0]  t_cvt_funct;
        input  [2:0]  t_rm;
        input  [31:0] t_expected_result;
        input  [4:0]  t_expected_fflags;
    begin
        integer timeout;
        // Drive inputs
        src1       = t_src1;
        cvt_funct  = t_cvt_funct;
        rm         = t_rm;

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
        clk       = 1'b0;
        reset     = 1'b1;
        src1      = 32'b0;
        cvt_funct = 3'b0;
        rm        = RNE;
        start     = 1'b0;
        pass_count = 0;
        fail_count = 0;
        test_num   = 1;

        // Assert reset for 5 cycles
        repeat (5) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        $display("========================================");
        $display("  tb_fpu_cvt: FCVT conversion tests");
        $display("========================================");

        // ===============================================================
        // FCVT.W.S  (float -> signed int32)
        // ===============================================================
        $display("--- FCVT.W.S: float -> signed int ---");

        // a. 1.0 -> 1
        run_op(ONE, FCVT_W_S, RNE, 32'h00000001, F_NONE);

        // b. 1.5 -> 2 (RNE rounds 1.5 to nearest even = 2, NX=1)
        run_op(ONE_DOT_FIVE, FCVT_W_S, RNE, 32'h00000002, F_NX);

        // c. -1.0 -> -1
        run_op(NEG_ONE, FCVT_W_S, RNE, 32'hFFFFFFFF, F_NONE);

        // d. 2^31 (overflow) -> INT_MAX (NV=1, NX=1)
        run_op(TWO_POW_31, FCVT_W_S, RNE, INT_MAX, F_NV_NX);

        // e. -2^31 -> -2^31 (exact, no NV)
        run_op(NEG_TWO_POW_31, FCVT_W_S, RNE, INT_MIN, F_NONE);

        // f. NaN -> INT_MAX (NV=1, NX=1)
        run_op(QNAN, FCVT_W_S, RNE, INT_MAX, F_NV_NX);

        // g. +Inf -> INT_MAX (NV=1, NX=1)
        run_op(POS_INF, FCVT_W_S, RNE, INT_MAX, F_NV_NX);

        // h. 0.0 -> 0
        run_op(POS_ZERO, FCVT_W_S, RNE, 32'h00000000, F_NONE);

        // ===============================================================
        // FCVT.WU.S  (float -> unsigned int32)
        // ===============================================================
        $display("--- FCVT.WU.S: float -> unsigned int ---");

        // a. 1.0 -> 1
        run_op(ONE, FCVT_WU_S, RNE, 32'h00000001, F_NONE);

        // b. -1.0 -> 0 (NV=1, negative to unsigned)
        run_op(NEG_ONE, FCVT_WU_S, RNE, 32'h00000000, F_NV_NX);

        // c. 2^31 -> 0x80000000
        run_op(TWO_POW_31, FCVT_WU_S, RNE, 32'h80000000, F_NONE);

        // d. NaN -> UINT_MAX (NV=1, NX=1)
        run_op(QNAN, FCVT_WU_S, RNE, UINT_MAX, F_NV_NX);

        // ===============================================================
        // FCVT.S.W  (signed int32 -> float)
        // ===============================================================
        $display("--- FCVT.S.W: signed int -> float ---");

        // a. 1 -> 1.0
        run_op(32'h00000001, FCVT_S_W, RNE, ONE, F_NONE);

        // b. -1 -> -1.0
        run_op(32'hFFFFFFFF, FCVT_S_W, RNE, NEG_ONE, F_NONE);

        // c. 0 -> +0.0
        run_op(32'h00000000, FCVT_S_W, RNE, POS_ZERO, F_NONE);

        // d. 0x7FFFFFFF -> 2^31 (NX=1, inexact)
        run_op(INT_MAX, FCVT_S_W, RNE, TWO_POW_31, F_NX);

        // e. 0x80000000 -> -2^31
        run_op(INT_MIN, FCVT_S_W, RNE, NEG_TWO_POW_31, F_NONE);

        // ===============================================================
        // FCVT.S.WU  (unsigned int32 -> float)
        // ===============================================================
        $display("--- FCVT.S.WU: unsigned int -> float ---");

        // a. 1 -> 1.0
        run_op(32'h00000001, FCVT_S_WU, RNE, ONE, F_NONE);

        // b. 0xFFFFFFFF -> 4294967296.0 (NX=1)
        run_op(UINT_MAX, FCVT_S_WU, RNE, TWO_POW_32, F_NX);

        // c. 0x80000000 -> 2^31
        run_op(32'h80000000, FCVT_S_WU, RNE, TWO_POW_31, F_NONE);

        // ===============================================================
        // Summary
        // ===============================================================
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
