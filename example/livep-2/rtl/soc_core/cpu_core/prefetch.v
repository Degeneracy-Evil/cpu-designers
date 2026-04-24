`timescale 1ns / 1ps
`include "riscv.h"
module m_prefetch(
	input  wire        clk,     
	input  wire        rstn,    
    input  wire [31:0] i_inst_32,           
	input  wire        i_holdflag_1,
	input  wire        i_isBranch_1, 
	input  wire        i_isIntPC_1,    
    input  wire [31:0] i_intPC_32,     
    input  wire [31:0] i_branchPC_32,  
    output wire [31:0] o_OutputPC_32,
    output wire [31:0] o_OutputInst_32,
    output wire [31:0] o_fetchaddr_32, 
    output wire        o_InstrAcceFaultFirst_1
    );
	localparam RESET           = 3'd0; 
	localparam IDLE            = 3'd1; 
	localparam Normal          = 3'd2; 
	reg         r_lastint_1;
	reg  [ 2:0] r_state;
    reg  [ 2:0] r_next_state;
	reg  [31:0] r_nextpc_32;
	reg  [31:0] r_inst_32;
	reg  [31:0] r_presentPC_32;
	reg  [31:0] r_lastPC_32;
	reg  [31:0] r_lastPC_t_32;
	wire [31:0] w_nextpcAdd4_32  = r_nextpc_32 + 32'h4;
	reg         r_intflagt_1;
	reg  [31:0] r_intpct_32;
	wire        w_intflag_1 = (i_isIntPC_1 ) | (r_intflagt_1 & (i_holdflag_1 | i_isBranch_1));
	wire [31:0] w_intpc_32 = i_isIntPC_1 ? i_intPC_32 : (r_intflagt_1 & (i_holdflag_1 | i_isBranch_1)) ? r_intpct_32 :32'b0;
	wire 		w_clear_1        = i_isBranch_1 | w_intflag_1 | i_holdflag_1; 
    wire 		w_addrMisa_1     = |r_nextpc_32[1:0];
	
	assign      o_fetchaddr_32   = r_nextpc_32;
	assign      o_InstrAcceFaultFirst_1    = (o_fetchaddr_32[31:0] > `ROM_MAX_ADDR | (o_fetchaddr_32[0]| o_fetchaddr_32[1])) ? 1'b1 : 1'b0;
    assign      o_OutputPC_32   = r_state!= IDLE ?r_presentPC_32:r_lastPC_32;
	assign       o_OutputInst_32   = i_holdflag_1? `nop: r_inst_32;	
	
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin 
			r_state          <= RESET;
			r_nextpc_32      <= `RESETADDR;
			r_lastPC_32      <= `RESETADDR;
			r_lastPC_t_32    <= `RESETADDR;
            r_lastint_1      <= 1'b0;
            r_intflagt_1     <= 1'b0;
            r_intpct_32      <= `RESETADDR;
        end else begin
			r_state          <= r_next_state;
		    r_lastPC_32      <= i_holdflag_1 ? r_lastPC_32      : r_nextpc_32;
		    r_lastPC_t_32    <= r_presentPC_32;
            r_lastint_1      <= w_intflag_1;
            r_intflagt_1     <= w_intflag_1;
            r_intpct_32      <= w_intflag_1 ?  w_intpc_32 : `RESETADDR;
			if(w_clear_1) begin
				r_nextpc_32  <= w_intflag_1  ? w_intpc_32 : (i_isBranch_1 ? i_branchPC_32 : r_presentPC_32);
			end 
			else begin
				case (r_state)
					RESET    : begin 
                        r_nextpc_32 <= w_nextpcAdd4_32; 
                    end
                                                                                            
                    IDLE     : begin r_nextpc_32 <= i_holdflag_1 ?r_nextpc_32: w_nextpcAdd4_32;
                    end
                    Normal   : begin  r_nextpc_32 <= w_nextpcAdd4_32; 
                    end     
					default  : begin r_nextpc_32 <= r_nextpc_32; end
				endcase
			end	
        end
    end
	
	always @(*) begin
		case (r_state)
		    RESET :     begin 
					    	  r_inst_32      = `nop;
					    	  r_presentPC_32 = r_lastPC_32;
					    	  r_next_state   = Normal;						
					    end 
		    IDLE  :     begin 
					    	  r_inst_32      = `nop;
					    	  r_presentPC_32 = r_lastPC_t_32;
					    	  r_next_state   = i_holdflag_1 ? IDLE:Normal;
					    end
		    Normal:     begin 
					    	  	begin 
                                r_inst_32 = i_inst_32;    
                                r_presentPC_32 = r_lastPC_32; 
                                end 
					    	  case(w_clear_1 &~r_lastint_1)
					    	  	    1'b1: begin  r_next_state = IDLE;      end
					    	  	    1'b0: begin  r_next_state = Normal;    end 
					    	  	    
					    	  endcase
					    end 

			default:    begin r_inst_32      = `nop;
						      r_presentPC_32 = r_lastPC_32;
						      r_next_state   = RESET;
					    end		
		endcase
	end
endmodule

