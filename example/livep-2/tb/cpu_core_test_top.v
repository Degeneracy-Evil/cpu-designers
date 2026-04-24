`timescale 1ns / 1ps
`include "header_file_path"
module cpu_core_test1;

    parameter BPS_115200 = 8680 ; 
    parameter ClockPeriod = (1000/`FREQ);

    reg clk,rstn;

    always #(ClockPeriod/2) clk =~clk ;
    
    cpu_core_top uut(
        .clk (clk),
        .rstn(rstn),
        .i_intFlag_1(1'b0)
    );

    wire[31:0] x3 =  uut.cpu_top.grf.regs[927:896]; 
    wire[31:0] x26 = uut.cpu_top.grf.regs[191:160];
    wire[31:0] x27 = uut.cpu_top.grf.regs[159:128];
	
    reg [31:0] mem_inst [8191:0];
    reg [31:0] mem_data [8191:0];

    integer i,roms;
    reg flag;
	string str;
    string loc = "test_file_path";

initial begin $sdf_annotate("sdf_file_path",uut); end 
initial
    begin
	clk=1'b0;
	roms = $fopen("insts_file_path","r");
        while(!$feof(roms))begin
			$fgets(str,roms);
			str = str.substr(0, str.len()-3);
			
            for(i=0;i<8192;i=i+1)begin
				mem_inst[i] = 0;
				mem_data[i] = 0;
			end

	        $readmemh($sformatf("%s%s%s",loc,str,".inst.txt"),mem_inst);
            $readmemh($sformatf("%s%s%s",loc,str,".data.txt"),mem_data);
			for(i = 0;i < 8192;i=i+1)begin
				uut.socmem.icache.Memory_byte3[i] = mem_inst[i][31:24];
				uut.socmem.icache.Memory_byte2[i] = mem_inst[i][23:16];
				uut.socmem.icache.Memory_byte1[i] = mem_inst[i][15:8];
				uut.socmem.icache.Memory_byte0[i] = mem_inst[i][7:0];
				
				uut.socmem.dcache.Memory_byte3[i] = mem_data[i][31:24];
				uut.socmem.dcache.Memory_byte2[i] = mem_data[i][23:16];
				uut.socmem.dcache.Memory_byte1[i] = mem_data[i][15:8];
				uut.socmem.dcache.Memory_byte0[i] = mem_data[i][7:0];
			end
			
			rstn = 1'b1;
			#23333
            rstn=1'b0;
            #23333
            rstn=1'b1;
            wait(x26 == 32'b1)   // wait x26 == 1
            #100
            $display("==================================");
            $display("%7dns: %s",$time(),str);
            if (x27 == 32'b1) begin
                $display("PASS!!");
            end else begin
                $display("FAIL!!");
                $display("fail testnum = %2d", x3);
            end
		end
	$finish;
    end

endmodule