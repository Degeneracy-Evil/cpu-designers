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
    
	//信号打包
    wire        w_writeEnable_1;  // 写寄存器标志
    wire [ 4:0] w_waddr_5;        // 写寄存器地址  
    wire [31:0] w_wdata_32;       // 写寄存器数据 
	
    wire [ 4:0] w_raddr1_5;       // 读寄存器1地址
    wire [ 4:0] w_raddr2_5;       // 读寄存器2地址
    reg  [31:0] r_rdata1_32;      // 读寄存器1数据
    reg  [31:0] r_rdata2_32;      // 读寄存器2数据
    
    wire [ 4:0] w_raddr3_5;       // 读寄存器3地址
    wire [ 4:0] w_raddr4_5;       // 读寄存器4地址
    reg  [31:0] r_rdata3_32;      // 读寄存器3数据
    reg  [31:0] r_rdata4_32;      // 读寄存器4数据

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
    // 写寄存器
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

    // 读寄存器1
    always @ (*) begin
        if ( !(|w_raddr1_5)) begin                 
            r_rdata1_32 = 32'b0;
        end else begin
            r_rdata1_32 = regs[w_raddr1_5];
        end
    end

    // 读寄存器2
    always @ (*) begin
        if (!(|w_raddr2_5)) begin
            r_rdata2_32 = 32'b0;
        end else begin
            r_rdata2_32 = regs[w_raddr2_5];
        end
    end
    
    // 读寄存器3
    always @ (*) begin
        if (!(|w_raddr3_5)) begin
            r_rdata3_32 = 32'b0;
        end else begin
            r_rdata3_32 = regs[w_raddr3_5];
        end
    end

    // 读寄存器4
    always @ (*) begin
        if (!(|w_raddr4_5)) begin
            r_rdata4_32 = 32'b0;
        end else begin
            r_rdata4_32 = regs[w_raddr4_5];
        end
    end
endmodule
