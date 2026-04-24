`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/17 13:26:25
// Design Name: 
// Module Name: CSR
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module CSR(
    input wire clk,
    input wire rstn,
	input wire [44:0] i_exe_45,
	output wire [31:0] o_ReadData_32,
    output reg [95:0] o_CsrToClint_96,
    //mtvec:95-64  mepc:63-32 mstatus: 31-0
    input wire [128:0] i_ClintToCsr_129
    );
	wire w_CsrWirte_1;
	wire [11:0] w_Addr_12;
	wire [31:0] w_WriteData_32;
	
	assign {w_CsrWirte_1,w_Addr_12,w_WriteData_32}=i_exe_45;
	
	reg [31:0] Csrs [0:4];	
	//0:mstatus;1:mtval;2:mcause;3:mepc;4:mtvec
	
    integer i;
   
always@(posedge clk or negedge rstn) 
    begin 
        if (!rstn)begin
          Csrs[0]=32'h8;
          Csrs[1]=32'b0;
          Csrs[2]=32'b0;
          Csrs[3]=32'hfffff;
          Csrs[4]=32'hfff;
        end              
        else begin
            if(w_CsrWirte_1)begin
                Csrs[w_Addr_12] = w_WriteData_32; 
            end
	        else if(i_ClintToCsr_129[128])begin
                {Csrs[3],Csrs[2],Csrs[1],Csrs[0]}=i_ClintToCsr_129 [127:0]; 
            end
        end
    end	
    
    always@(*)begin   
        o_CsrToClint_96 = {Csrs[4],Csrs[3],Csrs[0]};
	//0:mstatus;1:mtval;2:mcause;3:mepc;4:mtvec
    end
    
    assign o_ReadData_32 = Csrs[w_Addr_12[2:0]];

endmodule
