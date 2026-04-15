`timescale 1ns / 1ps

module tb_phase2_cpu;

    reg clk;
    reg reset;

    wire [31:0] debug_pc;
    wire [31:0] debug_instr;
    wire [4:0]  debug_state;
    wire        debug_illegal;
    wire [31:0] debug_mem_addr;
    wire [31:0] debug_mem_wdata;
    wire [31:0] debug_mem_rdata;
    wire [3:0]  debug_mem_wstrb;

    integer pass_count;
    integer fail_count;
    integer i;
    reg illegal_seen;

    cpu_top #(
        .IMEM_DEPTH(128),
        .DMEM_DEPTH(256)
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
        .debug_mem_wstrb(debug_mem_wstrb)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!reset && debug_illegal)
            illegal_seen <= 1'b1;
    end

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

    task clear_imem;
        begin
            for (i = 0; i < 128; i = i + 1)
                dut.u_instr_mem.mem[i] = 32'h00000013;
        end
    endtask

    task run_case;
        input integer run_cycles;
        begin
            illegal_seen = 1'b0;
            reset = 1'b1;
            repeat (3) @(posedge clk);
            reset = 1'b0;
            repeat (run_cycles) @(posedge clk);
        end
    endtask

    task load_rtype_program;
        begin
            clear_imem;
            dut.u_instr_mem.mem[0]  = 32'h01400093; // addi x1, x0, 20
            dut.u_instr_mem.mem[1]  = 32'h00300113; // addi x2, x0, 3
            dut.u_instr_mem.mem[2]  = 32'hff000693; // addi x13, x0, -16
            dut.u_instr_mem.mem[3]  = 32'h002081b3; // add x3, x1, x2
            dut.u_instr_mem.mem[4]  = 32'h40208233; // sub x4, x1, x2
            dut.u_instr_mem.mem[5]  = 32'h002112b3; // sll x5, x2, x2
            dut.u_instr_mem.mem[6]  = 32'h00112333; // slt x6, x2, x1
            dut.u_instr_mem.mem[7]  = 32'h001133b3; // sltu x7, x2, x1
            dut.u_instr_mem.mem[8]  = 32'h0020c433; // xor x8, x1, x2
            dut.u_instr_mem.mem[9]  = 32'h0020d4b3; // srl x9, x1, x2
            dut.u_instr_mem.mem[10] = 32'h4026d533; // sra x10, x13, x2
            dut.u_instr_mem.mem[11] = 32'h0020e5b3; // or x11, x1, x2
            dut.u_instr_mem.mem[12] = 32'h0020f633; // and x12, x1, x2
        end
    endtask

    task load_itype_program;
        begin
            clear_imem;
            dut.u_instr_mem.mem[0]  = 32'hff800093; // addi x1, x0, -8
            dut.u_instr_mem.mem[1]  = 32'h00300113; // addi x2, x0, 3
            dut.u_instr_mem.mem[2]  = 32'hfff0a193; // slti x3, x1, -1
            dut.u_instr_mem.mem[3]  = 32'h0010b213; // sltiu x4, x1, 1
            dut.u_instr_mem.mem[4]  = 32'h00614293; // xori x5, x2, 6
            dut.u_instr_mem.mem[5]  = 32'h00816313; // ori x6, x2, 8
            dut.u_instr_mem.mem[6]  = 32'h00a37393; // andi x7, x6, 10
            dut.u_instr_mem.mem[7]  = 32'h00411413; // slli x8, x2, 4
            dut.u_instr_mem.mem[8]  = 32'h00345493; // srli x9, x8, 3
            dut.u_instr_mem.mem[9]  = 32'h4020d513; // srai x10, x1, 2
        end
    endtask

    task load_mem_program;
        begin
            clear_imem;
            dut.u_instr_mem.mem[0]  = 32'h02000093; // addi x1, x0, 0x20
            dut.u_instr_mem.mem[1]  = 32'h11223137; // lui x2, 0x11223
            dut.u_instr_mem.mem[2]  = 32'h34410113; // addi x2, x2, 0x344
            dut.u_instr_mem.mem[3]  = 32'h0020a023; // sw x2, 0(x1)
            dut.u_instr_mem.mem[4]  = 32'h00008183; // lb x3, 0(x1)
            dut.u_instr_mem.mem[5]  = 32'h0000c203; // lbu x4, 0(x1)
            dut.u_instr_mem.mem[6]  = 32'h00308283; // lb x5, 3(x1)
            dut.u_instr_mem.mem[7]  = 32'h00009303; // lh x6, 0(x1)
            dut.u_instr_mem.mem[8]  = 32'h0000d383; // lhu x7, 0(x1)
            dut.u_instr_mem.mem[9]  = 32'h0000a403; // lw x8, 0(x1)
            dut.u_instr_mem.mem[10] = 32'hfff00493; // addi x9, x0, -1
            dut.u_instr_mem.mem[11] = 32'h009080a3; // sb x9, 1(x1)
            dut.u_instr_mem.mem[12] = 32'h0000d503; // lhu x10, 0(x1)
            dut.u_instr_mem.mem[13] = 32'h00009583; // lh x11, 0(x1)
            dut.u_instr_mem.mem[14] = 32'h00909123; // sh x9, 2(x1)
            dut.u_instr_mem.mem[15] = 32'h0000a603; // lw x12, 0(x1)
        end
    endtask

    task load_branch_program;
        begin
            clear_imem;
            dut.u_instr_mem.mem[0]  = 32'h00500093; // addi x1, x0, 5
            dut.u_instr_mem.mem[1]  = 32'h00500113; // addi x2, x0, 5
            dut.u_instr_mem.mem[2]  = 32'h00000193; // addi x3, x0, 0
            dut.u_instr_mem.mem[3]  = 32'h00208463; // beq x1, x2, +8
            dut.u_instr_mem.mem[4]  = 32'h00118193; // addi x3, x3, 1 (skip)
            dut.u_instr_mem.mem[5]  = 32'h00218193; // addi x3, x3, 2
            dut.u_instr_mem.mem[6]  = 32'h00209463; // bne x1, x2, +8 (not taken)
            dut.u_instr_mem.mem[7]  = 32'h00418193; // addi x3, x3, 4
            dut.u_instr_mem.mem[8]  = 32'h00114463; // blt x2, x1, +8 (not taken)
            dut.u_instr_mem.mem[9]  = 32'h00818193; // addi x3, x3, 8
            dut.u_instr_mem.mem[10] = 32'h0020d463; // bge x1, x2, +8 (taken)
            dut.u_instr_mem.mem[11] = 32'h01018193; // addi x3, x3, 16 (skip)
            dut.u_instr_mem.mem[12] = 32'h00116463; // bltu x2, x1, +8 (not taken)
            dut.u_instr_mem.mem[13] = 32'h02018193; // addi x3, x3, 32
            dut.u_instr_mem.mem[14] = 32'h0020f463; // bgeu x1, x2, +8 (taken)
            dut.u_instr_mem.mem[15] = 32'h04018193; // addi x3, x3, 64 (skip)
            dut.u_instr_mem.mem[16] = 32'h08018193; // addi x3, x3, 128
        end
    endtask

    task load_jump_program;
        begin
            clear_imem;
            dut.u_instr_mem.mem[0] = 32'h00001097; // auipc x1, 0x1
            dut.u_instr_mem.mem[1] = 32'h0080016f; // jal x2, +8
            dut.u_instr_mem.mem[2] = 32'h00100193; // addi x3, x0, 1 (skip)
            dut.u_instr_mem.mem[3] = 32'h00200193; // addi x3, x0, 2
            dut.u_instr_mem.mem[4] = 32'h01800213; // addi x4, x0, 24
            dut.u_instr_mem.mem[5] = 32'h000202e7; // jalr x5, x4, 0
            dut.u_instr_mem.mem[6] = 32'h0000000f; // fence
            dut.u_instr_mem.mem[7] = 32'h0000100f; // fence.i
            dut.u_instr_mem.mem[8] = 32'h00600313; // addi x6, x0, 6
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        illegal_seen = 1'b0;
        reset = 1'b1;

        $display("========================================");
        $display("Phase-2 CPU Test");
        $display("========================================");

        load_rtype_program;
        run_case(260);
        expect_true(illegal_seen == 1'b0, "R-type program has no illegal decode");
        expect_true(dut.u_regfile.regs[3] == 32'd23, "R-type ADD");
        expect_true(dut.u_regfile.regs[4] == 32'd17, "R-type SUB");
        expect_true(dut.u_regfile.regs[5] == 32'd24, "R-type SLL");
        expect_true(dut.u_regfile.regs[6] == 32'd1, "R-type SLT");
        expect_true(dut.u_regfile.regs[7] == 32'd1, "R-type SLTU");
        expect_true(dut.u_regfile.regs[8] == 32'd23, "R-type XOR");
        expect_true(dut.u_regfile.regs[9] == 32'd2, "R-type SRL");
        expect_true(dut.u_regfile.regs[10] == 32'hffff_fffe, "R-type SRA");
        expect_true(dut.u_regfile.regs[11] == 32'd23, "R-type OR");
        expect_true(dut.u_regfile.regs[12] == 32'd0, "R-type AND");

        load_itype_program;
        run_case(220);
        expect_true(illegal_seen == 1'b0, "I-type program has no illegal decode");
        expect_true(dut.u_regfile.regs[3] == 32'd1, "I-type SLTI");
        expect_true(dut.u_regfile.regs[4] == 32'd0, "I-type SLTIU");
        expect_true(dut.u_regfile.regs[5] == 32'd5, "I-type XORI");
        expect_true(dut.u_regfile.regs[6] == 32'd11, "I-type ORI");
        expect_true(dut.u_regfile.regs[7] == 32'd10, "I-type ANDI");
        expect_true(dut.u_regfile.regs[8] == 32'd48, "I-type SLLI");
        expect_true(dut.u_regfile.regs[9] == 32'd6, "I-type SRLI");
        expect_true(dut.u_regfile.regs[10] == 32'hffff_fffe, "I-type SRAI");

        load_mem_program;
        run_case(320);
        expect_true(illegal_seen == 1'b0, "Load/Store program has no illegal decode");
        expect_true(dut.u_regfile.regs[3] == 32'h0000_0044, "LB sign-extend low byte");
        expect_true(dut.u_regfile.regs[4] == 32'h0000_0044, "LBU zero-extend low byte");
        expect_true(dut.u_regfile.regs[5] == 32'h0000_0011, "LB from byte 3");
        expect_true(dut.u_regfile.regs[6] == 32'h0000_3344, "LH sign-extend halfword");
        expect_true(dut.u_regfile.regs[7] == 32'h0000_3344, "LHU zero-extend halfword");
        expect_true(dut.u_regfile.regs[8] == 32'h1122_3344, "LW full word");
        expect_true(dut.u_regfile.regs[10] == 32'h0000_ff44, "LHU after SB");
        expect_true(dut.u_regfile.regs[11] == 32'hffff_ff44, "LH after SB");
        expect_true(dut.u_regfile.regs[12] == 32'hffff_ff44, "LW after SH");

        load_branch_program;
        run_case(320);
        expect_true(illegal_seen == 1'b0, "Branch program has no illegal decode");
        expect_true(dut.u_regfile.regs[3] == 32'd174, "Branch path result");

        load_jump_program;
        run_case(260);
        expect_true(illegal_seen == 1'b0, "Jump/FENCE program has no illegal decode");
        expect_true(dut.u_regfile.regs[1] == 32'h0000_1000, "AUIPC result");
        expect_true(dut.u_regfile.regs[2] == 32'h0000_0008, "JAL link register");
        expect_true(dut.u_regfile.regs[3] == 32'h0000_0002, "JAL skip behavior");
        expect_true(dut.u_regfile.regs[5] == 32'h0000_0018, "JALR link register");
        expect_true(dut.u_regfile.regs[6] == 32'h0000_0006, "FENCE/FENCE.I behave as NOP");

        expect_true(dut.u_regfile.regs[0] == 32'b0, "x0 remains zero");

        $display("========================================");
        $display("Phase-2 CPU Summary");
        $display("========================================");
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);

        if (fail_count == 0)
            $display("PHASE2 TESTS PASSED");
        else
            $display("PHASE2 TESTS FAILED");

        $finish;
    end

endmodule
