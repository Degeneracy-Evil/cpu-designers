`timescale 1ns / 1ps

module tb_cpu_clint_unit;
    localparam [1:0] PRIV_U = 2'b00;
    localparam [1:0] PRIV_S = 2'b01;
    localparam [1:0] PRIV_M = 2'b11;

    reg         clk;
    reg         resetn;
    reg         exception_valid;
    reg  [31:0] exception_cause;
    reg  [31:0] exception_pc;
    reg  [31:0] exception_mtval;
    reg         mret_req;
    reg         sret_req;
    reg         trap_enter_valid;
    reg  [31:0] interrupt_pc;
    reg  [1:0]  priv_mode;
    reg  [31:0] csr_mstatus;
    reg  [31:0] csr_mie;
    reg  [31:0] csr_mtvec;
    reg  [31:0] csr_mepc;
    reg  [31:0] csr_mip;
    reg  [31:0] csr_medeleg;
    reg  [31:0] csr_mideleg;
    reg  [31:0] csr_stvec;
    reg  [31:0] csr_sepc;

    wire        trap_enter;
    wire        trap_return;
    wire [31:0] trap_pc;
    wire [1:0]  target_priv;
    wire        hw_csr_wen;
    wire        hw_trap_is_enter;
    wire [1:0]  hw_target_priv;
    wire [31:0] hw_mepc_wdata;
    wire [31:0] hw_mcause_wdata;
    wire [31:0] hw_mtval_wdata;
    wire [31:0] hw_mstatus_wdata;
    wire [31:0] hw_sepc_wdata;
    wire [31:0] hw_scause_wdata;
    wire [31:0] hw_stval_wdata;
    wire [31:0] hw_sstatus_wdata;

    integer pass_count;
    integer fail_count;

    cpu_clint dut (
        .clk(clk),
        .resetn(resetn),
        .exception_valid(exception_valid),
        .exception_cause(exception_cause),
        .exception_pc(exception_pc),
        .exception_mtval(exception_mtval),
        .mret_req(mret_req),
        .sret_req(sret_req),
        .trap_enter_valid(trap_enter_valid),
        .interrupt_pc(interrupt_pc),
        .priv_mode(priv_mode),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mtvec(csr_mtvec),
        .csr_mepc(csr_mepc),
        .csr_mip(csr_mip),
        .csr_medeleg(csr_medeleg),
        .csr_mideleg(csr_mideleg),
        .csr_stvec(csr_stvec),
        .csr_sepc(csr_sepc),
        .trap_enter(trap_enter),
        .trap_return(trap_return),
        .trap_pc(trap_pc),
        .target_priv(target_priv),
        .hw_csr_wen(hw_csr_wen),
        .hw_trap_is_enter(hw_trap_is_enter),
        .hw_target_priv(hw_target_priv),
        .hw_mepc_wdata(hw_mepc_wdata),
        .hw_mcause_wdata(hw_mcause_wdata),
        .hw_mtval_wdata(hw_mtval_wdata),
        .hw_mstatus_wdata(hw_mstatus_wdata),
        .hw_sepc_wdata(hw_sepc_wdata),
        .hw_scause_wdata(hw_scause_wdata),
        .hw_stval_wdata(hw_stval_wdata),
        .hw_sstatus_wdata(hw_sstatus_wdata)
    );

    task check;
        input condition;
        input [8*64-1:0] name;
        begin
            if (condition) begin
                pass_count = pass_count + 1;
                $display("  PASS %0s", name);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL %0s", name);
            end
        end
    endtask

    task clear_inputs;
        begin
            exception_valid = 1'b0;
            exception_cause = 32'b0;
            exception_pc = 32'h8000_0100;
            exception_mtval = 32'b0;
            mret_req = 1'b0;
            sret_req = 1'b0;
            trap_enter_valid = 1'b1;
            interrupt_pc = 32'h8000_0200;
            priv_mode = PRIV_M;
            csr_mstatus = 32'b0;
            csr_mie = 32'b0;
            csr_mtvec = 32'h8000_1000;
            csr_mepc = 32'b0;
            csr_mip = 32'b0;
            csr_medeleg = 32'b0;
            csr_mideleg = 32'b0;
            csr_stvec = 32'h8000_2000;
            csr_sepc = 32'b0;
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        resetn = 1'b1;
        pass_count = 0;
        fail_count = 0;

        clear_inputs();
        csr_mie[7] = 1'b1;
        csr_mip[7] = 1'b1;
        #1;
        check(!trap_enter, "M interrupt is gated by MIE in M-mode");

        priv_mode = PRIV_S;
        #1;
        check(trap_enter && target_priv == PRIV_M && hw_mcause_wdata == 32'h8000_0007,
              "M interrupt ignores MIE below M-mode");

        clear_inputs();
        priv_mode = PRIV_M;
        csr_mstatus[1] = 1'b1;
        csr_mie[1] = 1'b1;
        csr_mip[1] = 1'b1;
        csr_mideleg[1] = 1'b1;
        #1;
        check(!trap_enter, "delegated S interrupt cannot preempt M-mode");

        priv_mode = PRIV_S;
        csr_mstatus[1] = 1'b0;
        #1;
        check(!trap_enter, "S interrupt is gated by SIE in S-mode");

        priv_mode = PRIV_U;
        #1;
        check(trap_enter && target_priv == PRIV_S && hw_scause_wdata == 32'h8000_0001,
              "S interrupt ignores SIE below S-mode");

        clear_inputs();
        priv_mode = PRIV_S;
        csr_mstatus[1] = 1'b1;
        csr_mie[1] = 1'b1;
        csr_mip[3] = 1'b1;
        csr_mideleg[1] = 1'b1;
        #1;
        check(!trap_enter, "MSIP is not aliased to SSIP");

        clear_inputs();
        priv_mode = PRIV_M;
        exception_valid = 1'b1;
        exception_cause = 32'd8;
        csr_medeleg[8] = 1'b1;
        #1;
        check(trap_enter && target_priv == PRIV_M, "M-mode exception is never delegated");

        priv_mode = PRIV_U;
        #1;
        check(trap_enter && target_priv == PRIV_S && hw_scause_wdata == 32'd8,
              "U-mode delegated exception targets S-mode");

        clear_inputs();
        priv_mode = PRIV_M;
        mret_req = 1'b1;
        csr_mstatus[17] = 1'b1;
        csr_mstatus[12:11] = PRIV_S;
        #1;
        check(hw_csr_wen && !hw_mstatus_wdata[17],
              "MRET below M-mode clears MPRV");

        csr_mstatus[12:11] = PRIV_M;
        #1;
        check(hw_mstatus_wdata[17],
              "MRET to M-mode preserves MPRV");

        clear_inputs();
        priv_mode = PRIV_S;
        sret_req = 1'b1;
        csr_mstatus[17] = 1'b1;
        #1;
        check(hw_csr_wen && !hw_sstatus_wdata[17],
              "SRET clears stale MPRV state");

        $display("cpu_clint unit: pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end
endmodule
