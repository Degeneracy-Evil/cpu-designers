`timescale 1ns / 1ps

module tb_fpu_divider;

    // ----------------------------------------------------------------
    // Clock and reset
    // ----------------------------------------------------------------
    reg        clk;
    reg        reset;

    // ----------------------------------------------------------------
    // DUT inputs
    // ----------------------------------------------------------------
    reg  [31:0] src1;
    reg  [31:0] src2;
    reg  [2:0]  rm;
    reg         start;

    // ----------------------------------------------------------------
    // DUT outputs
    // ----------------------------------------------------------------
    wire [31:0] result;
    wire [4:0]  fflags;
    wire        done;

    // ----------------------------------------------------------------
    // IEEE 754 single-precision constants
    // ----------------------------------------------------------------
    localparam [31:0] QNAN            = 32'h7FC00000;
    localparam [31:0] SNAN            = 32'h7F800001;
    localparam [31:0] POS_INF         = 32'h7F800000;
    localparam [31:0] NEG_INF         = 32'hFF800000;
    localparam [31:0] POS_ZERO        = 32'h00000000;
    localparam [31:0] NEG_ZERO        = 32'h80000000;
    localparam [31:0] ONE             = 32'h3F800000;
    localparam [31:0] TWO             = 32'h40000000;
    localparam [31:0] THREE           = 32'h40400000;
    localparam [31:0] HALF            = 32'h3F000000;
    localparam [31:0] ONE_DOT_FIVE    = 32'h3FC00000;
    localparam [31:0] MAX_FLOAT       = 32'h7F7FFFFF;
    localparam [31:0] SMALLEST_NORMAL = 32'h00800000;

    // ----------------------------------------------------------------
    // Rounding mode constants
    // ----------------------------------------------------------------
    localparam [2:0] RNE = 3'b000;
    localparam [2:0] RTZ = 3'b001;
    localparam [2:0] RDN = 3'b010;
    localparam [2:0] RUP = 3'b011;
    localparam [2:0] RMM = 3'b100;

    // ----------------------------------------------------------------
    // fflags bit layout: {NV, DZ, OF, UF, NX}
    // ----------------------------------------------------------------
    localparam [4:0] FF_NONE = 5'b00000;
    localparam [4:0] FF_NV   = 5'b10000;
    localparam [4:0] FF_DZ   = 5'b01000;
    localparam [4:0] FF_OF_NX = 5'b00101;  // OF + NX

    // ----------------------------------------------------------------
    // Test counters
    // ----------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer cycle_count;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    fpu_divider dut (
        .clk    (clk),
        .reset  (reset),
        .src1   (src1),
        .src2   (src2),
        .rm     (rm),
        .start  (start),
        .result (result),
        .fflags (fflags),
        .done   (done)
    );

    // ----------------------------------------------------------------
    // Clock generation: 10 ns period (5 ns half-period)
    // ----------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ----------------------------------------------------------------
    // run_op task: drive one division, wait for done, compare
    // ----------------------------------------------------------------
    task run_op;
        input [31:0] t_src1;
        input [31:0] t_src2;
        input [2:0]  t_rm;
        input [31:0] t_exp_result;
        input [4:0]  t_exp_fflags;
        begin
            // Drive inputs
            src1 = t_src1;
            src2 = t_src2;
            rm   = t_rm;

            // Assert start for 1 cycle
            start = 1;
            @(posedge clk);
            #1;   // small delta after edge so DUT captures start
            start = 0;

            // Wait for done with timeout (divider is iterative, ~28 cycles)
            cycle_count = 0;
            while (!done && cycle_count < 500) begin
                @(posedge clk);
                #1;
                cycle_count = cycle_count + 1;
            end

            if (cycle_count >= 500) begin
                $display("FAIL: timeout waiting for done (src1=%08h src2=%08h rm=%0d)",
                         t_src1, t_src2, t_rm);
                fail_count = fail_count + 1;
            end else if (result === t_exp_result && fflags === t_exp_fflags) begin
                $display("PASS: %08h / %08h (rm=%0d) => result=%08h fflags=%05b  [%0d cycles]",
                         t_src1, t_src2, t_rm, result, fflags, cycle_count);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %08h / %08h (rm=%0d) => got result=%08h fflags=%05b, expected result=%08h fflags=%05b",
                         t_src1, t_src2, t_rm, result, fflags, t_exp_result, t_exp_fflags);
                fail_count = fail_count + 1;
            end

            // Wait one cycle for DUT to return to IDLE
            @(posedge clk);
            #1;
        end
    endtask

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    initial begin
        // Initialize
        pass_count = 0;
        fail_count = 0;
        src1  = 32'b0;
        src2  = 32'b0;
        rm    = RNE;
        start = 0;

        // Assert reset for 5 cycles
        reset = 1;
        repeat (5) @(posedge clk);
        reset = 0;
        @(posedge clk);
        #1;

        // ============================================================
        // Test vectors
        // ============================================================

        // a. 2.0 / 2.0 = 1.0
        run_op(TWO, TWO, RNE, ONE, FF_NONE);

        // b. 3.0 / 2.0 = 1.5
        run_op(THREE, TWO, RNE, ONE_DOT_FIVE, FF_NONE);

        // c. -2.0 / 2.0 = -1.0
        run_op(32'hC0000000, TWO, RNE, 32'hBF800000, FF_NONE);

        // d. -2.0 / -2.0 = 1.0
        run_op(32'hC0000000, 32'hC0000000, RNE, ONE, FF_NONE);

        // e. 1.0 / 0 = Inf (DZ=1)
        run_op(ONE, POS_ZERO, RNE, POS_INF, FF_DZ);

        // f. 0 / 0 = qNaN (NV=1)
        run_op(POS_ZERO, POS_ZERO, RNE, QNAN, FF_NV);

        // g. Inf / Inf = qNaN (NV=1)
        run_op(POS_INF, POS_INF, RNE, QNAN, FF_NV);

        // h. Inf / 2.0 = Inf
        run_op(POS_INF, TWO, RNE, POS_INF, FF_NONE);

        // i. sNaN / anything = qNaN (NV=1)
        run_op(SNAN, TWO, RNE, QNAN, FF_NV);

        // j. 1.0 / Inf = +0
        run_op(ONE, POS_INF, RNE, POS_ZERO, FF_NONE);

        // k. Overflow: max_float / 0.5 -> Inf (OF=1, NX=1)
        run_op(MAX_FLOAT, HALF, RNE, POS_INF, FF_OF_NX);

        // l. Underflow: smallest_normal / 2.0 -> subnormal 2^(-127)
        //    IEEE 754: UF is raised only when result is tiny AND inexact.
        //    This division is exact, so UF=0, NX=0.
        run_op(SMALLEST_NORMAL, TWO, RNE, 32'h00400000, FF_NONE);

        // ============================================================
        // Final summary
        // ============================================================
        $display("");
        $display("========================================");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");

        $finish;
    end

endmodule
