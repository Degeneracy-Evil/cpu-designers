`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/17 09:41:52
// Design Name: 
// Module Name: bus_arbiter
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
`include "./bus_define.vh"

module bus_arbiter(
input clk,
input reset,
input m0_req_,
input m1_req_,
output reg m0_grnt_,
output reg m1_grnt_
    );
    reg [1:0]owner;
    always@(*)begin
    /*总线使用权初始化*/
        m0_grnt_=`DISABLE_;
        m1_grnt_=`DISABLE_;
        case(owner)
            `BUS_OWNER_MASTER_0://0号总线主控
            begin
                m0_grnt_=`ENABLE_;
            end
            `BUS_OWNER_MASTER_1://1号总线主控
            begin
                m1_grnt_=`ENABLE_;
            end
        endcase
    end
    always@(posedge clk or negedge reset)begin
    //always@(*)begin
        if(~reset)begin
        /*异步复位*/
            owner =`BUS_OWNER_MASTER_0;
        end else begin
        /*仲裁*/
            case(owner)//当前总线使用权所有者
                `BUS_OWNER_MASTER_0://0号总线主控
                begin
                /*下一个获得总线使用权的主控*/
                    if(m0_req_ ==`ENABLE_)begin//0号总线主控继续请求
                        owner=`BUS_OWNER_MASTER_0;//0号总线主控继续持有总线使用权
                    end else if(m1_req_ ==`ENABLE_)begin//0号总线主控释放总线使用权，同时1号总线主控请求
                         owner=`BUS_OWNER_MASTER_1;//1号总线主控持有总线使用权
                    end
                  end
                 `BUS_OWNER_MASTER_1://1号总线主控
                  begin
                    if(m1_req_ ==`ENABLE_)begin//1号总线主控继续请求
                        owner=`BUS_OWNER_MASTER_1;//1号总线主控继续持有总线使用权
                    end else if(m0_req_ ==`ENABLE_)begin//1号总线主控释放总线使用权，同时0号总线主控请求
                         owner=`BUS_OWNER_MASTER_0;//0号总线主控持有总线使用权
                    end
                   end
            endcase
        end
    end
endmodule

