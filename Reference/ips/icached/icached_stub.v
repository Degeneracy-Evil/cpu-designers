// Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2018.3 (win64) Build 2405991 Thu Dec  6 23:38:27 MST 2018
// Date        : Sun May 17 15:57:00 2026
// Host        : LAPTOP-6T6LFEVF running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               e:/Xprogram/FPGA/tmpp/project/simplecpu_bus/simplecpu_bus.srcs/sources_1/ip/icached_1/icached_stub.v
// Design      : icached
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a200tfbg676-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_4_2,Vivado 2018.3" *)
module icached(clka, ena, wea, addra, dina, douta, clkb, enb, web, addrb, 
  dinb, doutb)
/* synthesis syn_black_box black_box_pad_pin="clka,ena,wea[31:0],addra[7:0],dina[255:0],douta[255:0],clkb,enb,web[31:0],addrb[7:0],dinb[255:0],doutb[255:0]" */;
  input clka;
  input ena;
  input [31:0]wea;
  input [7:0]addra;
  input [255:0]dina;
  output [255:0]douta;
  input clkb;
  input enb;
  input [31:0]web;
  input [7:0]addrb;
  input [255:0]dinb;
  output [255:0]doutb;
endmodule
