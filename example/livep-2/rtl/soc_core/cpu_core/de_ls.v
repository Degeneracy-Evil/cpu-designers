//-----------------------------------------------
//    module name: de_ls
//    author: 
//  
//    version: 1st version (2023-7-17)
//    description: \u017eÃÄ£¿éÎª¶þÈý\u0152¶Á÷Ë®ÏßÖ®\u0152äµÄ\u0152¶\u0152ä\u0152Ä\u017dæÆ÷Ä£¿?//                 
//
//
//-----------------------------------------------
`timescale 1ns / 1ps

module de_ls(
    input  wire         rstn,            
    input  wire         clk,      
	input  wire 		i_holdflag_1,
	input  wire 		i_flushflag_1,                
    input  wire [ 63:0] i_instAndPc_64,
	output wire [ 63:0] o_instAndPc_64,
	input  wire [138:0] i_deToLs_139,
	output  wire [138:0] o_deToLs_139
);
     
    localparam nop64 = 64'b0;
	localparam nop139 = 139'b0;
    reg  [ 63:0] r_instAndPc_64 ;
	reg  [138:0] r_deToLs_139;

always @ (posedge clk or negedge rstn) begin
	if(!rstn) begin
		  r_instAndPc_64 <= nop64;
		  r_deToLs_139 <= nop139;
	   end 
	else begin
        if(i_flushflag_1) begin
            r_instAndPc_64 <= nop64;
			r_deToLs_139 <= nop139;
        end 
        else begin
            if(i_holdflag_1) begin
                r_instAndPc_64 <= r_instAndPc_64;
				r_deToLs_139 <= r_deToLs_139;
            end
            else begin
                r_instAndPc_64 <= i_instAndPc_64;
				r_deToLs_139 <= i_deToLs_139;
            end
        end
    end
end

    assign o_instAndPc_64 = r_instAndPc_64;
	assign o_deToLs_139 = r_deToLs_139;
	
endmodule
