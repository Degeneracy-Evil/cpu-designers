`timescale 1ns / 1ps

module load_store_unit (
    input wire clk,
    input wire rstn,
    input wire [138:0] i_ExeLsuBus_139,

    //the signals to module grf
    //给grf的信号
    output wire [31:0] o_rdData_32,
    output wire [4:0] o_rdNum_5,
    output wire o_rdWen_1,
    //the signals between module dCache
    //给dCache的信号和从dCache中读取的数据
    input wire [31:0] i_memData_32,
    output wire [31:0] o_memAddr_32,
    output wire [31:0] o_memData_32,
    output wire [3:0] o_memWen,
    //the signals to CSR
    //给异常处理模块的信号
    output wire [31:0] o_epc_32,
    output wire [31:0] o_einst_32,
    output wire o_loadAcceFalutThird_1,
    output wire o_storeAcceFalutThird_1,
    
    output wire o_LsuPipeHold_1
);
    //regs related to dCache
    //与dCache有关的信号
    reg [31:0] r_memAddr_32;    //输出的地址
    reg [31:0] r_memData_32;    //输出的数据
    reg [3:0]  r_memWen_4;      //输出的4位使能信号，控制4字节读写，0为写，1为读，不读不写恒置1111

    assign o_memAddr_32 = r_memAddr_32;
    assign o_memWen = r_memWen_4;

    //暂存读出的数据，用于后续拼接
    reg [31:0] r_tempRData; 

    //来自译码模块的139位数据包
    wire w_isLoad_1;                //是否为load指令
    wire w_isStore_1;               //是否为store指令
    wire w_loadSign_1;              //有符号或者无符号load
    wire w_grfWen_1;                //grf使能信号
    wire [31:0] w_exeResult_32;     //来自执行模块的计算结果
    wire [31:0] w_storeData_32;     //需要存储的数据
    wire [1:0]  w_lsuType_2;        //load或者store的类型，0字节，1半字，2全字
    wire [4:0] w_rdNum_5;           //需要写回的寄存器号
  
    assign {
        w_isLoad_1,
        w_isStore_1,
        w_loadSign_1,
        w_grfWen_1,
        w_lsuType_2,
        w_exeResult_32,
        w_storeData_32,
        w_rdNum_5,
        o_epc_32,
        o_einst_32
    } = i_ExeLsuBus_139;

    assign o_rdNum_5 = w_rdNum_5;
    
    //与grf有关的寄存器
    reg r_grfWen_1;     //grf使能
    reg [31:0] r_grfdata_32;    //grf数据
    //与dCache有关的寄存器
    wire [31:0] w_memAddr_32;   //操作的地址
    reg r_endSignal_1;      //操作是否结束
    wire w_misalignTag;     //地址未对其标志
    wire w_lsuEnable_1;     
    reg [1:0] r_err_2;      //错误寄存器，处理地址非法

    //assign o_loadAcceFalutThird_1 = r_err_2[0];
    assign o_loadAcceFalutThird_1 = 1'b0;
    //assign o_storeAcceFalutThird_1 = r_err_2[1];
    assign o_storeAcceFalutThird_1 = 1'b0;
    
    assign o_rdData_32 = r_grfdata_32;
    assign o_rdWen_1 = r_grfWen_1;
    assign w_memAddr_32 = w_exeResult_32;
    assign w_misalignTag = (w_lsuType_2 == 2'b11 & w_memAddr_32[1:0] != 2'b00)      //对全字操作的地址未对齐
                         | (w_lsuType_2 == 2'b10 & w_memAddr_32[1:0] == 2'b11);    //对半字操作的地址未对齐
    assign w_lsuEnable_1 = w_isLoad_1  | w_isStore_1 ;
    assign o_LsuPipeHold_1 = (w_lsuEnable_1 & (~r_endSignal_1));        //暂停流水线标志

    //状态机的几个状态
    localparam state_IDLE             = 4'd0;       //空闲状态
    localparam state_LoadByteAndEnd   = 4'd1;     //lb
    localparam state_LoadHwordAndEnd  = 4'd2;     //lh
    localparam state_LoadWordAndEnd   = 4'd3;     //lw
    localparam state_LoadHwordmisa    = 4'd4;     //lh & 地址未对齐
    localparam state_Loadwordmisa     = 4'd5;     //lw & 地址未对齐
    localparam state_StoreByteAndEnd  = 4'd6;     //sb
    localparam state_StoreHwordAndEnd = 4'd7;       //sh
    localparam state_StoreHwordmisa   = 4'd8;       //sh & 地址未对齐
    localparam state_StoreWordAndEnd  = 4'd9;     //sw
    localparam state_StoreWordmisa    = 4'd10;     //sw且地址未对齐


    reg [3:0] r_state_4;
    reg [3:0] r_stateNext_4;
    reg [1:0] state;

    assign o_memData_32 = r_memData_32;

    always @(*) begin
//        r_err_2 = 2'b00;
        if (w_isLoad_1) begin
	    r_err_2 = 2'b00;
            case (r_state_4)
                state_IDLE : begin          
                    r_endSignal_1 = 1'b0;
                    r_memAddr_32 = w_memAddr_32;
                    r_memData_32 = 32'b0;
                    r_memWen_4 = 4'b1111;
                    r_grfdata_32 = 32'b0;
                    r_grfWen_1 = 1'b0;
                    case (w_lsuType_2)
                        2'b11 : begin
                            r_stateNext_4 = !w_misalignTag ? state_LoadWordAndEnd : state_Loadwordmisa;
                        end 
                        2'b10 : begin
                            r_stateNext_4 = !w_misalignTag ? state_LoadHwordAndEnd : state_LoadHwordmisa;
                        end
                        2'b01 : begin
                            r_stateNext_4 = state_LoadByteAndEnd;
                        end
                        default: r_stateNext_4 = state_IDLE;
                    endcase
			end
                //end 
                state_LoadByteAndEnd : begin
                    r_endSignal_1 = 1'b1;
                    r_memAddr_32 = w_memAddr_32;
                    r_memData_32 = 32'b0;
                    r_memWen_4 = 4'b1111;
                    //对写回数据进行截取，处理包括有无符号
                    case (w_memAddr_32[1:0])
                        2'b00 : begin
                            r_grfdata_32 = w_loadSign_1 ? {{24{i_memData_32[7]}}, i_memData_32[7:0]} : {24'b0, i_memData_32[7:0]};
                        end 
                        2'b01 : begin
                            r_grfdata_32 = w_loadSign_1 ? {{24{i_memData_32[15]}}, i_memData_32[15:8]} : {24'b0, i_memData_32[15:8]};
                        end
                        2'b10 : begin
                            r_grfdata_32 = w_loadSign_1 ? {{24{i_memData_32[23]}}, i_memData_32[23:16]} : {24'b0, i_memData_32[23:16]};
                        end
                        2'b11 : begin
                            r_grfdata_32 = w_loadSign_1 ? {{24{i_memData_32[31]}}, i_memData_32[31:24]} : {24'b0, i_memData_32[31:24]};
                        end 
                    endcase
                    r_stateNext_4 = state_IDLE;
                    r_grfWen_1 = 1'b1;
                end
                state_LoadHwordAndEnd : begin
                    r_endSignal_1 = 1'b1;
                    r_memAddr_32 = w_memAddr_32;
                    r_memData_32 = 32'b0;
                    r_memWen_4 = 4'b1111;
                    //对写回数据进行截取，处理包括有无符号
                    case (w_memAddr_32[1:0])
                        2'b00 : begin
                            r_grfdata_32 = w_loadSign_1 ? {{16{i_memData_32[15]}}, i_memData_32[15:0]} : {16'b0, i_memData_32[15:0]};
                        end 
                        2'b10 : begin
                            r_grfdata_32 = w_loadSign_1 ? {{16{i_memData_32[31]}}, i_memData_32[31:16]} : {16'b0, i_memData_32[31:16]};
                        end
                        2'b01 : begin
                            r_grfdata_32 = w_loadSign_1 ? {{16{i_memData_32[23]}}, i_memData_32[23:8]} : {16'b0, i_memData_32[23:8]};
                        end
                        2'b11 : begin
                            r_grfdata_32 = w_loadSign_1 ? {{16{i_memData_32[7]}}, i_memData_32[7:0], r_tempRData[31:24]} : {16'b0, i_memData_32[7:0], r_tempRData[31:24]};
                        end 
                    endcase
                    r_grfWen_1 = 1'b1;
                    r_stateNext_4 = state_IDLE;
                end
                state_LoadHwordmisa : begin
                    //如果地址未对齐，则先取一次，暂存后改变地址再跳转到state_LoadHwordAndEnd取一次数据
                    r_endSignal_1 = 1'b0;
                    r_memAddr_32 = w_memAddr_32;
                    r_memData_32 = 32'b0;
                    r_memWen_4 = 4'b1111;

                    r_stateNext_4 = state_LoadHwordAndEnd;
                    r_tempRData = i_memData_32;
                    r_memAddr_32 = w_memAddr_32 + 32'd4;
                    r_grfWen_1 = 1'b0;
                end
                state_LoadWordAndEnd : begin
                    r_endSignal_1 = 1'b1;
                    r_memAddr_32 = w_memAddr_32;
                    r_memData_32 = 32'b0;
                    r_memWen_4 = 4'b1111;
                    r_stateNext_4 = state_IDLE;

                    case (w_memAddr_32[1:0])
                        2'b00 : begin
                            r_grfdata_32 = i_memData_32;
                        end 
                        2'b01 : begin
                            r_grfdata_32 =  {i_memData_32[7:0], r_tempRData[31:8]};
                        end
                        2'b10 : begin
                            r_grfdata_32 = {i_memData_32[15:0], r_tempRData[31:16]};
                        end
                        2'b11 : begin
                            r_grfdata_32 = {i_memData_32[23:0], r_tempRData[31:24]};
                        end 
                    endcase
                    r_grfWen_1 = 1'b1;
                end
                state_Loadwordmisa : begin
                    r_endSignal_1 = 1'b0;
                    r_memAddr_32 = w_memAddr_32;
                    r_memData_32 = 32'b0;
                    r_memWen_4 = 4'b1111;

                    r_stateNext_4 = state_LoadWordAndEnd;
                    r_tempRData = i_memData_32;
                    r_memAddr_32 = w_memAddr_32 + 32'd4;
                    r_grfWen_1 = 1'b0;
                end
                
                default: r_stateNext_4 = state_IDLE;
            endcase
        end else if (w_isStore_1) begin
		r_err_2 = 2'b00;
            case (r_state_4)
                state_IDLE : begin
                    r_endSignal_1 = 1'b0;
                    r_memAddr_32 = w_memAddr_32;
                    r_memData_32 = 32'b0;
                    r_memWen_4 = 4'b1111;
                    r_grfdata_32 = 32'b0;
                    r_grfWen_1 = 1'b0;
                    case (w_lsuType_2)
                        2'b11 : begin
                            r_stateNext_4 = !w_misalignTag ? state_StoreWordAndEnd : state_StoreWordmisa;
                        end 
                        2'b10 : begin
                            r_stateNext_4 = !w_misalignTag ? state_StoreHwordAndEnd : state_StoreHwordmisa;
                        end
                        2'b01 : begin
                            r_stateNext_4 = state_StoreByteAndEnd;
                        end
                        default: r_stateNext_4 = state_IDLE;
                    endcase
		//end
                end
                state_StoreByteAndEnd : begin
                    r_endSignal_1 = 1'b1;
                    r_memAddr_32 = w_memAddr_32;
	//r_memData_32 = w_storeData_32;
                    r_memData_32 = {4{w_storeData_32[7:0]}};
                    case (w_memAddr_32[1:0])
                        2'b00 : begin
                            r_memWen_4 = 4'b1110;
                        end 
                        2'b01 : begin
                            r_memWen_4 = 4'b1101;
                        end
                        2'b10 : begin
                            r_memWen_4 = 4'b1011;
                        end
                        2'b11 : begin
                            r_memWen_4 = 4'b0111;
                        end 
                    endcase
                    r_stateNext_4 = state_IDLE;
                    r_grfWen_1 = 1'b0;
                end
                state_StoreHwordAndEnd : begin
                    r_endSignal_1 = 1'b1;
                    r_memAddr_32 = w_memAddr_32;
                    //r_memData_32 = w_storeData_32;
                    case (w_memAddr_32[1:0])
                        2'b00 : begin
				r_memData_32 = {16'b0, w_storeData_32[15:0]};
                            r_memWen_4 = 4'b1100;
                        end 
                        2'b01 : begin
				r_memData_32 = {8'b0, w_storeData_32[15:0], 8'b0};
                            r_memWen_4 = 4'b1001;
                        end
                        2'b10 : begin
				r_memData_32 = {w_storeData_32[15:0], 16'b0};
                            r_memWen_4 = 4'b0011;
                        end
                        2'b11 : begin
				r_memData_32 = {w_storeData_32[7:0], 24'b0};
                            r_memWen_4 = 4'b0111;
                        end 
                    endcase
                    r_stateNext_4 = state_IDLE;
                    
                    r_grfWen_1 = 1'b0;
                end
                state_StoreHwordmisa : begin
                    r_endSignal_1 = 1'b0;
                    r_memAddr_32 = w_memAddr_32 + 32'd4;
                    //r_memData_32 = w_storeData_32;
			r_memData_32 = {24'b0, w_storeData_32[15:8]};
                    r_memWen_4 = 4'b1110;
                    r_stateNext_4 = state_StoreHwordAndEnd;
                    r_grfWen_1 = 1'b0;
                end
                state_StoreWordAndEnd : begin
                    r_endSignal_1 = 1'b1;
                    r_memAddr_32 = w_memAddr_32;
                    r_memData_32 = w_storeData_32;
                    case (w_memAddr_32[1:0])
                        2'b00 : begin
                            r_memWen_4 = 4'b0000;
                        end 
                        2'b01 : begin
                            r_memWen_4 = 4'b0001;
                        end
                        2'b10 : begin
                            r_memWen_4 = 4'b0011;
                        end
                        2'b11 : begin
                            r_memWen_4 = 4'b0111;
                        end 
                    endcase
                    r_stateNext_4 = state_IDLE;
                    r_grfWen_1 = 1'b0;
                end
                state_StoreWordmisa : begin
                    r_endSignal_1 = 1'b0;
                    r_memAddr_32 = w_memAddr_32 + 32'd4;
                    r_memData_32 = w_storeData_32;
                    case (w_memAddr_32[1:0])
                        2'b01 : begin
                            r_memWen_4 = 4'b1110;
                        end
                        2'b10 : begin
                            r_memWen_4 = 4'b1100;
                        end
                        2'b11 : begin
                            r_memWen_4 = 4'b1000;
                        end 
                    endcase
                    r_grfWen_1 = 1'b0;
                    r_stateNext_4 = state_StoreWordAndEnd;
                end
            endcase
        end else if (w_grfWen_1) begin
            r_err_2 = 2'b00;
            r_endSignal_1  = 1'b1;
            r_memAddr_32   = 32'b0;
            r_memData_32   = 32'b0;
            r_memWen_4     = 4'b1111;
            r_grfdata_32 = w_exeResult_32;
            r_grfWen_1 = 1'b1;
            r_stateNext_4 = state_IDLE; 
            r_err_2 = 2'b00;
        end else begin
            r_err_2 = 2'b00;
            r_endSignal_1  = 1'b1;
            r_memAddr_32   = 32'b0;
            r_memData_32   = 32'b0;
            r_memWen_4     = 4'b1111;
            r_grfdata_32   = 32'b0;
            r_grfWen_1     = 1'b0;
            r_err_2 = 2'b00;
            r_stateNext_4 = state_IDLE; 
        end
    end

    //状态机跳变
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin 
            r_state_4       <= state_IDLE;
        end else begin
            r_state_4       <= r_stateNext_4;

        end
    end
endmodule



