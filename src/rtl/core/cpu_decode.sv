`timescale 1ns / 1ps
`include "core_bus_types.svh"
`include "csr_defs.svh"

module cpu_decode(
    input              id_valid,
    input      if_id_bus_t if_id_bus_r,
    input      [31:0]  rs1_value,
    input      [31:0]  rs2_value,
    output     [4:0]   rs1_addr,
    output     [4:0]   rs2_addr,
    output             id_done,
    output exception_t decode_exception,
    output             dec_need_exe,
    output     id_exe_bus_t id_exe_bus,

    output     [31:0]  id_pc,
    output     [31:0]  id_inst,

    output             dec_is_csr,
    output             dec_is_mret,
    output             dec_is_sret,
    output             dec_is_nop_like,
    output             dec_is_fencei,
    output             dec_is_sfence_vma,
    input      priv_mode_t priv_mode,
    input      [31:0]  csr_mstatus,
    input      [31:0]  csr_mcounteren,
    input      [31:0]  csr_scounteren
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
  localparam OPCODE_AMO      = 7'b0101111;  // LR.W/SC.W/AMO*.W

  wire [31:0] pc_plus4;
  wire [31:0] pc;
  wire [31:0] inst;
  assign pc_plus4 = if_id_bus_r.pc_plus4;
  assign pc       = if_id_bus_r.pc;
  assign inst     = if_id_bus_r.inst;

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

  wire inst_mul;
  wire inst_mulh;
  wire inst_mulhsu;
  wire inst_mulhu;
  wire inst_div;
  wire inst_divu;
  wire inst_rem;
  wire inst_remu;

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

  assign inst_mul    = (opcode == OPCODE_OP) && (funct3 == 3'b000) && (funct7 == 7'b0000001);
  assign inst_mulh   = (opcode == OPCODE_OP) && (funct3 == 3'b001) && (funct7 == 7'b0000001);
  assign inst_mulhsu = (opcode == OPCODE_OP) && (funct3 == 3'b010) && (funct7 == 7'b0000001);
  assign inst_mulhu  = (opcode == OPCODE_OP) && (funct3 == 3'b011) && (funct7 == 7'b0000001);
  assign inst_div    = (opcode == OPCODE_OP) && (funct3 == 3'b100) && (funct7 == 7'b0000001);
  assign inst_divu   = (opcode == OPCODE_OP) && (funct3 == 3'b101) && (funct7 == 7'b0000001);
  assign inst_rem    = (opcode == OPCODE_OP) && (funct3 == 3'b110) && (funct7 == 7'b0000001);
assign inst_remu   = (opcode == OPCODE_OP) && (funct3 == 3'b111) && (funct7 == 7'b0000001);

  // A extension instruction matches
  wire [4:0] funct5;
  assign funct5 = inst[31:27];

  wire inst_lr_w     = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b00010) && (rs2 == 5'd0);
  wire inst_sc_w     = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b00011);
  wire inst_amoswap  = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b00001);
  wire inst_amoadd   = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b00000);
  wire inst_amoand   = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b01100);
  wire inst_amoor    = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b01000);
  wire inst_amoxor   = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b00100);
wire inst_amomin   = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b10000);
wire inst_amomax   = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b10100);
wire inst_amominu  = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b11000);
wire inst_amomaxu  = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b11100);

  wire inst_ecall;
  wire inst_ebreak;
  wire inst_wfi;
  wire inst_mret;
  wire inst_sret;
  wire inst_fence;
  wire inst_fencei;
  wire inst_sfence_vma;
  wire inst_csrrw;
  wire inst_csrrs;
  wire inst_csrrc;
  wire inst_csrrwi;
  wire inst_csrrsi;
  wire inst_csrrci;

  assign inst_ecall  = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (inst[31:20] == 12'h000);
  assign inst_ebreak = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (inst[31:20] == 12'h001);
  // WFI has fixed rd=x0 and rs1=x0 fields.  Do not accept reserved SYSTEM
  // encodings that merely share WFI's funct12 value.
  assign inst_wfi    = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) &&
                        (inst[31:20] == 12'h105) && (rs1 == 5'd0) && (rd == 5'd0);
  assign inst_mret   = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (inst[31:7] == 25'b0011000_00010_00000_000_00000);
  assign inst_sret   = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (inst[31:7] == 25'b0001000_00010_00000_000_00000);
  assign inst_fence  = (opcode == OPCODE_FENCE)  && (funct3 == 3'b000);
  assign inst_fencei = (opcode == OPCODE_FENCE)  && (funct3 == 3'b001);
  // Accept sfence.vma with any rs1, rs2 (not just x0, x0).
  // rs1/rs2 are ignored — always treated as full TLB flush (same as sfence.vma x0, x0).
  // Encoding: funct7=0001001, funct3=000, rd=x0, rs1/rs2=any.
  assign inst_sfence_vma = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (inst[31:25] == 7'b0001001) && (inst[11:7] == 5'b00000);

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
  wire is_mu;
  wire is_csr;
  wire is_ecall;
  wire is_ebreak;
  wire is_mret;
  wire is_sret;
  wire is_nop_like;
  wire is_fencei;
  wire is_sfence_vma;
  wire is_system_trap;

  assign is_branch = inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu;
  assign is_load = inst_lb | inst_lh | inst_lw | inst_lbu | inst_lhu;
  assign is_store = inst_sb | inst_sh | inst_sw;
  assign is_jal_like = inst_jal | inst_jalr;
  assign is_alu = inst_lui | inst_auipc | is_load | is_store |
         inst_addi | inst_slti | inst_sltiu | inst_xori | inst_ori | inst_andi | inst_slli | inst_srli | inst_srai |
         inst_add | inst_sub | inst_sll | inst_slt | inst_sltu | inst_xor | inst_srl | inst_sra | inst_or | inst_and;
  assign is_mu = inst_mul | inst_mulh | inst_mulhsu | inst_mulhu |
         inst_div | inst_divu | inst_rem | inst_remu;
  assign is_csr = inst_csrrw | inst_csrrs | inst_csrrc | inst_csrrwi | inst_csrrsi | inst_csrrci;
  assign is_ecall = inst_ecall;
  assign is_ebreak = inst_ebreak;
  assign is_mret = inst_mret;
  assign is_sret = inst_sret;
  assign is_nop_like = inst_fence | inst_wfi;
  assign is_fencei   = inst_fencei;
  assign is_sfence_vma = inst_sfence_vma;
  assign is_system_trap = is_ecall | is_ebreak;

  // A extension classification
  wire is_amo_all = inst_amoswap | inst_amoadd | inst_amoand | inst_amoor |
                    inst_amoxor | inst_amomin | inst_amomax | inst_amominu | inst_amomaxu;
  wire is_lr = inst_lr_w;
  wire is_sc = inst_sc_w;
  wire is_amo = is_amo_all | is_lr | is_sc;  // All A extension instructions

  mem_kind_t mem_kind;
  always_comb begin
      if (is_load)         mem_kind = MEM_LOAD;
      else if (is_store)   mem_kind = MEM_STORE;
      else if (is_lr)      mem_kind = MEM_LR;
      else if (is_sc)      mem_kind = MEM_SC;
      else if (is_amo_all) mem_kind = MEM_AMO;
      else                 mem_kind = MEM_NONE;
  end

  wire use_fixed_wb;
  assign use_fixed_wb = inst_lui;

  wire valid_inst;
  assign valid_inst = is_branch | is_load | is_store | is_jal_like | is_alu | is_mu |
                       is_csr | is_system_trap | is_mret | is_sret | is_nop_like | is_fencei | is_sfence_vma |
                       is_amo;

  wire [31:0] alu_src1;
  wire [31:0] alu_src2;
  wire shift_op_r;
  wire shift_op_i;

  assign shift_op_r = inst_sll | inst_srl | inst_sra;
  assign shift_op_i = inst_slli | inst_srli | inst_srai;
   assign alu_src1 = (inst_auipc | inst_jal | is_branch) ? pc : rs1_value;
   assign alu_src2 = (inst_lui | inst_auipc) ? imm_u :
          inst_jal ? imm_j :
          inst_jalr ? imm_i :
          is_branch ? imm_b :
          (inst_addi | inst_slti | inst_sltiu | inst_xori | inst_ori | inst_andi) ? imm_i :
          shift_op_i ? {27'b0, inst[24:20]} :
           is_load ? imm_i :
           (is_store) ? imm_s :
           is_amo ? 32'b0 :   // AMO/LR/SC: address = rs1 + 0
           rs2_value;

  wire [15:0] alu_control;
  assign alu_control = inst_lui ? 16'b0000_0000_0000_0010 :
         (inst_add | inst_addi | inst_auipc | is_load | is_store | inst_jal | inst_jalr | is_branch | is_amo) ? 16'b0001_0000_0000_0000 :
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
   assign wb_we = valid_inst && ((is_alu && !is_store) |
                                 is_jal_like | is_csr | is_mu | is_amo);

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

  wire [2:0] mu_funct3;
  assign mu_funct3 = is_mu ? funct3 : 3'b0;

  wire [11:0] csr_addr;
  wire [2:0]  csr_funct3;
  wire [4:0]  csr_uimm;
  assign csr_addr   = inst[31:20];
  assign csr_funct3 = funct3;
  assign csr_uimm   = inst[19:15];

  wire csr_addr_valid;
  priv_mode_t csr_min_priv;
  wire csr_read_only;
  wire csr_is_counter_alias;
  wire [1:0] counter_enable_index;
  csr_meta u_csr_meta (
      .addr(csr_addr),
      .implemented(csr_addr_valid),
      .min_priv(csr_min_priv),
      .read_only(csr_read_only),
      .is_counter_alias(csr_is_counter_alias),
      .counter_index(counter_enable_index)
  );

  wire m_counter_enabled = csr_mcounteren[counter_enable_index];
  wire s_counter_enabled = csr_scounteren[counter_enable_index];
  wire counter_access_allowed = !csr_is_counter_alias ||
                                (priv_mode == PRIV_M) ||
                                ((priv_mode == PRIV_S) && m_counter_enabled) ||
                                ((priv_mode == PRIV_U) && m_counter_enabled &&
                                 s_counter_enabled);

  wire csr_addr_invalid = is_csr && !csr_addr_valid;
  wire csr_priv_violation = is_csr &&
                            (!priv_at_least(priv_mode, csr_min_priv) ||
                             !counter_access_allowed);
  wire csr_is_write   = (csr_funct3 == 3'b001) ||
                        (csr_funct3 == 3'b010 && rs1 != 5'd0) ||
                        (csr_funct3 == 3'b011 && rs1 != 5'd0) ||
                        (csr_funct3 == 3'b101) ||
                        (csr_funct3 == 3'b110 && inst[19:15] != 5'd0) ||
                        (csr_funct3 == 3'b111 && inst[19:15] != 5'd0);
  wire write_ro_csr   = is_csr && csr_read_only && csr_is_write;

  wire sret_priv_violation = is_sret && (priv_mode == PRIV_U);
  // MRET is legal only in M-mode.
  wire mret_priv_violation = is_mret && (priv_mode != PRIV_M);
  wire tw_bit = csr_mstatus[21];
  wire wfi_priv_violation = inst_wfi && tw_bit && (priv_mode != PRIV_M);
  wire tsr_bit = csr_mstatus[22];
  wire sret_tsr_violation = is_sret && tsr_bit && (priv_mode == PRIV_S);
  wire tvm_bit = csr_mstatus[20];
  wire sfence_priv_violation = is_sfence_vma && (priv_mode == PRIV_U);
  wire sfence_tvm_violation = is_sfence_vma && tvm_bit && (priv_mode == PRIV_S);
  // TVM traps every S-mode access to satp, including read-only CSRRS/CSRRC
  // forms.  M-mode uses this to virtualize both observing and changing satp.
  wire satp_tvm_violation = is_csr && (csr_addr == `CSR_SATP) && tvm_bit && (priv_mode == PRIV_S);

  wire illegal_inst = !valid_inst || csr_addr_invalid || csr_priv_violation || write_ro_csr ||
                      sret_priv_violation || mret_priv_violation ||
                      wfi_priv_violation || sret_tsr_violation ||
                      sfence_priv_violation || sfence_tvm_violation ||
                      satp_tvm_violation;
  wire decode_fault = illegal_inst || is_ecall || is_ebreak;

  assign decode_exception = '{
      valid: id_valid && decode_fault,
      cause: illegal_inst ? 32'd2 :
             is_ecall ? ((priv_mode == PRIV_U) ? 32'd8 :
                         (priv_mode == PRIV_S) ? 32'd9 : 32'd11) : 32'd3,
      epc:   pc,
      tval:  illegal_inst ? inst : 32'b0
  };
  assign id_done = id_valid && !decode_fault;
  assign rs1_addr = rs1;
  assign rs2_addr = rs2;
  assign dec_need_exe = id_valid && valid_inst && !is_nop_like && !is_fencei && !is_sfence_vma && !is_system_trap && !is_mret && !is_sret && !is_csr;

  assign dec_is_csr    = id_valid && valid_inst && is_csr;
  assign dec_is_mret   = id_valid && valid_inst && is_mret;
  assign dec_is_sret   = id_valid && valid_inst && is_sret;
  assign dec_is_nop_like = id_valid && valid_inst && (is_nop_like && !wfi_priv_violation);
  assign dec_is_fencei   = id_valid && valid_inst && is_fencei;
  assign dec_is_sfence_vma = id_valid && valid_inst && is_sfence_vma &&
                             !sfence_priv_violation && !sfence_tvm_violation;
  assign id_exe_bus = '{
      pc:            pc,
      pc_plus4:      pc_plus4,
      inst:          inst,
      alu_control:   alu_control,
      alu_src1:      alu_src1,
      alu_src2:      alu_src2,
      is_branch:     is_branch,
      is_jal_like:   is_jal_like,
      branch_funct3: branch_funct3,
      use_fixed_wb:  use_fixed_wb,
      fixed_wb_data: wb_fixed_data,
      wb_we:         wb_we,
      wb_rd:         rd,
      is_mu:         is_mu,
      mu_funct3:     mu_funct3,
      mem_kind:      mem_kind,
      mem_size:      mem_size,
      mem_unsigned:  mem_unsigned,
      rs1_value:     rs1_value,
      rs2_value:     rs2_value,
      amo_funct5:    funct5,
      csr_addr:      csr_addr,
      csr_funct3:    csr_funct3,
      csr_uimm:      csr_uimm,
      csr_rs1:       rs1
  };

  assign id_pc = pc;
  assign id_inst = inst;

endmodule
