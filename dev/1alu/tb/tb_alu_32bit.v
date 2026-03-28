`timescale 1ns / 1ps

module tb_alu_32bit;

    reg clk;
    reg reset;
    reg [15:0] alu_control;
    reg [31:0] src1;
    reg [31:0] src2;
    wire [31:0] result;
    wire done;

    integer test_count;
    integer pass_count;
    integer fail_count;

    alu_32bit uut (
        .clk(clk),
        .reset(reset),
        .alu_control(alu_control),
        .src1(src1),
        .src2(src2),
        .result(result),
        .done(done)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    task check_result;
        input [31:0] expected;
        input [255:0] test_name;
        begin
            test_count = test_count + 1;
            if (result == expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s", test_name);
                $display("  Expected: %h, Got: %h", expected, result);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s", test_name);
                $display("  Expected: %h, Got: %h", expected, result);
            end
            $display("");
        end
    endtask

    task wait_for_done;
        begin
            while (!done) @(posedge clk);
            @(posedge clk);
        end
    endtask

    initial begin
        $display("========================================");
        $display("ALU 32-bit Test Report");
        $display("========================================");
        $display("");

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        reset = 1;
        alu_control = 16'b0;
        src1 = 32'b0;
        src2 = 32'b0;

        #20 reset = 0;
        #20;

        // Test 1: ADD - Basic addition
        $display("Test %0d: ADD - Basic addition", test_count + 1);
        alu_control = 16'b0001_0000_0000_0000; // ADD
        src1 = 32'd12345;
        src2 = 32'd67890;
        #10;
        check_result(32'd80235, "ADD: 12345 + 67890");

        // Test 2: ADD - Addition with negative
        $display("Test %0d: ADD - Addition with negative", test_count + 1);
        alu_control = 16'b0001_0000_0000_0000; // ADD
        src1 = 32'hffffffff; // -1
        src2 = 32'd1;
        #10;
        check_result(32'd0, "ADD: -1 + 1");

        // Test 3: SUB - Basic subtraction
        $display("Test %0d: SUB - Basic subtraction", test_count + 1);
        alu_control = 16'b0000_1000_0000_0000; // SUB
        src1 = 32'd100;
        src2 = 32'd50;
        #10;
        check_result(32'd50, "SUB: 100 - 50");

        // Test 4: SUB - Negative result
        $display("Test %0d: SUB - Negative result", test_count + 1);
        alu_control = 16'b0000_1000_0000_0000; // SUB
        src1 = 32'd50;
        src2 = 32'd100;
        #10;
        check_result(32'hffffffce, "SUB: 50 - 100 = -50");

        // Test 5: SLT - Signed less than (true)
        $display("Test %0d: SLT - Signed less than (true)", test_count + 1);
        alu_control = 16'b0000_0100_0000_0000; // SLT
        src1 = 32'd1;
        src2 = 32'd2;
        #10;
        check_result(32'd1, "SLT: 1 < 2");

        // Test 6: SLT - Signed less than (false)
        $display("Test %0d: SLT - Signed less than (false)", test_count + 1);
        alu_control = 16'b0000_0100_0000_0000; // SLT
        src1 = 32'd2;
        src2 = 32'd1;
        #10;
        check_result(32'd0, "SLT: 2 < 1");

        // Test 7: SLT - Negative comparison
        $display("Test %0d: SLT - Negative comparison", test_count + 1);
        alu_control = 16'b0000_0100_0000_0000; // SLT
        src1 = 32'hffffffff; // -1
        src2 = 32'd1;
        #10;
        check_result(32'd1, "SLT: -1 < 1");

        // Test 8: SLTU - Unsigned less than
        $display("Test %0d: SLTU - Unsigned less than", test_count + 1);
        alu_control = 16'b0000_0010_0000_0000; // SLTU
        src1 = 32'd1;
        src2 = 32'd2;
        #10;
        check_result(32'd1, "SLTU: 1 < 2 (unsigned)");

        // Test 9: SLTU - Unsigned comparison with max
        $display("Test %0d: SLTU - Unsigned comparison with max", test_count + 1);
        alu_control = 16'b0000_0010_0000_0000; // SLTU
        src1 = 32'hffffffff; // Max unsigned
        src2 = 32'd1;
        #10;
        check_result(32'd0, "SLTU: 0xFFFFFFFF < 1 (unsigned)");

        // Test 10: AND
        $display("Test %0d: AND - Bitwise AND", test_count + 1);
        alu_control = 16'b0000_0001_0000_0000; // AND
        src1 = 32'h12345678;
        src2 = 32'hf0f0f0f0;
        #10;
        check_result(32'h10305070, "AND: 0x12345678 & 0xf0f0f0f0");

        // Test 11: OR
        $display("Test %0d: OR - Bitwise OR", test_count + 1);
        alu_control = 16'b0000_0000_0100_0000; // OR
        src1 = 32'h12345678;
        src2 = 32'h87654321;
        #10;
        check_result(32'h97755779, "OR: 0x12345678 | 0x87654321");

        // Test 12: NOT
        $display("Test %0d: NOT - Bitwise NOT", test_count + 1);
        alu_control = 16'b0000_0010_0000_0000; // NOT (bit 13)
        alu_control = 16'b0010_0000_0000_0000; // NOT
        src1 = 32'h0f0f0f0f;
        #10;
        check_result(32'hf0f0f0f0, "NOT: ~0x0f0f0f0f");

        // Test 13: XOR
        $display("Test %0d: XOR - Bitwise XOR", test_count + 1);
        alu_control = 16'b0000_0000_0010_0000; // XOR
        src1 = 32'h10101010;
        src2 = 32'h01010101;
        #10;
        check_result(32'h11111111, "XOR: 0x10101010 ^ 0x01010101");

        // Test 14: NOR
        $display("Test %0d: NOR - Bitwise NOR", test_count + 1);
        alu_control = 16'b0000_0000_1000_0000; // NOR
        src1 = 32'h00000000;
        src2 = 32'h00000000;
        #10;
        check_result(32'hffffffff, "NOR: ~(0 | 0)");

        // Test 15: SLL - Shift left logical
        $display("Test %0d: SLL - Shift left logical", test_count + 1);
        alu_control = 16'b0000_0000_0001_0000; // SLL
        src1 = 32'd4; // Shift amount
        src2 = 32'h0000000f; // Value to shift
        #10;
        check_result(32'h000000f0, "SLL: 0x0f << 4");

        // Test 16: SRL - Shift right logical
        $display("Test %0d: SRL - Shift right logical", test_count + 1);
        alu_control = 16'b0000_0000_0000_1000; // SRL
        src1 = 32'd4; // Shift amount
        src2 = 32'h000000f0; // Value to shift
        #10;
        check_result(32'h0000000f, "SRL: 0xf0 >> 4");

        // Test 17: SRA - Shift right arithmetic (positive)
        $display("Test %0d: SRA - Shift right arithmetic (positive)", test_count + 1);
        alu_control = 16'b0000_0000_0000_0100; // SRA
        src1 = 32'd4; // Shift amount
        src2 = 32'h000000f0; // Positive value
        #10;
        check_result(32'h0000000f, "SRA: 0xf0 >>> 4 (positive)");

        // Test 18: SRA - Shift right arithmetic (negative)
        $display("Test %0d: SRA - Shift right arithmetic (negative)", test_count + 1);
        alu_control = 16'b0000_0000_0000_0100; // SRA
        src1 = 32'd4; // Shift amount
        src2 = 32'hf0000000; // Negative value
        #10;
        check_result(32'hff000000, "SRA: 0xf0000000 >>> 4 (negative)");

        // Test 19: LUI - Load upper immediate
        $display("Test %0d: LUI - Load upper immediate", test_count + 1);
        alu_control = 16'b0000_0000_0000_0010; // LUI
        src2 = 32'h0000bfc0;
        #10;
        check_result(32'hbfc00000, "LUI: 0xbfc0 << 16");

// Test 20: MUL - Multiplication (positive * positive)
        $display("Test %0d: MUL - Multiplication (positive * positive)", test_count + 1);
        src1 = 32'd123;
        src2 = 32'd456;
        #10; // Wait for signals to settle
        alu_control = 16'b1000_0000_0000_0000; // MUL
        #10; // Wait for mul_start to be set
        wait_for_done();
        check_result(32'd56088, "MUL: 123 * 456");
        
        // Test 21: MUL - Multiplication (negative * positive)
        $display("Test %0d: MUL - Multiplication (negative * positive)", test_count + 1);
        src1 = 32'hffffff85; // -123
        src2 = 32'd456;
        #10;
        alu_control = 16'b1000_0000_0000_0000; // MUL
        #10;
        wait_for_done();
        check_result(32'hffff24e8, "MUL: -123 * 456");
        
        // Test 22: MUL - Multiplication (negative * negative)
        $display("Test %0d: MUL - Multiplication (negative * negative)", test_count + 1);
        src1 = 32'hffffff85; // -123
        src2 = 32'hfffffe38; // -456
        #10;
        alu_control = 16'b1000_0000_0000_0000; // MUL
        #10;
        wait_for_done();
        check_result(32'd56088, "MUL: -123 * -456");
        
        // Test 23: DIV - Division (positive / positive)
        $display("Test %0d: DIV - Division (positive / positive)", test_count + 1);
        src1 = 32'd1000;
        src2 = 32'd7;
        #10;
        alu_control = 16'b0100_0000_0000_0000; // DIV
        #10;
        wait_for_done();
        check_result(32'd142, "DIV: 1000 / 7");
        
        // Test 24: DIV - Division (negative / positive)
        $display("Test %0d: DIV - Division (negative / positive)", test_count + 1);
        src1 = 32'hfffffc18; // -1000
        src2 = 32'd7;
        #10;
        alu_control = 16'b0100_0000_0000_0000; // DIV
        #10;
        wait_for_done();
        check_result(32'hffffff72, "DIV: -1000 / 7");
        
        // Test 25: DIV - Division (positive / negative)
        $display("Test %0d: DIV - Division (positive / negative)", test_count + 1);
        src1 = 32'd1000;
        src2 = 32'hfffffff9; // -7
        #10;
        alu_control = 16'b0100_0000_0000_0000; // DIV
        #10;
        wait_for_done();
        check_result(32'hffffff72, "DIV: 1000 / -7");

        // Test 26: ADD - Zero
        $display("Test %0d: ADD - Zero", test_count + 1);
        alu_control = 16'b0001_0000_0000_0000; // ADD
        src1 = 32'd0;
        src2 = 32'd0;
        #10;
        check_result(32'd0, "ADD: 0 + 0");

        // Test 27: SUB - Same value
        $display("Test %0d: SUB - Same value", test_count + 1);
        alu_control = 16'b0000_1000_0000_0000; // SUB
        src1 = 32'd12345;
        src2 = 32'd12345;
        #10;
        check_result(32'd0, "SUB: 12345 - 12345");

        // Test 28: SLL - Shift by zero
        $display("Test %0d: SLL - Shift by zero", test_count + 1);
        alu_control = 16'b0000_0000_0001_0000; // SLL
        src1 = 32'd0; // Shift amount
        src2 = 32'h12345678;
        #10;
        check_result(32'h12345678, "SLL: 0x12345678 << 0");

        // Test 29: SRL - Shift by 31
        $display("Test %0d: SRL - Shift by 31", test_count + 1);
        alu_control = 16'b0000_0000_0000_1000; // SRL
        src1 = 32'd31; // Shift amount
        src2 = 32'h80000000;
        #10;
        check_result(32'd1, "SRL: 0x80000000 >> 31");

        // Test 30: AND - All ones
        $display("Test %0d: AND - All ones", test_count + 1);
        alu_control = 16'b0000_0001_0000_0000; // AND
        src1 = 32'hffffffff;
        src2 = 32'hffffffff;
        #10;
        check_result(32'hffffffff, "AND: 0xFFFFFFFF & 0xFFFFFFFF");

        #100;

        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("Pass rate:   %0.1f%%", (pass_count * 100.0) / test_count);
        $display("========================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");

        $finish;
    end

endmodule