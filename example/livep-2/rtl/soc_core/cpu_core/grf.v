//-----------------------------------------------
//    module name: grf
//    author: 
//  
//    version: 1st version (2023-7-18)
//    description: 
//             Í¨ÓÃ¼Ä´æÆ÷Ä£¿é    
//
//
//-----------------------------------------------
`timescale 1ns / 1ps

module grf(
    input wire         clk,
    input wire         rstn,
	input  wire [ 9:0] i_ifToGrf_10,
    output wire [63:0] o_grfToIf_64,                    
    input  wire [ 9:0] i_deToGrf_10,
    output wire [63:0] o_grfTode_64,
	input  wire [37:0] i_lsuToGrf_38
    );
	//ÐÅºÅ´ò°ü
    wire        w_writeEnable_1;  // Ð´¼Ä´æÆ÷±êÖ¾
    wire [ 4:0] w_waddr_5;        // Ð´¼Ä´æÆ÷µØÖ·  
    wire [31:0] w_wdata_32;       // Ð´¼Ä´æÆ÷Êý¾Ý 
    wire [ 4:0] w_raddr1_5;       // ¶Á¼Ä´æÆ÷1µØÖ·
    wire [ 4:0] w_raddr2_5;       // ¶Á¼Ä´æÆ÷2µØÖ·
    reg  [31:0] r_rdata1_32;      // ¶Á¼Ä´æÆ÷1Êý¾Ý
    reg  [31:0] r_rdata2_32;      // ¶Á¼Ä´æÆ÷2Êý¾Ý
    wire [ 4:0] w_raddr3_5;       // ¶Á¼Ä´æÆ÷3µØÖ·
    wire [ 4:0] w_raddr4_5;       // ¶Á¼Ä´æÆ÷4µØÖ·
    reg  [31:0] r_rdata3_32;      // ¶Á¼Ä´æÆ÷3Êý¾Ý
    reg  [31:0] r_rdata4_32;      // ¶Á¼Ä´æÆ÷4Êý¾Ý

    assign {w_raddr1_5,w_raddr2_5} = i_ifToGrf_10; 
    assign o_grfToIf_64             = {r_rdata1_32,r_rdata2_32};
    assign {w_raddr3_5,w_raddr4_5} = i_deToGrf_10;    
    assign o_grfTode_64             = {r_rdata3_32,r_rdata4_32};			
	assign {
			w_writeEnable_1,
			w_waddr_5,
			w_wdata_32
			} = i_lsuToGrf_38;

    reg[31:0] regs [0:31];
    integer i;                                     
    // Ð´¼Ä´æÆ÷
    always @ (posedge clk or negedge rstn) begin
        if (!rstn) begin
          for(i=0;i<32;i=i+1)                       
             regs[i] <= 32'b0;
        end
        else begin 
          if (w_writeEnable_1 & |w_waddr_5) begin
                regs[w_waddr_5] <= w_wdata_32;
          end 
        end
    end

    // ¶Á¼Ä´æÆ÷1
    always @ (*) begin
        if ( !(|w_raddr1_5)) begin                 
            r_rdata1_32 = 32'b0;
        end 
        else begin
            r_rdata1_32 = regs[w_raddr1_5];
        end
    end

    // ¶Á¼Ä´æÆ÷2
    always @ (*) begin
        if (!(|w_raddr2_5)) begin
            r_rdata2_32 = 32'b0;
        end 
        else begin
            r_rdata2_32 = regs[w_raddr2_5];
        end
    end
    
    // ¶Á¼Ä´æÆ÷3
    always @ (*) begin
        if (!(|w_raddr3_5)) begin
            r_rdata3_32 = 32'b0;
        end 
        else begin
            r_rdata3_32 = regs[w_raddr3_5];
        end
    end

    // ¶Á¼Ä´æÆ÷4
    always @ (*) begin
        if (!(|w_raddr4_5)) begin
            r_rdata4_32 = 32'b0;
        end 
        else begin
            r_rdata4_32 = regs[w_raddr4_5];
        end
    end
endmodule
