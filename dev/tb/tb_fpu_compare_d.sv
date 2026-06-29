`timescale 1ns / 1ps

module tb_fpu_compare_d;

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
    localparam [63:0] NEG_ONE        = 64'hBFF0000000000000;
    localparam [63:0] MAX_SUBNORMAL  = 64'h000FFFFFFFFFFFFF;
    localparam [63:0] NEG_SUBNORMAL  = 64'h800FFFFFFFFFFFFF;

    // Compare function codes
    localparam [2:0] FLT = 3'b000;
    localparam [2:0] FLE = 3'b001;
    localparam [2:0] FEQ = 3'b010;

    // Sign inject function codes
    localparam [2:0] FSGNJ  = 3'b000;
    localparam [2:0] FSGNJN = 3'b001;
    localparam [2:0] FSGNJX = 3'b010;

    // fflags: {NV, DZ, OF, UF, NX}
    localparam [4:0] F_NONE = 5'b00000;
    localparam [4:0] F_NV   = 5'b10000;

    // FCLASS bit positions
    localparam [63:0] CLASS_NEG_INF    = 64'h001;
    localparam [63:0] CLASS_NEG_NORMAL = 64'h002;
    localparam [63:0] CLASS_NEG_SUB    = 64'h004;
    localparam [63:0] CLASS_NEG_ZERO   = 64'h008;
    localparam [63:0] CLASS_POS_ZERO   = 64'h010;
    localparam [63:0] CLASS_POS_SUB    = 64'h020;
    localparam [63:0] CLASS_POS_NORMAL = 64'h040;
    localparam [63:0] CLASS_POS_INF    = 64'h080;
    localparam [63:0] CLASS_SNAN       = 64'h100;
    localparam [63:0] CLASS_QNAN       = 64'h200;

    // ===================================================================
    // DUT signals — compare
    // ===================================================================
    reg  [63:0] cmp_src1, cmp_src2;
    reg  [2:0]  cmp_funct;
    wire [63:0] cmp_result;
    wire [4:0]  cmp_fflags;

    fpu_compare_d u_compare (
        .src1      (cmp_src1),
        .src2      (cmp_src2),
        .cmp_funct (cmp_funct),
        .result    (cmp_result),
        .fflags    (cmp_fflags)
    );

    // ===================================================================
    // DUT signals — minmax
    // ===================================================================
    reg  [63:0] mm_src1, mm_src2;
    reg         mm_is_max;
    wire [63:0] mm_result;
    wire [4:0]  mm_fflags;

    fpu_minmax_d u_minmax (
        .src1   (mm_src1),
        .src2   (mm_src2),
        .is_max (mm_is_max),
        .result (mm_result),
        .fflags (mm_fflags)
    );

    // ===================================================================
    // DUT signals — classify
    // ===================================================================
    reg  [63:0] cls_src1;
    wire [63:0] cls_result;
    wire [4:0]  cls_fflags;

    fpu_classify_d u_classify (
        .src1   (cls_src1),
        .result (cls_result),
        .fflags (cls_fflags)
    );

    // ===================================================================
    // DUT signals — sign inject
    // ===================================================================
    reg  [63:0] sgnj_src1, sgnj_src2;
    reg  [2:0]  sgnj_funct;
    wire [63:0] sgnj_result;
    wire [4:0]  sgnj_fflags;

    fpu_sign_inject_d u_sign_inject (
        .src1       (sgnj_src1),
        .src2       (sgnj_src2),
        .sgnj_funct (sgnj_funct),
        .result     (sgnj_result),
        .fflags     (sgnj_fflags)
    );

    // ===================================================================
    // Scoreboard
    // ===================================================================
    integer pass_count;
    integer fail_count;
    integer test_num;

    // ===================================================================
    // Tasks for combinational modules
    // ===================================================================
    task check_compare;
        input  [63:0] t_src1;
        input  [63:0] t_src2;
        input  [2:0]  t_funct;
        input  [63:0] t_exp_result;
        input  [4:0]  t_exp_fflags;
    begin
        cmp_src1  = t_src1;
        cmp_src2  = t_src2;
        cmp_funct = t_funct;
        #1;
        if (cmp_result !== t_exp_result || cmp_fflags !== t_exp_fflags) begin
            $display("[FAIL] Test %0d: cmp result=%016X (exp=%016X) fflags=%05b (exp=%05b)",
                     test_num, cmp_result, t_exp_result, cmp_fflags, t_exp_fflags);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] Test %0d: cmp result=%016X fflags=%05b", test_num, cmp_result, cmp_fflags);
            pass_count = pass_count + 1;
        end
        test_num = test_num + 1;
    end
    endtask

    task check_minmax;
        input  [63:0] t_src1;
        input  [63:0] t_src2;
        input         t_is_max;
        input  [63:0] t_exp_result;
        input  [4:0]  t_exp_fflags;
    begin
        mm_src1   = t_src1;
        mm_src2   = t_src2;
        mm_is_max = t_is_max;
        #1;
        if (mm_result !== t_exp_result || mm_fflags !== t_exp_fflags) begin
            $display("[FAIL] Test %0d: minmax result=%016X (exp=%016X) fflags=%05b (exp=%05b)",
                     test_num, mm_result, t_exp_result, mm_fflags, t_exp_fflags);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] Test %0d: minmax result=%016X fflags=%05b", test_num, mm_result, mm_fflags);
            pass_count = pass_count + 1;
        end
        test_num = test_num + 1;
    end
    endtask

    task check_classify;
        input  [63:0] t_src1;
        input  [63:0] t_exp_result;
    begin
        cls_src1 = t_src1;
        #1;
        if (cls_result !== t_exp_result || cls_fflags !== 5'b0) begin
            $display("[FAIL] Test %0d: fclass result=%016X (exp=%016X) fflags=%05b",
                     test_num, cls_result, t_exp_result, cls_fflags);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] Test %0d: fclass result=%016X", test_num, cls_result);
            pass_count = pass_count + 1;
        end
        test_num = test_num + 1;
    end
    endtask

    task check_sgnj;
        input  [63:0] t_src1;
        input  [63:0] t_src2;
        input  [2:0]  t_funct;
        input  [63:0] t_exp_result;
    begin
        sgnj_src1  = t_src1;
        sgnj_src2  = t_src2;
        sgnj_funct = t_funct;
        #1;
        if (sgnj_result !== t_exp_result || sgnj_fflags !== 5'b0) begin
            $display("[FAIL] Test %0d: sgnj result=%016X (exp=%016X) fflags=%05b",
                     test_num, sgnj_result, t_exp_result, sgnj_fflags);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] Test %0d: sgnj result=%016X", test_num, sgnj_result);
            pass_count = pass_count + 1;
        end
        test_num = test_num + 1;
    end
    endtask

    // ===================================================================
    // Main test sequence
    // ===================================================================
    initial begin
        pass_count = 0;
        fail_count = 0;
        test_num   = 1;

        // Initialize all inputs
        cmp_src1 = 0; cmp_src2 = 0; cmp_funct = 0;
        mm_src1 = 0; mm_src2 = 0; mm_is_max = 0;
        cls_src1 = 0;
        sgnj_src1 = 0; sgnj_src2 = 0; sgnj_funct = 0;
        #1;

        $display("========================================");
        $display("  tb_fpu_compare_d: FEQ/FLT/FLE/FMIN/FMAX/FCLASS/FSGNJ tests");
        $display("========================================");

        // ===============================================================
        // FEQ.D tests
        // ===============================================================
        $display("--- FEQ.D ---");
        check_compare(ONE, ONE, FEQ, 64'h1, F_NONE);
        check_compare(ONE, TWO, FEQ, 64'h0, F_NONE);
        check_compare(POS_ZERO, NEG_ZERO, FEQ, 64'h1, F_NONE);  // +0 == -0
        check_compare(ONE, QNAN, FEQ, 64'h0, F_NONE);           // qNaN: no NV for FEQ
        check_compare(ONE, SNAN, FEQ, 64'h0, F_NV);             // sNaN: NV for FEQ

        // ===============================================================
        // FLT.D tests
        // ===============================================================
        $display("--- FLT.D ---");
        check_compare(ONE, TWO, FLT, 64'h1, F_NONE);
        check_compare(TWO, ONE, FLT, 64'h0, F_NONE);
        check_compare(NEG_ONE, ONE, FLT, 64'h1, F_NONE);
        check_compare(POS_ZERO, NEG_ZERO, FLT, 64'h0, F_NONE);  // not less, equal
        check_compare(ONE, QNAN, FLT, 64'h0, F_NV);             // any NaN: NV for FLT

        // ===============================================================
        // FLE.D tests
        // ===============================================================
        $display("--- FLE.D ---");
        check_compare(ONE, ONE, FLE, 64'h1, F_NONE);
        check_compare(TWO, ONE, FLE, 64'h0, F_NONE);
        check_compare(POS_ZERO, NEG_ZERO, FLE, 64'h1, F_NONE);  // equal => <=
        check_compare(ONE, QNAN, FLE, 64'h0, F_NV);             // any NaN: NV for FLE

        // ===============================================================
        // FMIN.D / FMAX.D tests
        // ===============================================================
        $display("--- FMIN.D / FMAX.D ---");
        check_minmax(ONE, TWO, 1'b0, ONE, F_NONE);              // FMIN(1,2)=1
        check_minmax(ONE, TWO, 1'b1, TWO, F_NONE);              // FMAX(1,2)=2
        check_minmax(NEG_ZERO, POS_ZERO, 1'b0, NEG_ZERO, F_NONE); // FMIN(-0,+0)=-0
        check_minmax(NEG_ZERO, POS_ZERO, 1'b1, POS_ZERO, F_NONE); // FMAX(-0,+0)=+0
        check_minmax(NEG_ONE, ONE, 1'b0, NEG_ONE, F_NONE);      // FMIN(-1,1)=-1
        check_minmax(NEG_ONE, ONE, 1'b1, ONE, F_NONE);          // FMAX(-1,1)=1
        check_minmax(ONE, QNAN, 1'b0, ONE, F_NV);               // FMIN(1,qNaN)=1, NV
        check_minmax(ONE, QNAN, 1'b1, ONE, F_NV);               // FMAX(1,qNaN)=1, NV
        check_minmax(QNAN, QNAN, 1'b0, QNAN, F_NV);             // FMIN(qNaN,qNaN)=qNaN, NV

        // ===============================================================
        // FCLASS.D tests
        // ===============================================================
        $display("--- FCLASS.D ---");
        check_classify(NEG_INF, CLASS_NEG_INF);
        check_classify(NEG_ONE, CLASS_NEG_NORMAL);
        check_classify(NEG_SUBNORMAL, CLASS_NEG_SUB);
        check_classify(NEG_ZERO, CLASS_NEG_ZERO);
        check_classify(POS_ZERO, CLASS_POS_ZERO);
        check_classify(MAX_SUBNORMAL, CLASS_POS_SUB);
        check_classify(ONE, CLASS_POS_NORMAL);
        check_classify(POS_INF, CLASS_POS_INF);
        check_classify(SNAN, CLASS_SNAN);
        check_classify(QNAN, CLASS_QNAN);

        // ===============================================================
        // FSGNJ.D / FSGNJN.D / FSGNJX.D tests
        // ===============================================================
        $display("--- FSGNJ.D / FSGNJN.D / FSGNJX.D ---");
        // FSGNJ: copy sign from src2
        check_sgnj(ONE, NEG_ONE, FSGNJ, NEG_ONE);       // {sign(-1), body(1)} = -1
        check_sgnj(NEG_ONE, ONE, FSGNJ, ONE);            // {sign(1), body(-1)} = 1
        // FSGNJN: invert sign from src2
        check_sgnj(ONE, NEG_ONE, FSGNJN, ONE);           // {~sign(-1), body(1)} = 1
        check_sgnj(ONE, ONE, FSGNJN, NEG_ONE);           // {~sign(1), body(1)} = -1
        // FSGNJX: XOR signs
        check_sgnj(ONE, ONE, FSGNJX, ONE);               // 0^0=0 => +1
        check_sgnj(ONE, NEG_ONE, FSGNJX, NEG_ONE);       // 0^1=1 => -1
        check_sgnj(NEG_ONE, NEG_ONE, FSGNJX, ONE);       // 1^1=0 => +1

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
