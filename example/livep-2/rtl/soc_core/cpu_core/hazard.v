//-----------------------------------------------
//    module name: hazard
//    author: 
//  
//    version: 1st version (2023-7-17)
//    description: hazard 模块实现数据前递以及流水线停顿，解决冒险问题。
//        
//
//-----------------------------------------------
`timescale 1ns / 1ps

module hazard(
	input  wire [11:0] i_ifToHazard_12,	    //提前分支两个寄存器地址+grf读使能
	input  wire [18:0] i_exToHazard_19, 	//执行阶段两个寄存器地址+grf读使能+目标地址+grf写使能+load信号
	input  wire [ 5:0] i_lsToHazard_6,		//回写阶段目标寄存器地址+grf写使能
	input  wire        rst,
	output reg  [3:0]  o_forward_first_4,
	output reg  [1:0]  o_forward_second_2
);
	//信号打包
    wire [ 4:0] if_addrr1_5; 
	wire [ 4:0] if_addrr2_5; 
    wire [ 1:0] if_read_2; 
    wire [ 4:0] ex_addrr1_5; 
	wire [ 4:0] ex_addrr2_5; 
    wire [ 4:0] ex_addrrd_5; 
    wire [ 1:0] ex_read_2; 
    wire 		ex_write_1; 
    wire        ex_load_type_1;
	wire [ 4:0] ls_addrrd_5; 
    wire 		ls_write_1; 
	
    assign  {
                            if_addrr1_5,
                            if_addrr2_5,
							if_read_2
                            }=i_ifToHazard_12;
    assign   {
							ex_addrr1_5,
							ex_addrr2_5,
							ex_read_2,
							ex_addrrd_5,
							ex_write_1,
							ex_load_type_1
							}=i_exToHazard_19;
	assign {
							ls_addrrd_5,
							ls_write_1
							}=i_lsToHazard_6;

	//数据前递部分  
	//提前分支
    always@(*)begin
	if(rst)
	        o_forward_first_4[3:2]  <= 2'b00;
        else if( ~ex_load_type_1 && if_read_2[1] && ex_write_1 && if_addrr1_5==ex_addrrd_5 && ex_addrrd_5 )
            o_forward_first_4[3:2] <= 2'b01;
        else if( if_read_2[1] && ls_write_1 && if_addrr1_5==ls_addrrd_5 && ls_addrrd_5 )
            o_forward_first_4[3:2] <= 2'b10;
        else
            o_forward_first_4[3:2] <= 2'b00;
    end
	
	always@(*)begin
	if(rst)
	        o_forward_first_4[1:0]  <= 2'b00;
        else if(~ex_load_type_1 &&  if_read_2[0] && ex_write_1 && if_addrr2_5==ex_addrrd_5 && ex_addrrd_5 )
            o_forward_first_4[1:0] <= 2'b01;
        else if( if_read_2[0] && ls_write_1 && if_addrr2_5==ls_addrrd_5 && ls_addrrd_5 )
            o_forward_first_4[1:0] <= 2'b10;
        else
            o_forward_first_4[1:0] <= 2'b00;
    end
	//译码执行
	always@(*)begin
	if(rst)
	        o_forward_second_2[1]  <= 1'b0;
        else if( ex_read_2[1] && ls_write_1 && ex_addrr1_5==ls_addrrd_5 && ls_addrrd_5 )
            o_forward_second_2[1] <= 1'b1;
        else 
            o_forward_second_2[1] <= 1'b0;
    end
	
	always@(*)begin
	if(rst)
	        o_forward_second_2[0]  <= 1'b0;
        else if( ex_read_2[0] && ls_write_1 && ex_addrr2_5==ls_addrrd_5 && ls_addrrd_5 )
            o_forward_second_2[0] <= 1'b1;
        else 
            o_forward_second_2[0] <= 1'b0;
    end

endmodule
