`timescale 1ns / 1ps

module cpu_decode(
    input              id_valid,
    input      [95:0]  if_id_bus_r,
    input      [31:0]  rs1_value,
    input      [31:0]  rs2_value,
    output     [4:0]   rs1_addr,
    output     [4:0]   rs2_addr,
    output             id_done,
    output             illegal_inst,
    output             dec_is_branch,
    output             dec_need_exe,
    output     [315:0] id_exe_bus,

    output     [31:0]  id_pc,
    output     [31:0]  id_inst,

    output             dec_is_csr,
    output             dec_is_ecall,
    output             dec_is_ebreak,
    output             dec_is_mret,
    output             dec_is_fence,
    output     [11:0]  dec_csr_addr,
    output     [2:0]   dec_csr_funct3,
    output             dec_csr_addr_valid
  );
  localparam OPCODE_LUI    = 7'b0110111;
  localparam OPCODE_AUIPC  = 7'b0010111;
  localparam OPCODE_JAL    = 7'b1101111;
  localparam OPCODE_JALR   = 7'b1100111;
  localparam OPCODE_BRANCH = 7'b1100011;
  localparam OPCODE_LOAD   = 7'b0000011;
  localparam OPCODE_STORE  = 7'b0100011;
  localparam OPCODE_OP_IMM = 7'b0010011;
  localparam OPCODE_OP     = 7'b0110011;
  localparam OPCODE_FENCE  = 7'b0001111;
  localparam OPCODE_SYSTEM = 7'b1110011;

  wire [31:0] pc_plus4;
  wire [31:0] pc;
  wire [31:0] inst;
  assign {pc_plus4, pc, inst} = if_id_bus_r;

  wire [6:0] opcode;
  wire [2:0] funct3;
  wire [6:0] funct7;
  wire [4:0] rs1;
  wire [4:0] rs2;
  wire [4:0] rd;
  wire [31:0] imm_i;
  wire [31:0] imm_s;
  wire [31:0] imm_b;
  wire [31:0] imm_u;
  wire [31:0] imm_j;

  op_regroup u_op_regroup(
               .op32bit(inst),
               .opcode(opcode),
               .funct3(funct3),
               .funct7(funct7),
               .rs1(rs1),
               .rs2(rs2),
               .rd(rd),
               .immI(imm_i),
               .immS(imm_s),
               .immB(imm_b),
               .immU(imm_u),
               .immJ(imm_j)
             );

  wire inst_lui;
  wire inst_auipc;
  wire inst_jal;
  wire inst_jalr;
  wire inst_beq;
  wire inst_bne;
  wire inst_blt;
  wire inst_bge;
  wire inst_bltu;
  wire inst_bgeu;
  wire inst_lb;
  wire inst_lh;
  wire inst_lw;
  wire inst_lbu;
  wire inst_lhu;
  wire inst_sb;
  wire inst_sh;
  wire inst_sw;
  wire inst_addi;
  wire inst_slti;
  wire inst_sltiu;
  wire inst_xori;
  wire inst_ori;
  wire inst_andi;
  wire inst_slli;
  wire inst_srli;
  wire inst_srai;
  wire inst_add;
  wire inst_sub;
  wire inst_sll;
  wire inst_slt;
  wire inst_sltu;
  wire inst_xor;
  wire inst_srl;
  wire inst_sra;
  wire inst_or;
  wire inst_and;

  assign inst_lui   = (opcode == OPCODE_LUI);
  assign inst_auipc = (opcode == OPCODE_AUIPC);
  assign inst_jal   = (opcode == OPCODE_JAL);
  assign inst_jalr  = (opcode == OPCODE_JALR)   && (funct3 == 3'b000);

  assign inst_beq  = (opcode == OPCODE_BRANCH) && (funct3 == 3'b000);
  assign inst_bne  = (opcode == OPCODE_BRANCH) && (funct3 == 3'b001);
  assign inst_blt  = (opcode == OPCODE_BRANCH) && (funct3 == 3'b100);
  assign inst_bge  = (opcode == OPCODE_BRANCH) && (funct3 == 3'b101);
  assign inst_bltu = (opcode == OPCODE_BRANCH) && (funct3 == 3'b110);
  assign inst_bgeu = (opcode == OPCODE_BRANCH) && (funct3 == 3'b111);

  assign inst_lb  = (opcode == OPCODE_LOAD) && (funct3 == 3'b000);
  assign inst_lh  = (opcode == OPCODE_LOAD) && (funct3 == 3'b001);
  assign inst_lw  = (opcode == OPCODE_LOAD) && (funct3 == 3'b010);
  assign inst_lbu = (opcode == OPCODE_LOAD) && (funct3 == 3'b100);
  assign inst_lhu = (opcode == OPCODE_LOAD) && (funct3 == 3'b101);

  assign inst_sb = (opcode == OPCODE_STORE) && (funct3 == 3'b000);
  assign inst_sh = (opcode == OPCODE_STORE) && (funct3 == 3'b001);
  assign inst_sw = (opcode == OPCODE_STORE) && (funct3 == 3'b010);

  assign inst_addi  = (opcode == OPCODE_OP_IMM) && (funct3 == 3'b000);
  assign inst_slti  = (opcode == OPCODE_OP_IMM) && (funct3 == 3'b010);
  assign inst_sltiu = (opcode == OPCODE_OP_IMM) && (funct3 == 3'b011);
  assign inst_xori  = (opcode == OPCODE_OP_IMM) && (funct3 == 3'b100);
  assign inst_ori   = (opcode == OPCODE_OP_IMM) && (funct3 == 3'b110);
  assign inst_andi  = (opcode == OPCODE_OP_IMM) && (funct3 == 3'b111);
  assign inst_slli  = (opcode == OPCODE_OP_IMM) && (funct3 == 3'b001) && (inst[31:25] == 7'b0000000);
  assign inst_srli  = (opcode == OPCODE_OP_IMM) && (funct3 == 3'b101) && (inst[31:25] == 7'b0000000);
  assign inst_srai  = (opcode == OPCODE_OP_IMM) && (funct3 == 3'b101) && (inst[31:25] == 7'b0100000);

  assign inst_add  = (opcode == OPCODE_OP) && (funct3 == 3'b000) && (funct7 == 7'b0000000);
  assign inst_sub  = (opcode == OPCODE_OP) && (funct3 == 3'b000) && (funct7 == 7'b0100000);
  assign inst_sll  = (opcode == OPCODE_OP) && (funct3 == 3'b001) && (funct7 == 7'b0000000);
  assign inst_slt  = (opcode == OPCODE_OP) && (funct3 == 3'b010) && (funct7 == 7'b0000000);
  assign inst_sltu = (opcode == OPCODE_OP) && (funct3 == 3'b011) && (funct7 == 7'b0000000);
  assign inst_xor  = (opcode == OPCODE_OP) && (funct3 == 3'b100) && (funct7 == 7'b0000000);
  assign inst_srl  = (opcode == OPCODE_OP) && (funct3 == 3'b101) && (funct7 == 7'b0000000);
  assign inst_sra  = (opcode == OPCODE_OP) && (funct3 == 3'b101) && (funct7 == 7'b0100000);
  assign inst_or   = (opcode == OPCODE_OP) && (funct3 == 3'b110) && (funct7 == 7'b0000000);
  assign inst_and  = (opcode == OPCODE_OP) && (funct3 == 3'b111) && (funct7 == 7'b0000000);

  wire inst_ecall;
  wire inst_ebreak;
  wire inst_mret;
  wire inst_fence;
  wire inst_fencei;
  wire inst_csrrw;
  wire inst_csrrs;
  wire inst_csrrc;
  wire inst_csrrwi;
  wire inst_csrrsi;
  wire inst_csrrci;

  assign inst_ecall  = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (inst[31:20] == 12'h000);
  assign inst_ebreak = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (inst[31:20] == 12'h001);
  assign inst_mret   = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (inst[31:7] == 25'b0011000_00010_00000_000_00000);
  assign inst_fence  = (opcode == OPCODE_FENCE)  && (funct3 == 3'b000);
  assign inst_fencei = (opcode == OPCODE_FENCE)  && (funct3 == 3'b001);

  assign inst_csrrw  = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b001);
  assign inst_csrrs  = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b010);
  assign inst_csrrc  = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b011);
  assign inst_csrrwi = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b101);
  assign inst_csrrsi = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b110);
  assign inst_csrrci = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b111);

  wire is_branch;
  wire is_load;
  wire is_store;
  wire is_jal_like;
  wire is_alu;
  wire is_csr;
  wire is_ecall;
  wire is_ebreak;
  wire is_mret;
  wire is_fence;
  wire is_system_trap;

  assign is_branch = inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu;
  assign is_load = inst_lb | inst_lh | inst_lw | inst_lbu | inst_lhu;
  assign is_store = inst_sb | inst_sh | inst_sw;
  assign is_jal_like = inst_jal | inst_jalr;
  assign is_alu = inst_lui | inst_auipc | is_load | is_store |
         inst_addi | inst_slti | inst_sltiu | inst_xori | inst_ori | inst_andi | inst_slli | inst_srli | inst_srai |
         inst_add | inst_sub | inst_sll | inst_slt | inst_sltu | inst_xor | inst_srl | inst_sra | inst_or | inst_and;
  assign is_csr = inst_csrrw | inst_csrrs | inst_csrrc | inst_csrrwi | inst_csrrsi | inst_csrrci;
  assign is_ecall = inst_ecall;
  assign is_ebreak = inst_ebreak;
  assign is_mret = inst_mret;
  assign is_fence = inst_fence | inst_fencei;
  assign is_system_trap = is_ecall | is_ebreak;

  wire use_fixed_wb;
  assign use_fixed_wb = inst_lui;

  wire valid_inst;
  assign valid_inst = is_branch | is_load | is_store | is_jal_like | is_alu |
                      is_csr | is_system_trap | is_mret | is_fence;

  wire [31:0] alu_src1;
  wire [31:0] alu_src2;
  wire shift_op_r;
  wire shift_op_i;

  assign shift_op_r = inst_sll | inst_srl | inst_sra;
  assign shift_op_i = inst_slli | inst_srli | inst_srai;
  assign alu_src1 = shift_op_r ? {27'b0, rs2_value[4:0]} :
         (shift_op_r | shift_op_i) ? rs1_value :
         (inst_auipc | inst_jal | is_branch) ? pc :
         inst_jalr ? rs1_value :
         rs1_value;
  assign alu_src2 = (inst_lui | inst_auipc) ? imm_u :
         inst_jal ? imm_j :
         inst_jalr ? imm_i :
         is_branch ? imm_b :
         (inst_addi | inst_slti | inst_sltiu | inst_xori | inst_ori | inst_andi) ? imm_i :
         shift_op_i ? {27'b0, inst[24:20]} :
         (is_load) ? imm_i :
         (is_store) ? imm_s :
         rs2_value;

  wire [15:0] alu_control;
  assign alu_control = inst_lui ? 16'b0000_0000_0000_0010 :
         (inst_add | inst_addi | inst_auipc | is_load | is_store | inst_jal | inst_jalr | is_branch) ? 16'b0001_0000_0000_0000 :
         inst_sub ? 16'b0000_1000_0000_0000 :
         (inst_slt | inst_slti) ? 16'b0000_0100_0000_0000 :
         (inst_sltu | inst_sltiu) ? 16'b0000_0010_0000_0000 :
         (inst_and | inst_andi) ? 16'b0000_0001_0000_0000 :
         (inst_or | inst_ori) ? 16'b0000_0000_0100_0000 :
         (inst_xor | inst_xori) ? 16'b0000_0000_0010_0000 :
         (inst_sll | inst_slli) ? 16'b0000_0000_0001_0000 :
         (inst_srl | inst_srli) ? 16'b0000_0000_0000_1000 :
         (inst_sra | inst_srai) ? 16'b0000_0000_0000_0100 :
         16'b0;

  wire wb_we;
  assign wb_we = valid_inst && (is_alu | is_load | is_jal_like | is_csr);

  wire [2:0] mem_size;
  assign mem_size = (inst_lb | inst_lbu | inst_sb) ? 3'b000 :
         (inst_lh | inst_lhu | inst_sh) ? 3'b001 :
         3'b010;

  wire mem_unsigned;
  assign mem_unsigned = inst_lbu | inst_lhu;

  wire [31:0] wb_fixed_data;
  assign wb_fixed_data = inst_lui ? imm_u : 32'b0;

  wire [2:0] branch_funct3;
  assign branch_funct3 = is_branch ? funct3 : 3'b0;

  wire [11:0] csr_addr;
  wire [2:0]  csr_funct3;
  wire [4:0]  csr_uimm;
  assign csr_addr   = inst[31:20];
  assign csr_funct3 = funct3;
  assign csr_uimm   = inst[19:15];

  assign id_done = id_valid;
  assign illegal_inst = id_valid && !valid_inst;
  assign rs1_addr = rs1;
  assign rs2_addr = rs2;
  assign dec_is_branch = id_valid && valid_inst && is_branch;
  assign dec_need_exe = id_valid && valid_inst && !is_fence && !is_system_trap && !is_mret && !is_csr;

  assign dec_is_csr    = id_valid && valid_inst && is_csr;
  assign dec_is_ecall  = id_valid && valid_inst && is_ecall;
  assign dec_is_ebreak = id_valid && valid_inst && is_ebreak;
  assign dec_is_mret   = id_valid && valid_inst && is_mret;
  assign dec_is_fence  = id_valid && valid_inst && is_fence;
  assign dec_csr_addr  = csr_addr;
  assign dec_csr_funct3 = csr_funct3;

  localparam CSR_MSTATUS  = 12'h300;
  localparam CSR_MIE      = 12'h304;
  localparam CSR_MTVEC    = 12'h305;
  localparam CSR_MSCRATCH = 12'h340;
  localparam CSR_MEPC     = 12'h341;
  localparam CSR_MCAUSE   = 12'h342;
  localparam CSR_MTVAL    = 12'h343;
  localparam CSR_MIP      = 12'h344;

  assign dec_csr_addr_valid = (csr_addr == CSR_MSTATUS)  ||
                              (csr_addr == CSR_MIE)      ||
                              (csr_addr == CSR_MTVEC)    ||
                              (csr_addr == CSR_MSCRATCH) ||
                              (csr_addr == CSR_MEPC)     ||
                              (csr_addr == CSR_MCAUSE)   ||
                              (csr_addr == CSR_MTVAL)    ||
                              (csr_addr == CSR_MIP);

  assign id_exe_bus = {
           pc_plus4,
           valid_inst,
           is_alu,
           is_load,
           is_store,
           is_jal_like,
           is_branch,
           use_fixed_wb,
           wb_we,
           rd,
           wb_fixed_data,
           mem_size,
           mem_unsigned,
           alu_control,
           alu_src1,
           alu_src2,
           rs1_value,
           rs2_value,
           branch_funct3,
           is_csr,
           is_ecall,
           is_ebreak,
           is_mret,
           csr_addr,
           csr_funct3,
           csr_uimm,
           pc,
           inst
         };

  assign id_pc = pc;
  assign id_inst = inst;

endmodule
