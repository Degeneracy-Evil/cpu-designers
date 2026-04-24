`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/18 03:11:01
// Design Name: 
// Module Name: ifStage
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

`include "bus_define.vh"
module ifStage(
    input  wire        clk,  
    input  wire        rstn,  
    input  wire        i_holdflag_if_1,
    input  wire [31:0] i_inst_32,          
    input  wire        i_isIntPC_1,         
    input  wire [31:0] i_intPC_32,
    input  wire [63:0] i_grfToIf_64,
    //bus to if
    input  wire         bus_rdy_,
    input  wire         bus_grnt_,
    input  wire [31:0]  bus_rd_data,     
    //icache
    output wire [31:0]  o_nextPC_32,
    //int
    output wire [31:0]  o_pc_if_32, 
    output wire [31:0]  o_intIns_if_32,    
    //if to bus
    output reg          bus_req_,
    output reg          bus_as_,
    output reg          bus_rw,
    output reg [31:0]   bus_addr,
    output reg [31:0]   bus_wr_data,
    output wire [63:0]  o_PcAndinstr_64,
    
    output wire [9:0]   o_ifToGrf_10,
    output wire [1:0]   o_ifEnToGrf_2,
    output wire         o_InstrAcceFaultFirst_if_1,
    output wire         o_ecall_1,
    output wire         o_ebreak_1,
    output wire         o_mret_1
);
    wire          w_isBranch_1;
    wire [31:0]   w_branchPC_32;
    wire [31:0]   w_instaddr_if_32;
    wire [31:0]   w_inst_if_32;
    wire [31:0]   o_nextPC_32_tmp;
    wire [2:0]    s_index;
    reg  [1:0]    state;
    reg  [31:0]   rd_buf;
    
    localparam state_IDLE = 2'b00;
    localparam state_REQ  = 2'b01;
    localparam state_ACCESS = 2'b10;
    
    assign s_index = ( o_nextPC_32_tmp > 32'h1bff ? 3'd1 : `BUS_SLAVE_0); //当地址大于1bff时访问外设
    
    always@(posedge clk or negedge rstn)begin
        if(~rstn)begin
            state<= state_IDLE;
            bus_req_ <= 1'b1;
            bus_addr<=32'b0;
            bus_as_<=1'b1;
            bus_rw<=`READ;
            bus_wr_data<=32'b0;
        end 
        else begin
            case(state)
             state_IDLE:begin
                if(s_index != `BUS_SLAVE_0)begin
                    state <= state_REQ;
                    bus_req_ <= 1'b0;
                    bus_addr<=i_inst_32;
                    bus_as_<=1'b0;
                    bus_rw<=`READ;
                    bus_wr_data<=32'b0;
                end
             end
             state_REQ:begin
                if(bus_grnt_==1'b0)begin
                    state<=state_ACCESS;
                    bus_as_<=1'b0;
                end
             end
             state_ACCESS:begin
                if(bus_rdy_==1'b0)begin
                    bus_req_<=1'b1;
                    bus_addr<=32'h0;
                    bus_rw<=`READ;
                    bus_wr_data<=32'h0;
                    rd_buf<=bus_rd_data;
                    state<=state_IDLE;
                end
             end
           endcase
        end
    end
m_prefetch prefetch(
        .clk                (clk),     
        .rstn               (rstn),  
        .i_holdflag_1       (i_holdflag_if_1),  
        //icache??????
        .i_inst_32          (i_inst_32),
        //???pc?????
        .i_isBranch_1       (w_isBranch_1), 
        .i_branchPC_32      (w_branchPC_32),  
        //?ж?pc?????
        .i_isIntPC_1        (i_isIntPC_1),    
        .i_intPC_32         (i_intPC_32),            
        //???pc??ins-????????/???ж?/??????
        .o_OutputPC_32      (w_instaddr_if_32),
        .o_OutputInst_32    (w_inst_if_32),
        //??????????pc
        .o_fetchaddr_32     (o_nextPC_32_tmp),
        .o_InstrAcceFaultFirst_1 (o_InstrAcceFaultFirst_if_1)
    );
    
    wire [31:0] w_ins_if_32;
    
    m_prebranch m_prebranch(
        .i_inst_32          (w_inst_if_32),
        .i_addr_32          (w_instaddr_if_32),
        .o_ifToGrf_10       (o_ifToGrf_10),
        .o_ifEnToGrf_2      (o_ifEnToGrf_2),
        .i_grfToIf_64       (i_grfToIf_64),
        .o_inst_32          (w_ins_if_32),
        .o_ecall            (o_ecall_1),         
        .o_ebreak           (o_ebreak_1),
        .o_mret             (o_mret_1),
        .o_branchPC_32      (w_branchPC_32),
        .o_isBranch_1       (w_isBranch_1)
    );
    
	assign o_pc_if_32 = w_instaddr_if_32;
	assign o_intIns_if_32 = w_inst_if_32;
    assign o_PcAndinstr_64 = {w_instaddr_if_32,w_ins_if_32};
    assign o_nextPC_32 = (s_index == `BUS_SLAVE_0 ? o_nextPC_32_tmp : rd_buf);
    
endmodule
