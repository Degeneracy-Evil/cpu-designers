`timescale 1ns/1ps
`include "core_bus_types.svh"

module tb_exception_contract_unit;
    reg clk=0,resetn=0;always #5 clk=~clk;
    exception_t sync_exception_now;
    reg trap_enter_valid,trap_return_valid;
    trap_return_kind_t trap_return_kind;
    priv_mode_t priv_mode;
    reg [31:0] csr_mstatus,csr_mie,csr_mtvec,csr_mepc,csr_mip;
    reg [31:0] csr_medeleg,csr_mideleg,csr_stvec,csr_sepc,current_pc;
    wire sync_exception_pending,interrupt_pending;
    wire [31:0] trap_pc;
    wire priv_mode_t target_priv,hw_status_priv;
    wire hw_csr_wen,hw_trap_is_enter;
    wire [31:0] hw_mepc_wdata,hw_mcause_wdata,hw_mtval_wdata,hw_mstatus_wdata;
    wire [31:0] hw_sepc_wdata,hw_scause_wdata,hw_stval_wdata,hw_sstatus_wdata;

    cpu_trap_manager dut(.*);
    integer pass_count=0,fail_count=0;
    task check(input condition,input [8*76-1:0] name);begin
        if(condition)begin pass_count=pass_count+1;$display("  PASS %0s",name);end
        else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
    end endtask

    task present_exception(input [31:0] cause,input [31:0] epc,input [31:0] tval);begin
        @(negedge clk);
        sync_exception_now='{valid:1'b1,cause:cause,epc:epc,tval:tval};
        @(posedge clk);#1;
        @(negedge clk);sync_exception_now='0;
    end endtask

    task consume_exception;begin
        @(negedge clk);trap_enter_valid=1;
        @(posedge clk);#1;
        @(negedge clk);trap_enter_valid=0;
        @(posedge clk);#1;
    end endtask

    initial begin
        sync_exception_now='0;trap_enter_valid=0;trap_return_valid=0;
        trap_return_kind=RET_NONE;
        priv_mode=PRIV_M;csr_mstatus=0;csr_mie=0;csr_mtvec=32'h80001000;
        csr_mepc=0;csr_mip=0;csr_medeleg=0;csr_mideleg=0;
        csr_stvec=32'h80002000;csr_sepc=0;current_pc=32'h80000400;
        repeat(4)@(posedge clk);@(negedge clk);resetn=1;repeat(2)@(posedge clk);

        present_exception(32'd1,32'h80000120,32'h40003124);
        check(sync_exception_pending&&hw_mcause_wdata==1,
              "one latch exposes the architectural exception cause");
        check(hw_mepc_wdata==32'h80000120&&hw_mtval_wdata==32'h40003124,
              "exception latch preserves EPC and virtual TVAL");

        present_exception(32'd7,32'h80000200,32'h40004008);
        check(hw_mcause_wdata==1&&hw_mepc_wdata==32'h80000120,
              "a later candidate cannot overwrite an unconsumed exception");

        consume_exception();
        check(!sync_exception_pending,"trap entry consumes the exception latch");

        present_exception(32'd12,32'h80000300,32'h50000304);
        csr_mstatus[3]=1;csr_mie[7]=1;csr_mip[7]=1;
        #1;
        check(sync_exception_pending&&interrupt_pending,
              "synchronous and interrupt pending remain independent");
        check(hw_mcause_wdata==12&&hw_mtval_wdata==32'h50000304,
              "synchronous exception has routing priority over interrupt");

        consume_exception();
        check(!sync_exception_pending&&interrupt_pending,
              "consuming an exception does not clear interrupt pending");

        $display("exception contract unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED");else $display("TEST FAILED");
        $finish;
    end
    initial begin repeat(1000)@(posedge clk);$display("TEST FAILED: timeout");$finish;end
endmodule
