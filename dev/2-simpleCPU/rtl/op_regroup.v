`timescale 1ns / 1ps

// 32位ricv-CPU 指令重组电路
module op_regroup(
    input [31:0] op32bit,
    output [6:0] opcode,
    output [2:0] funct3,
    output [6:0] funct7,
    output [4:0] rs1,
    output [4:0] rs2,
    output [4:0] rd,
    output [31:0] immI,
    output [31:0] immS,
    output [31:0] immB,
    output [31:0] immU,
    output [31:0] immJ
  );

  assign opcode=op32bit[6:0];
  assign funct3=op32bit[14:12];
  assign funct7=op32bit[31:25];
  assign rd=op32bit[11:7];
  assign rs1=op32bit[19:15];
  assign rs2=op32bit[24:20];

  // 立即数解码
  wire H;
  wire [5:0] D4;
  wire [3:0] D3;
  wire M;
  wire [7:0] D2;
  wire [3:0] D1;
  wire L;

  assign H=op32bit[31];
  assign D4=op32bit[30:25];
  assign D3=op32bit[24:21];
  assign M=op32bit[20];
  assign D2=op32bit[19:12];
  assign D1=op32bit[11:8];
  assign L=op32bit[7];

  // 始终进行符号扩展
  assign immI={{21{H}},D4,D3,M};
  assign immS={{21{H}},D4,D1,L};
  assign immB={{19{H}},H,L,D4,D1,1'b0};
  assign immU={H,D4,D3,M,D2,{12{1'b0}}};
  assign immJ={{12{H}},D2,M,D4,D3,1'b0};

endmodule
