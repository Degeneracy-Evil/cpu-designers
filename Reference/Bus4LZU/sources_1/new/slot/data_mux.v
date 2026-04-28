`timescale 1ns / 1ps

module slot_data(

    input wire [31:0] i_memAddr_32,
    input wire [31:0] i_lsuData_32,
    input wire [3:0] i_memWen_4,
    input wire [31:0] i_busData_32,
    input wire i_busRdy_1,
    input wire [31:0] i_memData_32,
    output wire [31:0] o_memAddr_32,
    output wire [31:0] o_memData_32,
    output reg [3:0] o_memWen_4,
    output wire [31:0] o_busData_32,
    output wire [31:0] o_busAddr_32,
    output reg o_busAs_1,
    output reg o_busRw_1,
    output wire [31:0] o_loadData_32
    );
    wire s_index;
    assign o_busAddr_32 = i_memAddr_32;
    assign o_busData_32 = i_lsuData_32;
    assign o_memAddr_32 = i_memAddr_32;
    assign o_memData_32 = i_lsuData_32;
    assign s_index =(i_memAddr_32>=32'h00010000&&i_memAddr_32<=32'h0008ffff)?1'b1:1'b0;
    assign o_loadData_32=(s_index==1'b1)?i_busData_32 : i_memData_32;
    always @(*) begin
        if (s_index==1'b1) begin
            o_busAs_1=1'b0;
            o_memWen_4 = 4'b1111;
            if(i_memWen_4==4'b1111)begin 
                o_busRw_1=1'b1;
            end else begin
                o_busRw_1=1'b0;
            end
        end else begin
            o_busAs_1=1'b1;
            o_busRw_1=1'b1;
            o_memWen_4 = i_memWen_4;
        end
    end
endmodule    
