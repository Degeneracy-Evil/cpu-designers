`timescale 1ns/1ps
`include "axi4_def.svh"
`include "core_bus_types.svh"

module tb_cpu_mem_contract_unit;
    reg clk=0, resetn=0;
    always #5 clk=~clk;

    reg mem_valid, trap_enter, mem_access_ready;
    reg [31:0] mem_access_paddr;
    reg [31:0] phys_resp_rdata;
    reg phys_resp_valid;
    exe_mem_bus_t exe_mem_bus_r;
    wire mem_access_valid, phys_req_valid, phys_req_write, mem_done;
    wire [31:0] mem_vaddr, phys_req_paddr, phys_req_wdata, mem_pc, mem_inst;
    wire [2:0] mem_access_size, phys_req_size;
    mem_kind_t mem_kind;
    access_class_t mem_access_type;
    wb_bus_t mem_wb_bus;
    exception_t mem_exception;

    cpu_mem dut(.*);

    integer pass_count=0, fail_count=0;
    task check(input condition,input [8*80-1:0] name); begin
        if(condition)begin pass_count=pass_count+1;$display("  PASS %0s",name);end
        else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
    end endtask

    task start_op(
        input mem_kind_t kind,
        input [31:0] addr,
        input [31:0] data,
        input [2:0] size,
        input [4:0] funct5
    ); begin
        @(negedge clk);
        exe_mem_bus_r='0;
        exe_mem_bus_r.pc=32'h80000100;
        exe_mem_bus_r.pc_plus4=32'h80000104;
        exe_mem_bus_r.inst=32'h00000013;
        exe_mem_bus_r.result=addr;
        exe_mem_bus_r.wb_we=(kind!=MEM_STORE);
        exe_mem_bus_r.wb_rd=5'd5;
        exe_mem_bus_r.mem_kind=kind;
        exe_mem_bus_r.mem_size=size;
        exe_mem_bus_r.store_data=data;
        exe_mem_bus_r.amo_funct5=funct5;
        mem_valid=1;
        while(!mem_access_valid)begin @(posedge clk);#1;end
    end endtask

    task allow_access(input [31:0] paddr); begin
        @(negedge clk);mem_access_paddr=paddr;mem_access_ready=1;
        @(posedge clk);#1;
        @(negedge clk);mem_access_ready=0;
    end endtask

    task complete_phys(input [31:0] data); begin
        @(negedge clk);phys_resp_rdata=data;phys_resp_valid=1;
        @(posedge clk);#1;
        @(negedge clk);phys_resp_valid=0;
    end endtask

    task finish_op; begin
        while(!mem_done)begin @(posedge clk);#1;end
        @(negedge clk);mem_valid=0;
        repeat(2)@(posedge clk);
    end endtask

    initial begin
        mem_valid=0;trap_enter=0;mem_access_ready=0;mem_access_paddr=0;
        phys_resp_rdata=0;phys_resp_valid=0;exe_mem_bus_r='0;
        repeat(4)@(posedge clk);@(negedge clk);resetn=1;repeat(2)@(posedge clk);

        start_op(MEM_STORE,32'h80001003,32'h0000005a,`AXI_SIZE_BYTE,5'b0);
        check(mem_access_type==ACCESS_STORE,"ordinary store uses STORE architectural access");
        check(mem_access_size==`AXI_SIZE_BYTE,"architectural access exposes its byte size");
        allow_access(32'h90001003);
        check(phys_req_valid&&phys_req_write&&phys_req_size==`AXI_SIZE_BYTE,
              "allowed store emits one physical byte write");
        check(phys_req_paddr==32'h90001003,"store uses the checked physical address");
        check(phys_req_wdata==32'h0000005a,"cpu_mem leaves byte store data unshifted");
        complete_phys(0);finish_op();

        start_op(MEM_SC,32'h80002000,32'hcafebabe,`AXI_SIZE_WORD,5'b00011);
        check(mem_access_type==ACCESS_STORE&&!phys_req_valid,
              "SC checks STORE permission before reservation status");
        allow_access(32'h90002000);
        check(mem_done&&!phys_req_valid&&mem_wb_bus.wb_data==32'd1,
              "failed SC returns one without a physical read or write");
        finish_op();

        start_op(MEM_AMO,32'h80003000,32'd7,`AXI_SIZE_WORD,5'b00000);
        check(mem_access_type==ACCESS_STORE,"AMO read phase is STORE-class architecturally");
        allow_access(32'h90003000);
        check(phys_req_valid&&!phys_req_write,"AMO starts with a physical read");
        check(phys_req_paddr==32'h90003000,"AMO read uses the checked physical address");
        mem_access_paddr=32'ha0003000;#1;
        check(phys_req_paddr==32'h90003000,"physical request ignores later MMU PA changes");
        complete_phys(32'd11);
        check(mem_access_valid&&mem_access_type==ACCESS_STORE&&
              phys_req_valid&&phys_req_write&&phys_req_wdata==32'd18,
              "AMO retains checked access while issuing physical write");
        check(phys_req_paddr==32'h90003000,"AMO write reuses the checked read PA");
        complete_phys(0);
        check(mem_done&&mem_wb_bus.wb_data==32'd11,"AMO writes back old memory value");
        finish_op();

        start_op(MEM_LR,32'h80004000,0,`AXI_SIZE_WORD,5'b00010);
        check(mem_access_type==ACCESS_LOAD,"LR uses LOAD architectural access");
        allow_access(32'h90004000);complete_phys(32'h12345678);
        check(mem_done&&mem_wb_bus.wb_data==32'h12345678,"LR returns loaded value");
        finish_op();

        start_op(MEM_SC,32'h80005000,32'hdeadbeef,`AXI_SIZE_WORD,5'b00011);
        allow_access(32'h90004000);
        check(phys_req_valid&&phys_req_write&&phys_req_wdata==32'hdeadbeef,
              "SC succeeds across VA aliases of one physical word");
        complete_phys(0);
        check(mem_done&&mem_wb_bus.wb_data==0,"successful SC returns zero");
        finish_op();

        start_op(MEM_LR,32'h80006000,0,`AXI_SIZE_WORD,5'b00010);
        allow_access(32'h90006000);complete_phys(32'h11112222);finish_op();
        start_op(MEM_SC,32'h80006000,32'h33334444,`AXI_SIZE_WORD,5'b00011);
        allow_access(32'h90007000);
        check(mem_done&&!phys_req_valid&&mem_wb_bus.wb_data==1,
              "SC fails when the same VA translates to a different PA");
        finish_op();
        start_op(MEM_SC,32'h80006000,32'h33334444,`AXI_SIZE_WORD,5'b00011);
        allow_access(32'h90006000);
        check(mem_done&&!phys_req_valid&&mem_wb_bus.wb_data==1,
              "a failed SC attempt clears the prior reservation");
        finish_op();

        start_op(MEM_LR,32'h80008000,0,`AXI_SIZE_WORD,5'b00010);
        allow_access(32'h90008000);complete_phys(32'h55556666);finish_op();
        start_op(MEM_STORE,32'h80009000,32'h77778888,`AXI_SIZE_WORD,5'b0);
        allow_access(32'h90009000);complete_phys(0);finish_op();
        start_op(MEM_SC,32'h80008000,32'h9999aaaa,`AXI_SIZE_WORD,5'b00011);
        allow_access(32'h90008000);
        check(mem_done&&!phys_req_valid&&mem_wb_bus.wb_data==1,
              "normal store completion invalidates the reservation");
        finish_op();

        start_op(MEM_LR,32'h8000b000,0,`AXI_SIZE_WORD,5'b00010);
        allow_access(32'h9000b000);complete_phys(32'h01020304);finish_op();
        start_op(MEM_AMO,32'h8000c000,32'd1,`AXI_SIZE_WORD,5'b00000);
        allow_access(32'h9000c000);complete_phys(32'd4);complete_phys(0);finish_op();
        start_op(MEM_SC,32'h8000b000,32'h05060708,`AXI_SIZE_WORD,5'b00011);
        allow_access(32'h9000b000);
        check(mem_done&&!phys_req_valid&&mem_wb_bus.wb_data==1,
              "AMO completion invalidates the reservation");
        finish_op();

        start_op(MEM_LR,32'h8000a000,0,`AXI_SIZE_WORD,5'b00010);
        allow_access(32'h9000a000);complete_phys(32'hbbbbcccc);finish_op();
        @(negedge clk);trap_enter=1;
        @(posedge clk);#1;
        @(negedge clk);trap_enter=0;
        start_op(MEM_SC,32'h8000a000,32'hddddeeee,`AXI_SIZE_WORD,5'b00011);
        allow_access(32'h9000a000);
        check(mem_done&&!phys_req_valid&&mem_wb_bus.wb_data==1,
              "trap entry invalidates the reservation");
        finish_op();

        @(negedge clk);
        exe_mem_bus_r='0;
        exe_mem_bus_r.pc=32'h80000500;
        exe_mem_bus_r.result=32'h80005002;
        exe_mem_bus_r.mem_kind=MEM_LOAD;
        exe_mem_bus_r.mem_size=`AXI_SIZE_WORD;
        mem_valid=1;
        #1;
        check(mem_exception.valid&&mem_exception.cause==4,
              "misaligned load produces one architectural exception");
        check(mem_exception.epc==32'h80000500&&mem_exception.tval==32'h80005002,
              "memory exception preserves instruction PC and effective VA");
        @(posedge clk);#1;
        check(!mem_done&&!mem_access_valid&&!phys_req_valid,
              "misaligned load does not complete or issue a request");
        @(negedge clk);trap_enter=1;
        @(posedge clk);#1;
        @(negedge clk);trap_enter=0;mem_valid=0;

        $display("cpu_mem contract unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(!fail_count)$display("ALL TESTS PASSED");else $display("TEST FAILED");
        $finish;
    end

    initial begin repeat(3000)@(posedge clk);$display("TEST FAILED: timeout");$finish;end
endmodule
