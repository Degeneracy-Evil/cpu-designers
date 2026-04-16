`timescale 1ns / 1ps

// Phase-1 CPU integration testbench.
// Verifies basic RV32I execution path for ADDI/ADD/LUI using
// the phase1 program image in phase1_prog.hex.
module tb_phase1_cpu;

    // Clock and reset.
    reg clk;
    reg reset;

    // Debug outputs from DUT.
    wire [31:0] debug_pc;
    wire [31:0] debug_instr;
    wire [4:0]  debug_state;
    wire        debug_illegal;
    wire [31:0] debug_mem_addr;
    wire [31:0] debug_mem_wdata;
    wire [31:0] debug_mem_rdata;
    wire [3:0]  debug_mem_wstrb;
    wire [31:0] debug_display_mem_data;

    // Test statistics.
    integer pass_count;
    integer fail_count;
    integer cycle_count;

    // Relevant FSM states for synchronization checks.
    localparam FETCH = 5'd0;
    localparam DECODE = 5'd1;
    localparam EXECUTE_REQ = 5'd2;
    localparam EXECUTE_WAIT = 5'd3;
    localparam WRITE_BACK = 5'd11;
    localparam INTERRUPT_CHECK = 5'd12;

    // Device under test.
    cpu_top #(
        .IMEM_DEPTH(8),
        .IMEM_INIT_FILE("../dev/2-embedded_cpu/tb/phase1_prog.hex")
    ) dut (
        .clk(clk),
        .reset(reset),
        .debug_pc(debug_pc),
        .debug_instr(debug_instr),
        .debug_state(debug_state),
        .debug_illegal(debug_illegal),
        .debug_mem_addr(debug_mem_addr),
        .debug_mem_wdata(debug_mem_wdata),
        .debug_mem_rdata(debug_mem_rdata),
        .debug_mem_wstrb(debug_mem_wstrb),
        .debug_display_mem_data(debug_display_mem_data)
    );

    // 100 MHz simulation clock.
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Common expectation helper.
    task expect_true;
        input cond;
        input [1023:0] name;
        begin
            if (cond) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s", name);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s", name);
            end
        end
    endtask

    // Wait until FSM reaches WRITE_BACK or timeout.
    task wait_for_writeback;
        input integer timeout_cycles;
        output integer hit;
        integer i;
        begin
            hit = 1'b0;
            for (i = 0; i < timeout_cycles; i = i + 1) begin
                @(posedge clk);
                if (debug_state == WRITE_BACK) begin
                    hit = 1'b1;
                    i = timeout_cycles;
                end
            end
        end
    endtask

    // Wait until FSM returns to FETCH or timeout.
    task wait_for_fetch;
        input integer timeout_cycles;
        output integer hit;
        integer i;
        begin
            hit = 1'b0;
            for (i = 0; i < timeout_cycles; i = i + 1) begin
                @(posedge clk);
                if (debug_state == FETCH) begin
                    hit = 1'b1;
                    i = timeout_cycles;
                end
            end
        end
    endtask

    // Wait until FSM reaches INTERRUPT_CHECK or timeout.
    task wait_for_interrupt_check;
        input integer timeout_cycles;
        output integer hit;
        integer i;
        begin
            hit = 1'b0;
            for (i = 0; i < timeout_cycles; i = i + 1) begin
                @(posedge clk);
                if (debug_state == INTERRUPT_CHECK) begin
                    hit = 1'b1;
                    i = timeout_cycles;
                end
            end
        end
    endtask

    integer hit;
    initial begin
        // Initialize counters.
        pass_count = 0;
        fail_count = 0;
        cycle_count = 0;

        // Reset sequence.
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;

        $display("========================================");
        $display("Phase-1 CPU Test");
        $display("========================================");

        // Instruction 1: addi x1, x0, 5
        wait_for_writeback(80, hit);
        expect_true(hit == 1, "Instruction 1 reaches WRITE_BACK");
        wait_for_interrupt_check(20, hit);
        expect_true(hit == 1, "Instruction 1 commits before FETCH");
        expect_true(dut.u_regfile.regs[1] == 32'd5, "ADDI writes x1 = 5");
        expect_true(debug_illegal == 1'b0, "No illegal instruction after ADDI x1");

        wait_for_fetch(30, hit);
        expect_true(hit == 1, "Return to FETCH after instruction 1");

        // Instruction 2: addi x2, x0, 7
        wait_for_writeback(80, hit);
        expect_true(hit == 1, "Instruction 2 reaches WRITE_BACK");
        wait_for_interrupt_check(20, hit);
        expect_true(hit == 1, "Instruction 2 commits before FETCH");
        expect_true(dut.u_regfile.regs[2] == 32'd7, "ADDI writes x2 = 7");
        expect_true(debug_illegal == 1'b0, "No illegal instruction after ADDI x2");

        wait_for_fetch(30, hit);
        expect_true(hit == 1, "Return to FETCH after instruction 2");

        // Instruction 3: add x3, x1, x2
        wait_for_writeback(80, hit);
        expect_true(hit == 1, "Instruction 3 reaches WRITE_BACK");
        wait_for_interrupt_check(20, hit);
        expect_true(hit == 1, "Instruction 3 commits before FETCH");
        expect_true(dut.u_regfile.regs[3] == 32'd12, "ADD writes x3 = x1 + x2");
        expect_true(debug_illegal == 1'b0, "No illegal instruction after ADD");

        wait_for_fetch(30, hit);
        expect_true(hit == 1, "Return to FETCH after instruction 3");

        // Instruction 4: lui x4, 0x12345
        wait_for_writeback(80, hit);
        expect_true(hit == 1, "Instruction 4 reaches WRITE_BACK");
        wait_for_interrupt_check(20, hit);
        expect_true(hit == 1, "Instruction 4 commits before FETCH");
        expect_true(dut.u_regfile.regs[4] == 32'h12345000, "LUI writes x4 = 0x12345000");
        expect_true(debug_illegal == 1'b0, "No illegal instruction after LUI");

        wait_for_fetch(30, hit);
        expect_true(hit == 1, "Return to FETCH after instruction 4");

        // Instruction 5: addi x5, x4, 1
        wait_for_writeback(80, hit);
        expect_true(hit == 1, "Instruction 5 reaches WRITE_BACK");
        wait_for_interrupt_check(20, hit);
        expect_true(hit == 1, "Instruction 5 commits before FETCH");
        expect_true(dut.u_regfile.regs[5] == 32'h12345001, "ADDI writes x5 = x4 + 1");
        expect_true(debug_illegal == 1'b0, "No illegal instruction after ADDI x5");

        // Architectural x0 invariant.
        expect_true(dut.u_regfile.regs[0] == 32'b0, "x0 remains hardwired zero");

        $display("========================================");
        $display("Phase-1 CPU Summary");
        $display("========================================");
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);

        if (fail_count == 0)
            $display("PHASE1 TESTS PASSED");
        else
            $display("PHASE1 TESTS FAILED");

        $finish;
    end

    // Global timeout guard.
    always @(posedge clk) begin
        if (!reset)
            cycle_count = cycle_count + 1;
        if (cycle_count > 500) begin
            $display("FAIL: Simulation timeout");
            $finish;
        end
    end

endmodule
