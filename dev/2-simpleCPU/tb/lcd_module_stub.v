`timescale 1ns / 1ps
module lcd_module(
    input         clk,
    input         resetn,
    input         display_valid,
    input  [39:0] display_name,
    input  [31:0] display_value,
    output [5:0]  display_number,
    output        input_valid,
    output [31:0] input_value,
    output        lcd_rst,
    output        lcd_cs,
    output        lcd_rs,
    output        lcd_wr,
    output        lcd_rd,
    inout  [15:0] lcd_data_io,
    output        lcd_bl_ctr,
    inout         ct_int,
    inout         ct_sda,
    output        ct_scl,
    output        ct_rstn
);
    assign display_number = 6'd0;
    assign input_valid    = 1'b0;
    assign input_value    = 32'd0;
    assign lcd_rst        = 1'b0;
    assign lcd_cs         = 1'b0;
    assign lcd_rs         = 1'b0;
    assign lcd_wr         = 1'b0;
    assign lcd_rd         = 1'b0;
    assign lcd_bl_ctr     = 1'b0;
    assign ct_scl         = 1'b0;
    assign ct_rstn        = 1'b1;
endmodule
