`timescale 1ns/1ps
module tb_icache_blocking_unit;
    reg clk=0,resetn=0; always #5 clk=~clk;
    reg cpu_req_valid,flush_req,invalidate_req; reg [31:0] cpu_req_paddr;
    wire [31:0] cpu_req_data,cpu_req_error_addr; wire cpu_req_ready,cpu_req_error,invalidate_done;
    wire mem_req_valid,mem_req_write; reg mem_req_ready;
    wire [31:0] mem_req_addr,mem_req_wdata; wire [2:0] mem_req_size; wire [7:0] mem_req_len;
    reg mem_resp_valid,mem_resp_error; reg [255:0] mem_resp_data; wire [2:0] dbg_state;
    icache_ctrl dut(.*);
    integer pass_count=0,fail_count=0,line_count=0,single_count=0,i,delay;
    reg busy,fail_next; reg [31:0] addr_r; reg [7:0] len_r;
    function [31:0] value(input [31:0] base,input integer beat);
        value=(base+(beat*4))^32'h13579bdf;
    endfunction
    always @(posedge clk or negedge resetn) begin
        if(!resetn) begin busy<=0;delay<=0;mem_resp_valid<=0;mem_resp_error<=0;mem_resp_data<=0;end
        else begin
            mem_resp_valid<=0;mem_resp_error<=0;
            if(mem_req_valid&&mem_req_ready&&!busy) begin
                busy<=1;addr_r<=mem_req_addr;len_r<=mem_req_len;delay<=4;
                if(mem_req_len==7) line_count<=line_count+1;else single_count<=single_count+1;
            end else if(busy) begin
                if(delay!=0) delay<=delay-1;
                else begin
                    for(i=0;i<8;i=i+1) mem_resp_data[i*32+:32]<=value(addr_r,i);
                    mem_resp_error<=fail_next;mem_resp_valid<=1;busy<=0;
                end
            end
        end
    end
    task check(input condition,input [8*72-1:0] name);begin
        if(condition)begin pass_count=pass_count+1;$display("  PASS %0s",name);end
        else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
    end endtask
    task fetch(input [31:0] addr,output [31:0] data);begin
        @(negedge clk);cpu_req_paddr=addr;cpu_req_valid=1;
        while(!cpu_req_ready&&!cpu_req_error)begin @(posedge clk);#1;end
        data=cpu_req_data;@(negedge clk);cpu_req_valid=0;repeat(2)@(posedge clk);
    end endtask
    localparam [31:0] A=32'h80001004,B=32'h80001108,C=32'h8000120c;
    reg [31:0] got; integer count_before;
    initial begin
        cpu_req_valid=0;cpu_req_paddr=0;flush_req=0;invalidate_req=0;
        mem_req_ready=1;fail_next=0;
        repeat(5)@(posedge clk);resetn=1;repeat(2)@(posedge clk);
        fetch(A,got);check(got==value({A[31:5],5'b0},A[4:2])&&line_count==1,"cacheable miss refills a line");
        count_before=line_count;fetch(A,got);check(line_count==count_before,"second access hits without memory request");
        fetch(B,got);check(dut.valid_array[0][0]&&dut.valid_array[0][1],"two physical tags fill both ways");
        fetch(C,got);check(line_count==count_before+2,"third same-set tag replaces one way");

        count_before=single_count;fetch(32'h7ffffffc,got);
        check(single_count==count_before+1&&got==value(32'h7ffffffc,0),"address below DDR is uncached single read");
        count_before=single_count;fetch(32'h88000000,got);
        check(single_count==count_before+1&&got==value(32'h88000000,0),"address at DDR limit is uncached single read");

        @(negedge clk);invalidate_req=1;@(posedge clk);#1;
        check(invalidate_done&& !dut.valid_array[0][0]&&!dut.valid_array[0][1],"invalidate clears all valid bits in one cycle");
        @(negedge clk);invalidate_req=0;

        // Accepted refill is drained after a redirect and cannot answer the new address.
        @(negedge clk);cpu_req_paddr=32'h80001310;cpu_req_valid=1;
        while(!busy)@(posedge clk);@(negedge clk);flush_req=1;cpu_req_paddr=32'h80001414;
        @(negedge clk);flush_req=0;
        while(!cpu_req_ready)begin @(posedge clk);#1;end
        got=cpu_req_data;@(negedge clk);cpu_req_valid=0;
        check(got==value(32'h80001400,5),"flush drains stale refill and returns only new request");

        fail_next=1;@(negedge clk);cpu_req_paddr=32'h8000161c;cpu_req_valid=1;
        while(!cpu_req_error)begin @(posedge clk);#1;end
        check(cpu_req_error_addr==32'h8000161c&&!cpu_req_ready,"refill error reports latched physical address");
        @(negedge clk);cpu_req_valid=0;fail_next=0;
        $display("icache blocking unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(!fail_count)$display("ALL TESTS PASSED");else $display("TEST FAILED");$finish;
    end
    initial begin repeat(5000)@(posedge clk);$display("TEST FAILED: timeout");$finish;end
endmodule
