// Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2018.3 (win64) Build 2405991 Thu Dec  6 23:38:27 MST 2018
// Date        : Sat May  2 16:25:08 2026
// Host        : LAPTOP-6T6LFEVF running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub e:/Xprogram/FPGA/tmpp/tmpp.srcs/sources_1/ip/icache/icache_stub.v
// Design      : icache
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a200tfbg676-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_4_2,Vivado 2018.3" *)
module icache(clka, ena, wea, addra, dina, douta, clkb, enb, web, addrb, 
  dinb, doutb)
/* synthesis syn_black_box black_box_pad_pin="clka,ena,wea[0:0],addra[8:0],dina[31:0],douta[31:0],clkb,enb,web[0:0],addrb[8:0],dinb[31:0],doutb[31:0]" */;
  input clka;
  input ena;
  input [0:0]wea;
  input [8:0]addra;
  input [31:0]dina;
  output [31:0]douta;
  input clkb;
  input enb;
  input [0:0]web;
  input [8:0]addrb;
  input [31:0]dinb;
  output [31:0]doutb;
endmodule
