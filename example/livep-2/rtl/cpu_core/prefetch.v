`timescale 1ns / 1ps
`include "riscv.h"
module m_prefetch(
	input  wire        clk,     
	input  wire        rstn,    
	
    input  wire [31:0] i_inst_32,           
   
	
	input  wire        i_holdFlag_1,
	input  wire        i_isBranch_1, 
	input  wire       i_isIntPc_1,    
    input  wire [31:0] i_intPc_32,     
    input  wire [31:0] i_branchPc_32,  
   

   
    output  wire [31:0] o_outputPc_32,
    output  wire [31:0] o_outputInst_32,

    output wire [31:0] o_fetchAddr_32, 
    output wire    o_instrAcceFaultFirst_1
    );
	
	localparam RESET           = 3'd0; 
	localparam IDLE            = 3'd1; 
	localparam Normal          = 3'd2; 

		
	reg         r_lastInt_1;
	reg  [ 2:0] r_state;
    reg  [ 2:0] r_nextState;
	
	reg  [31:0] r_nextPc_32;
	reg  [31:0] r_inst_32;
	reg  [31:0] r_presentPc_32;
	reg  [31:0] r_lastPc_32;
	reg  [31:0] r_lastPc_t_32;
	wire [31:0] w_nextpcAdd4_32  = r_nextPc_32 + 32'h4;
	reg         r_intFlagt_32;
	reg  [31:0] r_intPct_32;
	

	wire       w_intFlag_1 = (i_isIntPc_1 ) | (r_intFlagt_32 & (i_holdFlag_1 | i_isBranch_1));
	wire [31:0] w_intPc_32 =i_isIntPc_1 ? i_intPc_32 : (r_intFlagt_32 & (i_holdFlag_1 | i_isBranch_1)) ? r_intPct_32 :32'b0;
	

	wire 		w_clear_1        = i_isBranch_1 |w_intFlag_1 | i_holdFlag_1; 



    wire 		w_addrMisa_1     = |r_nextPc_32[1:0];
	assign      o_fetchAddr_32   = r_nextPc_32;

	assign      o_InstrAcceFaultFirst_1    = (o_fetchAddr_32[31:0] > `ROM_MAX_ADDR | (o_fetchAddr_32[0]| o_fetchAddr_32[1])) ? 1'b1 : 1'b0;


    assign      o_outputPc_32   = r_state!= IDLE ?r_presentPc_32:r_lastPc_32;
	assign       o_outputInst_32   = i_holdFlag_1? `nop: r_inst_32;	
	
	
	

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin 
			r_state          <= RESET;
		
			r_nextPc_32      <= `RESETADDR;
			r_lastPc_32      <= `RESETADDR;
			r_lastPc_t_32    <= `RESETADDR;
            r_lastInt_1      <= 1'b0;
            r_intFlagt_32     <= 1'b0;
            r_intPct_32      <= `RESETADDR;
        end else begin
			r_state          <= r_nextState;
		    r_lastPc_32      <= i_holdFlag_1 ? r_lastPc_32      : r_nextPc_32;
		    r_lastPc_t_32    <= r_presentPc_32;
            r_lastInt_1      <=w_intFlag_1;
            r_intFlagt_32     <=w_intFlag_1;
            r_intPct_32      <=w_intFlag_1 ?  w_intPc_32 : `RESETADDR;
            

			if(w_clear_1) begin
				r_nextPc_32  <=w_intFlag_1  ? w_intPc_32 : (i_isBranch_1 ? i_branchPc_32 : r_presentPc_32);
			end 
			else begin
				case (r_state)
					RESET    : begin 
                        r_nextPc_32 <= w_nextpcAdd4_32; 
                    end
                                                                                            
                    IDLE     : begin r_nextPc_32 <= i_holdFlag_1 ?r_nextPc_32: w_nextpcAdd4_32;
                    end
                    Normal   : begin  r_nextPc_32 <= w_nextpcAdd4_32; 
                    end     
					default  : begin r_nextPc_32 <= r_nextPc_32; end
				endcase
			end	
        end
    end
	
	always @(*) begin
		case (r_state)
		    RESET :     begin 
					    	  r_inst_32      = `nop;
					    	  r_presentPc_32 = r_lastPc_32;
					    	  r_nextState   = Normal;						
					    end 
		    IDLE  :     begin 
					    	  r_inst_32      = `nop;
					    	  r_presentPc_32 = r_lastPc_t_32;
					    	  r_nextState   = i_holdFlag_1 ? IDLE:Normal;
					    end
		    Normal:     begin 
					    	  	begin 
                                r_inst_32 = i_inst_32;    
                                r_presentPc_32 = r_lastPc_32; 
                                end 
					    	  case(w_clear_1 &~r_lastInt_1)
					    	  	    1'b1: begin  r_nextState = IDLE;      end
					    	  	    1'b0: begin  r_nextState = Normal;    end 
					    	  	    
					    	  endcase
					    end 

			default:    begin r_inst_32      = `nop;
						      r_presentPc_32 = r_lastPc_32;
						      r_nextState   = RESET;
					    end		
		endcase
	end

endmodule

