`timescale 1ns/1ps
`include "axi4_def.svh"
module tb_cpu_bus_bridge_unit;
    reg clk=0,resetn=0; always #5 clk=~clk;
    reg i_req_valid,i_req_write; wire i_req_ready,i_resp_valid,i_resp_error;
    reg [31:0] i_req_addr,i_req_wdata; reg [2:0] i_req_size; reg [7:0] i_req_len;
    wire [255:0] i_resp_data;
    reg d_req_valid,d_req_write; wire d_req_ready,d_resp_valid,d_resp_error;
    reg [31:0] d_req_addr,d_req_wdata; reg [2:0] d_req_size; reg [7:0] d_req_len;
    wire [255:0] d_resp_data;
    wire [3:0] awid,awcache,awqos,awregion,wstrb,arid,arcache,arqos,arregion;
    wire [31:0] awaddr,wdata,araddr; wire [7:0] awlen,arlen;
    wire [2:0] awsize,awprot,arsize,arprot; wire [1:0] awburst,arburst;
    wire awlock,awvalid,wlast,wvalid,bready,arlock,arvalid,rready;
    reg awready,wready,bvalid,arready,rvalid,rlast; reg [1:0] bresp,rresp; reg [31:0] rdata;
    cpu_bus_bridge dut(.*);
    integer pass_count=0,fail_count=0,i;
    task check(input condition,input [8*72-1:0] name); begin
        if(condition) begin pass_count=pass_count+1;$display("  PASS %0s",name);end
        else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
    end endtask
    task send_read(input owner_d,input [31:0] base,input [7:0] len,input error);
        begin
            while(!arvalid) @(posedge clk); #1;
            check(araddr==base&&arlen==len,"AXI read metadata is latched");
            arready=1; @(posedge clk); #1; arready=0;
            for(i=0;i<=len;i=i+1) begin
                repeat(2) @(posedge clk); @(negedge clk);
                rdata=base+(i*4); rresp=(error&&i==len)?`AXI_RESP_SLVERR:`AXI_RESP_OKAY;
                rlast=(i==len); rvalid=1;
                @(posedge clk); #1;
                @(negedge clk); rvalid=0; rlast=0;
            end
            #1;
            check(owner_d?d_resp_valid:i_resp_valid,"response returns only to locked owner");
            check((owner_d?d_resp_error:i_resp_error)==error,"read error status is returned with response");
        end
    endtask
    initial begin
        i_req_valid=0;i_req_addr=0;i_req_write=0;i_req_size=`AXI_SIZE_WORD;i_req_len=0;i_req_wdata=0;
        d_req_valid=0;d_req_addr=0;d_req_write=0;d_req_size=`AXI_SIZE_WORD;d_req_len=0;d_req_wdata=0;
        awready=0;wready=0;bvalid=0;bresp=`AXI_RESP_OKAY;arready=0;rvalid=0;rdata=0;rresp=0;rlast=0;
        repeat(4) @(posedge clk); resetn=1; repeat(2) @(posedge clk);

        // Simultaneous requests: D wins and I remains pending.
        @(negedge clk); d_req_valid=1;d_req_addr=32'h80002000;d_req_len=0;
        i_req_valid=1;i_req_addr=32'h80001000;i_req_len=7;
        #1; check(d_req_ready&&!i_req_ready,"DCache has fixed arbitration priority");
        @(posedge clk); #1; d_req_valid=0;
        send_read(1,32'h80002000,0,0);
        check(!i_resp_valid,"D response never leaks to ICache");

        while(!i_req_ready) @(posedge clk); @(posedge clk); #1; i_req_valid=0;
        send_read(0,32'h80001000,7,0);
        check(i_resp_data[255:224]==32'h8000101c,"eight-beat line is assembled in order");

        @(negedge clk);d_req_valid=1;d_req_addr=32'h80003000;d_req_len=7;
        while(!d_req_ready)@(posedge clk);@(posedge clk);#1;d_req_valid=0;
        send_read(1,32'h80003000,7,1);

        // Narrow write with independent AW/W handshakes.
        @(negedge clk); d_req_valid=1;d_req_addr=32'h10000003;d_req_write=1;
        d_req_size=`AXI_SIZE_BYTE;d_req_wdata=32'hc7;
        while(!d_req_ready) @(posedge clk); @(posedge clk); #1; d_req_valid=0;
        while(!awvalid||!wvalid) @(posedge clk); #1;
        check(wstrb==4'b1000&&wdata==32'hc7000000,"byte write data and strobe are aligned");
        awready=1; @(posedge clk); #1; awready=0;
        repeat(2) @(posedge clk); wready=1; @(posedge clk); #1; wready=0;
        while(!bready) @(posedge clk); bresp=`AXI_RESP_DECERR;bvalid=1;
        @(posedge clk); #1; bvalid=0;
        check(d_resp_valid&&d_resp_error,"write response error returns to DCache");
        repeat(3) @(posedge clk); #1;
        check(!i_resp_valid&&!d_resp_valid,"responses are one-cycle pulses");
        $display("cpu_bus_bridge unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(!fail_count)$display("ALL TESTS PASSED");else $display("TEST FAILED");
        $finish;
    end
    initial begin repeat(3000) @(posedge clk);$display("TEST FAILED: timeout");$finish;end
endmodule
