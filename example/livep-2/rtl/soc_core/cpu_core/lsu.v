`timescale 1ns / 1ps
module load_store_unit (
    input wire clk,
    input wire rstn,
    input wire [138:0] i_ExeLsuBus_139,
   //input bus
    input wire [31:0] bus_rd_data, 
    input wire bus_rdy_,
    input wire bus_grnt_, 
    //??????GRF??????????????????
    output wire [31:0] o_rdData_32,
    output wire [4:0] o_rdNum_5,
    output wire o_rdWen_1,
    //??????dCache???????????????dCache???????????????????
    input wire [31:0] i_memData_32,
    output wire [31:0] o_memAddr_32,
    output wire [31:0] o_memData_32,
    output wire [3:0] o_memWen,
    //???????????????????????????????????????????
    output wire [31:0] o_epc_32,
    output wire [31:0] o_einst_32,
    output wire o_loadAcceFalutThird_1,
    output wire o_storeAcceFalutThird_1,
    //??????????????????
    //output to bus
    output reg bus_req_,
    output reg [31:0] bus_addr,
    output reg bus_as_,
    output reg bus_rw,
    output reg [31:0] bus_wr_data, 
    output wire o_LsuPipeHold_1
);
    //dCache????????????????????????
    reg [31:0] r_memAddr_32;
    reg [31:0] r_memData_32,r_memData_32_tmp;
    reg [3:0]  r_memWen_4;

    assign o_memAddr_32 = r_memAddr_32;
    assign o_memWen = r_memWen_4;

    //dCache????????????????????????
    reg [31:0] r_tempRData; //????????????
    //139??????????????????????????????
    wire w_isLoad_1;
    wire w_isStore_1;
    wire w_loadSign_1;
    wire w_grfWen_1;
    wire [31:0] w_exeResult_32;
    wire [31:0] w_storeData_32;
    wire [1:0]  w_lsuType_2;
    wire [4:0] w_rdNum_5;
  
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
    
    //??????????????????????????
    reg r_grfWen_1;             //????????????grf????????????
    reg [31:0] r_grfdata_32;    //??????????????????GRF?????????????
    wire [31:0] w_memAddr_32;   //???????????????????????????????
    reg r_endSignal_1;          //????????????
    wire w_misalignTag;         //???????????????????
    wire w_lsuEnable_1;
    reg [1:0] r_err_2;

    assign o_loadAcceFalutThird_1 = 1'b0;
    assign o_storeAcceFalutThird_1 = 1'b0;
    assign o_rdData_32 = r_grfdata_32;
    assign o_rdWen_1 = r_grfWen_1;
    assign w_memAddr_32 = w_exeResult_32;
    assign w_misalignTag = (w_lsuType_2 == 2'b11 & w_memAddr_32[1:0] != 2'b00)      //??????????????????
                         | (w_lsuType_2 == 2'b10 & w_memAddr_32[1:0] == 2'b11);    //?????????????????????????
    assign w_lsuEnable_1 = w_isLoad_1  | w_isStore_1 ;
    assign o_LsuPipeHold_1 = (w_lsuEnable_1 & (~r_endSignal_1));

    //???????????????????
    localparam state_IDLE             = 4'd0;
    localparam state_LoadByteAndEnd   = 4'd1;     //??????? ??????  ??????????????????????????
    localparam state_LoadHwordAndEnd  = 4'd2;     //??????? ??????  ??????????????????????????
    localparam state_LoadWordAndEnd   = 4'd3;     //???????   ???????  ??????????????????????????
    localparam state_LoadHwordmisa    = 4'd4;     //??????? ???????????? ??????  ?????????????????????????
    localparam state_Loadwordmisa     = 4'd5;     //??????? ????????????   ???????  ?????????????????????????
    localparam state_StoreByteAndEnd  = 4'd6;     //??????? ??????  
    localparam state_StoreHwordAndEnd = 4'd7;
    localparam state_StoreHwordmisa   = 4'd8;
    localparam state_StoreWordAndEnd  = 4'd9;     //???????   ???????  ??????????????????????????
    localparam state_StoreWordmisa    = 4'd10;     //??????? ??????  ??????????????????????????

    reg [3:0] r_state_4;
    reg [3:0] r_stateNext_4;
    wire [2:0] s_index;
    reg [1:0] state;

    localparam bus_state_IDLE = 2'b00;
    localparam bus_state_REQ = 2'b01;
    localparam bus_state_ACCESS = 2'b10;
    
    assign s_index = ( o_memAddr_32 > 32'hffffffff ? 3'd1 : 3'd0); //???????????17ff??????????
    assign o_memData_32 = (s_index)?r_memData_32_tmp:r_memData_32;
    
 always@(posedge clk or negedge rstn)begin
        if(~rstn)begin
            state<= bus_state_IDLE;
            bus_req_ <= 1'b1;
            bus_addr<=32'b0;
            bus_as_<=1'b1;
            bus_rw<=1'b1;
            bus_wr_data<=32'b0;
	        r_memData_32_tmp<=0;
        end 
        else begin
            case(state)
             bus_state_IDLE:begin
                if(s_index != 3'd0)begin
                    state <= bus_state_REQ;
                    bus_req_ <= 1'b0;
                    bus_addr<=o_memAddr_32;
                    bus_as_<=1'b0;
                    if(o_memWen != 4'b1111)begin
                        bus_rw <=1'b0;//???????
                        bus_wr_data<=w_exeResult_32;
                    end 
                    else begin
                    bus_rw<=1'b1;
                    bus_wr_data<=32'b0;
                    end
                end
             end
             bus_state_REQ:begin
                if(bus_grnt_==1'b0)begin
                    state<=bus_state_ACCESS;
                    bus_as_<=1'b0;
                end
             end
             bus_state_ACCESS:begin
                if(bus_rdy_==1'b0)begin
                    bus_req_<=1'b1;
                    bus_addr<=32'h0;
                    bus_wr_data<=32'h0;
                    if(bus_rw == 1'b1)begin	
                    r_memData_32_tmp<=bus_rd_data;
                    end
                    state<=bus_state_IDLE;
                    bus_rw<=1'b1;
                end
              end
            endcase
        end
 end
 
    always @(*) begin
        if (w_isLoad_1) begin
            case (r_state_4)
                state_IDLE : begin
                    if (r_memAddr_32 > 32'h1fff)
                        r_err_2 = 2'b01;
                        else r_err_2 = 2'b00;               
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
                state_LoadByteAndEnd : begin
                    r_endSignal_1 = 1'b1;
                    r_memAddr_32 = w_memAddr_32;
                    r_memData_32 = 32'b0;
                    r_memWen_4 = 4'b1111;
                    //????????????????????????grf??????????????????
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
                    //??????????????????
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
        end 
        else if (w_isStore_1) begin
            case (r_state_4)
                state_IDLE : begin
                    if (r_memAddr_32 > 32'h1fff)
                        r_err_2 = 2'b10;
                        else r_err_2 = 2'b00;
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
                end
                state_StoreByteAndEnd : begin
                    r_endSignal_1 = 1'b1;
                    r_memAddr_32 = w_memAddr_32;
                    r_memData_32 = w_storeData_32;
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
                    r_memData_32 = w_storeData_32;
                    case (w_memAddr_32[1:0])
                        2'b00 : begin
                            r_memWen_4 = 4'b1100;
                        end 
                        2'b01 : begin
                            r_memWen_4 = 4'b1001;
                        end
                        2'b10 : begin
                            r_memWen_4 = 4'b0011;
                        end
                        2'b11 : begin
                            r_memWen_4 = 4'b1110;
                        end 
                    endcase
                    r_stateNext_4 = state_IDLE;  
                    r_grfWen_1 = 1'b0;
                end
                state_StoreHwordmisa : begin
                    r_endSignal_1 = 1'b0;
                    r_memAddr_32 = w_memAddr_32 + 32'd4;
                    r_memData_32 = w_storeData_32;
                    r_memWen_4 = 4'b0111;
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
        end 
        else if (w_grfWen_1) begin
            r_err_2 = 2'b00;
            r_endSignal_1  = 1'b1;
            r_memAddr_32   = 32'b0;
            r_memData_32   = 32'b0;
            r_memWen_4     = 4'b1111;
            r_grfdata_32 = w_exeResult_32;
            r_grfWen_1 = 1'b1;
            r_stateNext_4 = state_IDLE; 
            r_err_2 = 2'b00;
        end 
        else begin
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

    //????????????????????????????????????
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin 
            r_state_4       <= state_IDLE;
        end 
        else begin
            r_state_4       <= r_stateNext_4;

        end
    end
endmodule