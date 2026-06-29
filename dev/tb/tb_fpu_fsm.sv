`timescale 1ns / 1ps

// ===================================================================
// tb_fpu_fsm: FPU FSM boundary behavior testbench
//
// Tests 6 scenarios on the refactored fpu_unit FSM:
//   1. Reentrancy          — second req_valid rejected while busy
//   2. Timeout             — force div_done=0, verify fpu_error=1
//   3. Flush in F_DISPATCH — flush right after req_fire
//   4. Flush in F_WAIT     — flush during multi-cycle FDIV
//   5. Flush in F_COMPLETE — flush while result_valid held
//   6. Back-to-back        — FADD then FMUL with no gap
// ===================================================================

module tb_fpu_fsm;

    // ===================================================================
    // IEEE 754 single-precision constants
    // ===================================================================
    localparam [31:0] ONE          = 32'h3F800000;
    localparam [31:0] TWO          = 32'h40000000;
    localparam [31:0] THREE        = 32'h40400000;
    localparam [31:0] ONE_DOT_FIVE = 32'h3FC00000;

    // Rounding mode
    localparam [2:0] RNE = 3'b000;

    // fflags
    localparam [4:0] F_NONE = 5'b00000;

    // ===================================================================
    // FPU operation encoding (matches fpu_unit.sv)
    // ===================================================================
    localparam [6:0] FPU_FADD = 7'd0;
    localparam [6:0] FPU_FMUL = 7'd2;
    localparam [6:0] FPU_FDIV = 7'd3;

    // ===================================================================
    // FSM state constants (must match fpu_unit.sv)
    // ===================================================================
    localparam [2:0] F_IDLE     = 3'd0;
    localparam [2:0] F_DISPATCH = 3'd1;
    localparam [2:0] F_WAIT     = 3'd2;
    localparam [2:0] F_DONE     = 3'd3;
    localparam [2:0] F_COMPLETE = 3'd4;

    // ===================================================================
    // Clock and reset
    // ===================================================================
    reg        clk;
    reg        resetn;

    always #5 clk = ~clk;   // 10ns period

    // ===================================================================
    // DUT signals
    // ===================================================================
    reg  [6:0]  fpu_funct;
    reg  [2:0]  fpu_rm;
    reg  [63:0] src1;
    reg  [63:0] src2;
    reg  [63:0] src3;
    reg         req_valid;
    reg         flush;
    reg         result_got;
    wire [63:0] result;
    wire        fpu_busy;
    wire        fpu_ready;
    wire        result_valid;
    wire [4:0]  fflags;
    wire        rd_is_int;
    wire        fpu_error;

    // ===================================================================
    // DUT instantiation
    // ===================================================================
    fpu_unit dut (
        .clk         (clk),
        .resetn      (resetn),
        .fpu_funct   (fpu_funct),
        .fpu_rm      (fpu_rm),
        .src1        (src1),
        .src2        (src2),
        .src3        (src3),
        .req_valid   (req_valid),
        .flush       (flush),
        .result_got  (result_got),
        .result      (result),
        .fpu_busy    (fpu_busy),
        .fpu_ready   (fpu_ready),
        .result_valid(result_valid),
        .fflags      (fflags),
        .rd_is_int   (rd_is_int),
        .fpu_error   (fpu_error)
    );

    // ===================================================================
    // Scoreboard
    // ===================================================================
    integer pass_count;
    integer fail_count;
    integer test_num;

    // ===================================================================
    // Helper: clear all stimulus inputs
    // ===================================================================
    task clear_inputs;
    begin
        req_valid  = 1'b0;
        flush      = 1'b0;
        result_got = 1'b0;
        fpu_funct  = 7'b0;
        fpu_rm     = RNE;
        src1       = 64'b0;
        src2       = 64'b0;
        src3       = 64'b0;
    end
    endtask

    // ===================================================================
    // Helper: wait for fpu_ready with timeout
    // ===================================================================
    task wait_ready;
    begin
        integer timeout;
        timeout = 0;
        while (fpu_ready === 1'b0 && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
    end
    endtask

    // ===================================================================
    // Helper: issue a request (drive inputs + req_valid for 2 cycles)
    // ===================================================================
    task issue_req;
        input [6:0]  t_funct;
        input [31:0] t_src1;
        input [31:0] t_src2;
    begin
        fpu_funct = t_funct;
        fpu_rm    = RNE;
        src1      = {32'hFFFFFFFF, t_src1};
        src2      = {32'hFFFFFFFF, t_src2};
        src3      = 64'b0;
        req_valid = 1'b1;
        @(posedge clk);
        @(posedge clk);
        req_valid = 1'b0;
    end
    endtask

    // ===================================================================
    // Helper: acknowledge result (result_got for 2 cycles)
    // ===================================================================
    task ack_result;
    begin
        result_got = 1'b1;
        @(posedge clk);
        @(posedge clk);
        result_got = 1'b0;
    end
    endtask

    // ===================================================================
    // Helper: record pass/fail
    // ===================================================================
    task check;
        input cond;
        input [255:0] msg;
    begin
        if (cond) begin
            $display("[PASS] Test %0d: %0s", test_num, msg);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test %0d: %0s", test_num, msg);
            fail_count = fail_count + 1;
        end
        test_num = test_num + 1;
    end
    endtask

    // ===================================================================
    // Scenario 1: Reentrancy test
    //   Start FDIV, while busy assert req_valid with FADD.
    //   Verify fpu_ready=0 (rejected) and first FDIV completes correctly.
    // ===================================================================
    task test_reentrancy;
    begin
        integer timeout;
        $display("--- Scenario 1: Reentrancy ---");

        wait_ready;

        // Issue FDIV: 3.0 / 2.0 = 1.5
        issue_req(FPU_FDIV, THREE, TWO);

        // Wait until fpu_busy=1 (F_WAIT state)
        @(posedge clk);
        @(posedge clk);

        // Assert a second request while busy
        fpu_funct = FPU_FADD;
        src1      = {32'hFFFFFFFF, ONE};
        src2      = {32'hFFFFFFFF, TWO};
        req_valid = 1'b1;
        @(posedge clk);
        @(posedge clk);
        req_valid = 1'b0;

        // fpu_ready should be 0 (FPU rejected the second request)
        check(fpu_ready === 1'b0, "fpu_ready=0 during busy (reentrancy rejected)");

        // Wait for first FDIV to complete
        timeout = 0;
        while (result_valid === 1'b0 && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 500) begin
            check(1'b0, "FDIV completed (no timeout)");
        end else begin
            check(result === {32'hFFFFFFFF, ONE_DOT_FIVE} && fflags === F_NONE,
                  "FDIV result correct after reentrancy attempt");
        end

        ack_result;
        @(posedge clk);
    end
    endtask

    // ===================================================================
    // Scenario 2: Timeout test
    //   Start FDIV, force div_done=0 to simulate stuck sub-module.
    //   Wait >1000 cycles → fpu_error=1.
    //   Release force, acknowledge result, verify fpu_error clears.
    // ===================================================================
    task test_timeout;
    begin
        integer timeout;
        integer i;
        $display("--- Scenario 2: Timeout ---");

        wait_ready;

        // Issue FDIV
        issue_req(FPU_FDIV, THREE, TWO);

        // Wait until F_WAIT state
        @(posedge clk);
        @(posedge clk);

        // Force div_done=0 to prevent completion (hierarchical force)
        force dut.div_done = 1'b0;

        // Wait for timeout (1000 cycles + margin)
        // fpu_error should assert after 1000 cycles in F_WAIT
        timeout = 0;
        while (fpu_error === 1'b0 && timeout < 1200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (fpu_error === 1'b1) begin
            check(1'b1, "fpu_error=1 after timeout");
        end else begin
            check(1'b0, "fpu_error=1 after timeout (timed out waiting)");
        end

        // Release force so simulation can proceed
        release dut.div_done;

        // The FSM should have transitioned to F_DONE→F_COMPLETE
        // Wait for result_valid
        timeout = 0;
        while (result_valid === 1'b0 && timeout < 50) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        check(result_valid === 1'b1 && fpu_error === 1'b1,
              "result_valid=1 with fpu_error=1 (invalid result flagged)");

        // Acknowledge result — should clear fpu_error and return to idle
        ack_result;

        check(fpu_ready === 1'b1 && fpu_error === 1'b0,
              "fpu_ready=1, fpu_error=0 after result_got (error cleared)");

        @(posedge clk);
    end
    endtask

    // ===================================================================
    // Scenario 3: Flush in F_DISPATCH
    //   Issue request, then flush on the cycle where f_state=F_DISPATCH.
    //   Verify FPU returns to idle with no spurious result.
    // ===================================================================
    task test_flush_in_dispatch;
    begin
        integer timeout;
        $display("--- Scenario 3: Flush in F_DISPATCH ---");

        wait_ready;

        // Issue FADD (sequential op → goes through F_DISPATCH→F_WAIT)
        issue_req(FPU_FADD, ONE, TWO);

        // After 2 posedges of req_valid, DUT latched inputs and is in F_DISPATCH
        // (F_IDLE samples req_valid → F_DISPATCH on next edge)
        // Assert flush for 2 cycles
        flush = 1'b1;
        @(posedge clk);
        @(posedge clk);
        flush = 1'b0;

        // After flush: should be in F_IDLE, no result_valid
        repeat (3) @(posedge clk);

        check(fpu_ready === 1'b1, "fpu_ready=1 after flush in F_DISPATCH");
        check(result_valid === 1'b0, "result_valid=0 after flush in F_DISPATCH (no spurious result)");

        @(posedge clk);
    end
    endtask

    // ===================================================================
    // Scenario 4: Flush in F_WAIT
    //   Start FDIV (multi-cycle), wait until F_WAIT, then flush.
    //   Verify FPU returns to idle, result discarded.
    // ===================================================================
    task test_flush_in_wait;
    begin
        integer timeout;
        $display("--- Scenario 4: Flush in F_WAIT ---");

        wait_ready;

        // Issue FDIV (takes many cycles in F_WAIT)
        issue_req(FPU_FDIV, THREE, TWO);

        // Wait until fpu_busy=1 (F_WAIT)
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // Verify we're in F_WAIT (busy but no result yet)
        check(fpu_busy === 1'b1 && result_valid === 1'b0,
              "fpu_busy=1 in F_WAIT before flush");

        // Assert flush
        flush = 1'b1;
        @(posedge clk);
        @(posedge clk);
        flush = 1'b0;

        // After flush: should be in F_IDLE, no result
        repeat (3) @(posedge clk);

        check(fpu_ready === 1'b1, "fpu_ready=1 after flush in F_WAIT");
        check(result_valid === 1'b0, "result_valid=0 after flush in F_WAIT (result discarded)");

        @(posedge clk);
    end
    endtask

    // ===================================================================
    // Scenario 5: Flush in F_COMPLETE
    //   Start FADD, wait until result_valid=1 (F_COMPLETE), then flush.
    //   Verify FPU returns to idle, result_valid cleared.
    // ===================================================================
    task test_flush_in_complete;
    begin
        integer timeout;
        $display("--- Scenario 5: Flush in F_COMPLETE ---");

        wait_ready;

        // Issue FADD (short multi-cycle)
        issue_req(FPU_FADD, ONE, TWO);

        // Wait for result_valid (F_COMPLETE state)
        timeout = 0;
        while (result_valid === 1'b0 && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 500) begin
            check(1'b0, "FADD completed (reached F_COMPLETE)");
            @(posedge clk);
            return;
        end

        // Verify we're in F_COMPLETE: result_valid=1, fpu_busy=0
        check(result_valid === 1'b1 && fpu_busy === 1'b0,
              "result_valid=1, fpu_busy=0 in F_COMPLETE");

        // Assert flush while in F_COMPLETE
        flush = 1'b1;
        @(posedge clk);
        @(posedge clk);
        flush = 1'b0;

        // After flush: should be in F_IDLE, result_valid cleared
        repeat (3) @(posedge clk);

        check(fpu_ready === 1'b1, "fpu_ready=1 after flush in F_COMPLETE");
        check(result_valid === 1'b0, "result_valid=0 after flush in F_COMPLETE (result discarded)");

        @(posedge clk);
    end
    endtask

    // ===================================================================
    // Scenario 6: Back-to-back operations
    //   FADD then FMUL with no gap between result_got and next req_valid.
    //   Verify both produce correct results.
    // ===================================================================
    task test_back_to_back;
    begin
        integer timeout;
        $display("--- Scenario 6: Back-to-back ---");

        wait_ready;

        // Op A: FADD 1.0 + 2.0 = 3.0
        issue_req(FPU_FADD, ONE, TWO);

        // Wait for result_valid
        timeout = 0;
        while (result_valid === 1'b0 && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 500) begin
            check(1'b0, "B2B op A (FADD) completed");
            @(posedge clk);
            return;
        end

        check(result === {32'hFFFFFFFF, THREE}, "B2B op A: FADD 1.0+2.0=3.0");

        // Acknowledge and immediately issue next request (back-to-back)
        fpu_funct = FPU_FMUL;
        fpu_rm    = RNE;
        src1      = {32'hFFFFFFFF, ONE_DOT_FIVE};
        src2      = {32'hFFFFFFFF, TWO};
        src3      = 64'b0;
        result_got = 1'b1;
        req_valid  = 1'b1;
        @(posedge clk);
        @(posedge clk);
        result_got = 1'b0;
        req_valid  = 1'b0;

        // Wait for second result_valid
        timeout = 0;
        while (result_valid === 1'b0 && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 500) begin
            check(1'b0, "B2B op B (FMUL) completed");
            @(posedge clk);
            return;
        end

        // FMUL 1.5 * 2.0 = 3.0
        check(result === {32'hFFFFFFFF, THREE}, "B2B op B: FMUL 1.5*2.0=3.0");

        ack_result;
        @(posedge clk);
    end
    endtask

    // ===================================================================
    // Main test sequence
    // ===================================================================
    initial begin
        // Initialize
        clk        = 1'b0;
        resetn     = 1'b0;
        clear_inputs;
        pass_count = 0;
        fail_count = 0;
        test_num   = 1;

        // Assert reset for 5 cycles
        repeat (5) @(posedge clk);
        resetn = 1'b1;
        @(posedge clk);

        $display("========================================");
        $display("  tb_fpu_fsm: FPU FSM boundary tests");
        $display("========================================");

        // Run 6 scenarios
        test_reentrancy;
        test_timeout;
        test_flush_in_dispatch;
        test_flush_in_wait;
        test_flush_in_complete;
        test_back_to_back;

        // Summary
        $display("========================================");
        $display("  pass=%0d fail=%0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED: %0d/%0d scenarios failed", fail_count, pass_count + fail_count);

        $finish;
    end

endmodule
