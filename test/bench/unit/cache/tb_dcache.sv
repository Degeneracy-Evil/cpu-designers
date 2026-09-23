`timescale 1ns/1ps
`include "common/bus/axi.svh"
module tb_dcache;
    reg clk=0,resetn=0;always #5 clk=~clk;
    reg cpu_req_valid,cpu_req_write;reg [31:0] cpu_req_paddr,cpu_req_wdata;reg [2:0] cpu_req_size;
    wire [31:0] cpu_req_rdata,cpu_req_error_addr;wire cpu_req_ready,cpu_req_error,cpu_req_error_is_store;
    reg ptw_req_valid,ptw_req_write;reg [31:0] ptw_req_addr,ptw_req_wdata;
    wire [31:0] ptw_req_rdata;wire ptw_req_done,ptw_req_error;
    wire mem_req_valid,mem_req_write;reg mem_req_ready;wire [31:0] mem_req_addr,mem_req_wdata;
    wire [2:0] mem_req_size;wire [7:0] mem_req_len;wire [3:0] mem_req_wstrb;
    reg mem_resp_valid,mem_resp_error;reg [255:0] mem_resp_data;
    dcache_ctrl dut(.*);
    reg [31:0] memory[0:1023];integer pass_count=0,fail_count=0,line_count=0,single_count=0;
    integer i,delay;reg busy,fail_next;reg [31:0] addr_r,wdata_r;reg [3:0] wstrb_r;reg write_r;reg [2:0] size_r;reg [7:0] len_r;
    task write_memory(input [31:0] addr,input [31:0] data,input [3:0] strb);reg [31:0] old;integer b;begin
        old=memory[addr[11:2]];
        for(b=0;b<4;b=b+1)if(strb[b])old[b*8+:8]=data[b*8+:8];
        memory[addr[11:2]]=old;
    end endtask
    always @(posedge clk or negedge resetn)begin
        if(!resetn)begin busy<=0;delay<=0;mem_resp_valid<=0;mem_resp_error<=0;mem_resp_data<=0;end
        else begin
            mem_resp_valid<=0;mem_resp_error<=0;
            if(mem_req_valid&&mem_req_ready&&!busy)begin
                busy<=1;addr_r<=mem_req_addr;wdata_r<=mem_req_wdata;wstrb_r<=mem_req_wstrb;write_r<=mem_req_write;
                size_r<=mem_req_size;len_r<=mem_req_len;delay<=3;
                if(mem_req_len==7)line_count<=line_count+1;else single_count<=single_count+1;
            end else if(busy)begin
                if(delay!=0)delay<=delay-1;
                else begin
                    if(write_r&&!fail_next)write_memory(addr_r,wdata_r,wstrb_r);
                    for(i=0;i<8;i=i+1)mem_resp_data[i*32+:32]<=memory[(addr_r[11:2]+i)&10'h3ff];
                    mem_resp_valid<=1;mem_resp_error<=fail_next;busy<=0;
                end
            end
        end
    end
    task check(input condition,input [8*72-1:0] name);begin
        if(condition)begin pass_count=pass_count+1;$display("  PASS %0s",name);end
        else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
    end endtask
    task cpu_access(input [31:0] addr,input wr,input [2:0] size,input [31:0] wd,output [31:0] rd);begin
        @(negedge clk);cpu_req_paddr=addr;cpu_req_write=wr;cpu_req_size=size;cpu_req_wdata=wd;cpu_req_valid=1;
        while(!cpu_req_ready)begin @(posedge clk);#1;end rd=cpu_req_rdata;
        @(negedge clk);cpu_req_valid=0;cpu_req_write=0;repeat(2)@(posedge clk);
    end endtask
    task ptw_access(input [31:0] addr,input wr,input [31:0] wd,output [31:0] rd);begin
        @(negedge clk);ptw_req_addr=addr;ptw_req_write=wr;ptw_req_wdata=wd;ptw_req_valid=1;
        while(!ptw_req_done)begin @(posedge clk);#1;end rd=ptw_req_rdata;
        check(!ptw_req_error,"PTW access completes without error");
        @(negedge clk);ptw_req_valid=0;ptw_req_write=0;repeat(2)@(posedge clk);
    end endtask
    localparam [31:0] A=32'h80001000,B=32'h80001100,C=32'h80001200;
    localparam [31:0] D=32'h80001303,E=32'h80001400;
    reg [31:0] got;integer count_before;
    initial begin
        cpu_req_valid=0;cpu_req_paddr=0;cpu_req_wdata=0;cpu_req_write=0;cpu_req_size=`AXI_SIZE_WORD;
        ptw_req_valid=0;ptw_req_addr=0;ptw_req_wdata=0;ptw_req_write=0;mem_req_ready=1;fail_next=0;
        for(i=0;i<1024;i=i+1)memory[i]=32'h60000000+i;
        repeat(5)@(posedge clk);resetn=1;repeat(2)@(posedge clk);
        cpu_access(A,1,`AXI_SIZE_WORD,32'hdeadbeef,got);
        check(memory[A[11:2]]==32'hdeadbeef&&!dut.valid_array[0][0],"store miss writes through without allocation");
        cpu_access(A,0,`AXI_SIZE_WORD,0,got);check(got==32'hdeadbeef&&line_count==1,"load miss allocates one line");
        cpu_access(B,0,`AXI_SIZE_WORD,0,got);check(dut.valid_array[0][0]&&dut.valid_array[0][1],"two ways hold two physical tags");
        count_before=line_count;cpu_access(A,0,`AXI_SIZE_WORD,0,got);check(line_count==count_before,"load hit avoids memory request");
        cpu_access(C,0,`AXI_SIZE_WORD,0,got);check(line_count==count_before+1,"third same-set load replaces one way");

        cpu_access(A,1,`AXI_SIZE_WORD,32'h12345678,got);
        ptw_access(A,0,0,got);check(got==32'h12345678,"PTW observes latest CPU store to cached PTE");
        cpu_access(A,1,`AXI_SIZE_HWORD,32'h0000a55a,got);
        cpu_access(A,0,`AXI_SIZE_WORD,0,got);
        check(got[15:0]==16'ha55a&&memory[A[11:2]][15:0]==16'ha55a,"halfword store hit updates memory and cached bytes");
        ptw_access(A,0,0,got);check(got[15:0]==16'ha55a,"PTW shares coherent DCache contents");

        count_before=line_count;cpu_access(D,1,`AXI_SIZE_BYTE,32'h5a,got);
        check(memory[D[11:2]][31:24]==8'h5a&&line_count==count_before,"byte store miss is write-through and no-allocate");
        ptw_access(E,0,0,got);check(line_count==count_before+1,"PTW load miss refills through DCache");
        ptw_access(E,1,32'h600005f8,got);cpu_access(E,0,`AXI_SIZE_WORD,0,got);
        check(got==32'h600005f8&&memory[E[11:2]]==32'h600005f8,"PTW A/D write updates memory and cached PTE");

        count_before=single_count;cpu_access(32'h88000000,0,`AXI_SIZE_WORD,0,got);
        check(single_count==count_before+1&&line_count==4,"DDR upper limit is uncached");

        fail_next=1;@(negedge clk);ptw_req_addr=32'h10000000;ptw_req_valid=1;
        while(!ptw_req_done)begin @(posedge clk);#1;end
        check(ptw_req_error,"memory error returns to PTW owner");
        @(negedge clk);ptw_req_valid=0;repeat(2)@(posedge clk);fail_next=0;

        count_before=single_count;
        fail_next=1;@(negedge clk);cpu_req_paddr=32'h10000004;cpu_req_write=1;
        cpu_req_size=`AXI_SIZE_WORD;cpu_req_wdata=32'h1234;cpu_req_valid=1;
        while(!cpu_req_error)begin @(posedge clk);#1;end
        check(cpu_req_error_is_store&&cpu_req_error_addr==32'h10000004&&!cpu_req_ready,"store error preserves owner, type, and address");
        repeat(5)begin @(posedge clk);#1;end
        check(single_count==count_before+1,"held CPU request is blocked after memory error");
        @(negedge clk);cpu_req_valid=0;cpu_req_write=0;fail_next=0;
        repeat(2)@(posedge clk);
        cpu_access(32'h10000008,0,`AXI_SIZE_WORD,0,got);
        check(single_count==count_before+2,"dropping CPU valid releases the error block");
        $display("dcache write-through unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(!fail_count)$display("ALL TESTS PASSED");else $fatal(1, "TEST FAILED");$finish;
    end
    initial begin repeat(5000)@(posedge clk);$fatal(1, "TEST FAILED: timeout");end
endmodule
