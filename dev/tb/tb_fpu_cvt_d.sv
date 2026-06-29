`timescale 1ns / 1ps

module tb_fpu_cvt_d;

    // ===================================================================
    // IEEE 754 double-precision constants
    // ===================================================================
    localparam [63:0] QNAN_D         = 64'h7FF8000000000000;
    localparam [63:0] POS_INF_D      = 64'h7FF0000000000000;
    localparam [63:0] NEG_INF_D      = 64'hFFF0000000000000;
    localparam [63:0] ONE_D          = 64'h3FF0000000000000;
    localparam [63:0] NEG_ONE_D      = 64'hBFF0000000000000;
    localparam [63:0] THREE_D        = 64'h4008000000000000;
    localparam [63:0] ONE_HALF_D     = 64'h3FE0000000000000;
    localparam [63:0] ONE_FIVE_D     = 64'h3FF8000000000000;  // 1.5

    // Single-precision constants
    localparam [31:0] ONE_S          = 32'h3F800000;
    localparam [31:0] THREE_S        = 32'h40400000;

    // Conversion function codes
    localparam [2:0] FCVT_W_D   = 3'd0;   // double -> signed   int32
    localparam [2:0] FCVT_WU_D  = 3'd1;   // double -> unsigned int32
    localparam [2:0] FCVT_D_W   = 3'd2;   // signed   int32 -> double
    localparam [2:0] FCVT_D_WU  = 3'd3;   // unsigned int32 -> double
    localparam [2:0] FCVT_S_D   = 3'd4;   // double -> single
    localparam [2:0] FCVT_D_S   = 3'd5;   // single -> double

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
    localparam [4:0] F_NV_NX  = 5'b10001;

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
    reg  [2:0]  cvt_funct;
    reg  [2:0]  rm;
    reg         start;
    reg         flush;
    wire [63:0] result;
    wire [4:0]  fflags;
    wire        done;

    // ===================================================================
    // DUT instantiation
    // ===================================================================
    fpu_cvt_d dut (
        .clk       (clk),
        .resetn    (resetn),
        .src1      (src1),
        .cvt_funct (cvt_funct),
        .rm        (rm),
        .start     (start),
        .flush     (flush),
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
    // run_op task
    // ===================================================================
    task run_op;
        input  [63:0] t_src1;
        input  [2:0]  t_cvt_funct;
        input  [2:0]  t_rm;
        input  [63:0] t_expected_result;
        input  [4:0]  t_expected_fflags;
    begin
        integer timeout;
        src1      = t_src1;
        cvt_funct = t_cvt_funct;
        rm        = t_rm;

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
        clk       = 1'b0;
        resetn    = 1'b0;
        src1      = 64'b0;
        cvt_funct = 3'b0;
        rm        = RNE;
        start     = 1'b0;
        flush     = 1'b0;
        pass_count = 0;
        fail_count = 0;
        test_num   = 1;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        @(posedge clk);

        $display("========================================");
        $display("  tb_fpu_cvt_d: FCVT tests");
        $display("========================================");

        // --- FCVT.D.W: signed int32 -> double ---
        $display("--- FCVT.D.W ---");
        run_op({32'b0, 32'h00000001}, FCVT_D_W, RNE, ONE_D, F_NONE);
        run_op({32'b0, 32'hFFFFFFFF}, FCVT_D_W, RNE, NEG_ONE_D, F_NONE);
        run_op({32'b0, 32'h00000000}, FCVT_D_W, RNE, 64'h0000000000000000, F_NONE);

        // --- FCVT.D.WU: unsigned int32 -> double ---
        $display("--- FCVT.D.WU ---");
        run_op({32'b0, 32'h00000001}, FCVT_D_WU, RNE, ONE_D, F_NONE);
        run_op({32'b0, 32'hFFFFFFFF}, FCVT_D_WU, RNE, 64'h41EFFFFFFFE00000, F_NONE);

        // --- FCVT.W.D: double -> signed int32 ---
        $display("--- FCVT.W.D ---");
        run_op(ONE_D, FCVT_W_D, RNE, {32'b0, 32'h00000001}, F_NONE);
        run_op(NEG_ONE_D, FCVT_W_D, RNE, {32'b0, 32'hFFFFFFFF}, F_NONE);
        run_op(ONE_FIVE_D, FCVT_W_D, RNE, {32'b0, 32'h00000002}, F_NX);  // 1.5 RNE -> 2
        run_op(ONE_FIVE_D, FCVT_W_D, RTZ, {32'b0, 32'h00000001}, F_NX);  // 1.5 RTZ -> 1
        run_op(POS_INF_D, FCVT_W_D, RNE, {32'b0, 32'h7FFFFFFF}, F_NV_NX);
        run_op(QNAN_D, FCVT_W_D, RNE, {32'b0, 32'h7FFFFFFF}, F_NV_NX);

        // --- FCVT.WU.D: double -> unsigned int32 ---
        $display("--- FCVT.WU.D ---");
        run_op(ONE_D, FCVT_WU_D, RNE, {32'b0, 32'h00000001}, F_NONE);
        run_op(NEG_ONE_D, FCVT_WU_D, RNE, {32'b0, 32'h00000000}, F_NV_NX); // negative -> 0

        // --- FCVT.S.D: double -> single ---
        $display("--- FCVT.S.D ---");
        run_op(ONE_D, FCVT_S_D, RNE, {32'hFFFFFFFF, ONE_S}, F_NONE);
        run_op(THREE_D, FCVT_S_D, RNE, {32'hFFFFFFFF, THREE_S}, F_NONE);

        // --- FCVT.D.S: single -> double ---
        $display("--- FCVT.D.S ---");
        run_op({32'b0, ONE_S}, FCVT_D_S, RNE, ONE_D, F_NONE);
        run_op({32'b0, THREE_S}, FCVT_D_S, RNE, THREE_D, F_NONE);

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
