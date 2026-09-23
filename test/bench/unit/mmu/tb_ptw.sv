`timescale 1ns/1ps
`include "core/interface/types.svh"

module tb_ptw;
    reg clk=0,resetn=0;
    always #5 clk=~clk;

    reg [31:0] satp;
    priv_mode_t priv_mode;
    access_class_t access_type;
    reg [31:0] walk_vaddr;
    reg walk_req,walk_abort;
    wire walk_idle,walk_done,walk_fault,walk_g;
    wire [3:0] walk_fault_cause;
    wire [31:0] walk_fault_vaddr;
    wire [21:0] walk_ppn;
    wire walk_r,walk_w,walk_x,walk_u,walk_a,walk_d,walk_is_megapage;
    wire ptw_bus_req,ptw_bus_we;
    wire [31:0] ptw_bus_addr,ptw_bus_wdata;
    reg [31:0] ptw_bus_rdata;
    reg ptw_bus_done,ptw_bus_error;

    ptw dut(
        .clk(clk),.resetn(resetn),.satp(satp),.priv_mode(priv_mode),
        .mstatus_sum(1'b0),.mstatus_mxr(1'b0),.access_type(access_type),
        .walk_vaddr(walk_vaddr),.walk_req(walk_req),.walk_abort(walk_abort),
        .walk_idle(walk_idle),.walk_done(walk_done),.walk_fault(walk_fault),
        .walk_fault_cause(walk_fault_cause),.walk_fault_vaddr(walk_fault_vaddr),
        .walk_ppn(walk_ppn),.walk_r(walk_r),.walk_w(walk_w),.walk_x(walk_x),
        .walk_u(walk_u),.walk_a(walk_a),.walk_d(walk_d),.walk_g(walk_g),
        .walk_is_megapage(walk_is_megapage),.ptw_bus_req(ptw_bus_req),
        .ptw_bus_addr(ptw_bus_addr),.ptw_bus_we(ptw_bus_we),
        .ptw_bus_wdata(ptw_bus_wdata),.ptw_bus_rdata(ptw_bus_rdata),
        .ptw_bus_done(ptw_bus_done),.ptw_bus_error(ptw_bus_error)
    );

    integer pass_count=0,fail_count=0;
    task check(input condition,input [8*80-1:0] name);begin
        if(condition)begin pass_count=pass_count+1;$display("  PASS %0s",name);end
        else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
    end endtask

    task respond_pte(input [31:0] expected_addr,input [31:0] pte);begin
        wait(ptw_bus_req);#1;
        check(ptw_bus_addr==expected_addr&&!ptw_bus_we,"PTW requests expected PTE address");
        @(negedge clk);ptw_bus_rdata=pte;ptw_bus_done=1;
        @(negedge clk);ptw_bus_done=0;
    end endtask

    task start_walk;begin
        wait(walk_idle);@(negedge clk);walk_req=1;
        @(negedge clk);walk_req=0;
    end endtask

    initial begin
        satp=32'h8000_0001;priv_mode=PRIV_U;access_type=ACCESS_LOAD;
        walk_vaddr=0;walk_req=0;walk_abort=0;
        ptw_bus_rdata=0;ptw_bus_done=0;ptw_bus_error=0;
        repeat(3)@(posedge clk);@(negedge clk);resetn=1;

        start_walk();
        // Root PPN=1. L1 non-leaf points to PPN=2 and marks the subtree global.
        respond_pte(32'h0000_1000,32'h0000_0821);
        // L0 leaf points to PPN=3; U/R/A/D are set, leaf G is clear.
        respond_pte(32'h0000_2000,32'h0000_0cd3);
        wait(walk_done||walk_fault);#1;
        check(walk_done&&!walk_fault&&walk_g,
              "non-leaf G is inherited by the final Sv32 translation");

        @(posedge clk);start_walk();
        respond_pte(32'h0000_1000,32'h0000_0801);
        respond_pte(32'h0000_2000,32'h0000_0cd3);
        wait(walk_done||walk_fault);#1;
        check(walk_done&&!walk_fault&&!walk_g,
              "global inheritance state clears at each new walk");

        $display("ptw global unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED");else $fatal(1, "TEST FAILED");
        $finish;
    end

    initial begin
        repeat (1800) @(posedge clk);
        $fatal(1, "TEST FAILED: timeout");
    end
endmodule
