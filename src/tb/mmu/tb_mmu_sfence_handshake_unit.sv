`timescale 1ns / 1ps
`include "core_bus_types.svh"

module tb_mmu_sfence_handshake_unit;
    reg clk=1'b0, resetn=1'b0;
    always #5 clk=~clk;

    reg [31:0] i_vaddr, d_vaddr;
    reg i_translate_en, d_translate_en;
    access_class_t d_access_type;
    priv_mode_t priv_mode, mstatus_mpp;
    reg [31:0] satp;
    reg mstatus_mprv, mstatus_sum, mstatus_mxr;
    wire [31:0] i_paddr, d_paddr;
    wire i_miss, d_miss, i_fault, d_fault, i_ready, d_ready;
    wire [3:0] i_fault_cause, d_fault_cause;
    wire [31:0] i_fault_vaddr, d_fault_vaddr;
    wire ptw_bus_req, ptw_bus_we;
    wire [31:0] ptw_bus_addr, ptw_bus_wdata;
    reg [31:0] ptw_bus_rdata;
    reg ptw_bus_done, ptw_bus_error;
    reg sfence_req;
    wire sfence_done;
    wire [3:0] dbg_mmu_state;
    wire dbg_mmu_owner, dbg_mmu_sv32, dbg_mmu_tlb_hit;
    wire dbg_mmu_tlb_perm_fault, dbg_mmu_ptw_active;
    wire dbg_mmu_fault_from_ptw;
    wire [31:0] dbg_mmu_req_vaddr;

    MMU dut(.*);

    integer pass_count=0, fail_count=0, done_count=0;
    always @(posedge clk) begin
        if (sfence_done) done_count <= done_count+1;
    end

    task check(input condition,input [8*72-1:0] name);
        begin
            if(condition) begin pass_count=pass_count+1;$display("  PASS %0s",name);end
            else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
        end
    endtask

    task request_sfence;
        begin
            @(negedge clk); sfence_req=1;
            while(!sfence_done) begin @(posedge clk);#1;end
            @(posedge clk);#1;
        end
    endtask

    initial begin
        i_vaddr=0;i_translate_en=0;d_vaddr=0;d_access_type=ACCESS_LOAD;d_translate_en=0;
        priv_mode=PRIV_M;satp=0;mstatus_mprv=0;mstatus_mpp=PRIV_M;
        mstatus_sum=0;mstatus_mxr=0;ptw_bus_rdata=0;ptw_bus_done=0;ptw_bus_error=0;
        sfence_req=0;
        repeat(4)@(posedge clk);@(negedge clk);resetn=1;repeat(2)@(posedge clk);

        request_sfence();
        check(done_count==1,"first held SFENCE produces one completion");
        repeat(10)@(posedge clk);#1;
        check(done_count==1,"held SFENCE is not accepted twice");

        @(negedge clk);sfence_req=0;repeat(2)@(posedge clk);
        request_sfence();
        check(done_count==2,"request drop rearms the next SFENCE");
        @(negedge clk);sfence_req=0;repeat(2)@(posedge clk);

        @(negedge clk);i_vaddr=32'h81234560;i_translate_en=1;
        while(!i_ready)begin @(posedge clk);#1;end
        check(i_paddr==i_vaddr&&dbg_mmu_owner==1'b0&&
              dbg_mmu_req_vaddr==i_vaddr,"unified debug reports instruction owner and request VA");
        @(negedge clk);i_translate_en=0;repeat(2)@(posedge clk);

        @(negedge clk);d_vaddr=32'h82345670;d_translate_en=1;
        while(!d_ready)begin @(posedge clk);#1;end
        check(d_paddr==d_vaddr&&dbg_mmu_owner==1'b1&&
              dbg_mmu_req_vaddr==d_vaddr,"unified debug reports data owner and request VA");
        @(negedge clk);d_translate_en=0;

        // Start a real Sv32 walk and hold its first memory transaction.  A
        // concurrent SFENCE must wait for that transaction to drain before it
        // flushes the TLB and reports completion.
        @(negedge clk);satp=32'h80000001;priv_mode=PRIV_S;
        while(dbg_mmu_state!=0)begin @(posedge clk);#1;end
        @(negedge clk);i_vaddr=32'h80403020;i_translate_en=1;
        while(!ptw_bus_req)begin @(posedge clk);#1;end
        check(dbg_mmu_ptw_active,"unified debug reports active PTW");
        @(negedge clk);sfence_req=1;
        repeat(3)begin @(posedge clk);#1;end
        check(!sfence_done&&ptw_bus_req,
              "SFENCE waits for an outstanding PTW bus transaction");
        @(negedge clk);ptw_bus_done=1;
        @(posedge clk);#1;
        @(negedge clk);ptw_bus_done=0;
        while(!sfence_done)begin @(posedge clk);#1;end
        @(posedge clk);#1;
        check(done_count==3,"SFENCE completes once after PTW drain and flush");
        repeat(6)@(posedge clk);#1;
        check(done_count==3,"held post-drain SFENCE is not accepted twice");
        @(negedge clk);sfence_req=0;i_translate_en=0;satp=0;priv_mode=PRIV_M;

        $display("mmu sfence handshake unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(!fail_count)$display("ALL TESTS PASSED");else $display("TEST FAILED");
        $finish;
    end

    initial begin repeat(2000)@(posedge clk);$display("TEST FAILED: timeout");$finish;end
endmodule
