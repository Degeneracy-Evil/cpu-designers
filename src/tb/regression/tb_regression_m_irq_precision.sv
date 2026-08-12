`timescale 1ns / 1ps
`include "core_bus_types.svh"

// A pending interrupt must not cancel an in-flight M-extension instruction.
// The instruction completes and reaches WB first; only then may the controller
// enter the trap state.  This is the precise-interrupt contract required by
// Linux (notably by scheduler arithmetic such as avg_vruntime()).
module tb_regression_m_irq_precision;
  localparam [3:0] STATE_EXEC       = 4'd3;
  localparam [3:0] STATE_WB         = 4'd5;
  localparam [3:0] STATE_TRAP_ENTER = 4'd7;

  logic clk = 1'b0;
  logic resetn = 1'b0;
  always #5 clk = ~clk;

  logic trap_pending = 1'b0;
  logic [329:0] id_exe_bus_r;
  logic exe_done;
  logic exe_valid;
  logic wb_valid;
  logic trap_enter_valid;
  logic exe_is_branch;
  logic exe_need_mem;
  logic [3:0] state;
  logic dbg_mu_active;
  exe_mem_bus_t exe_mem_bus;

  cpu_controller u_controller (
    .clk(clk),
    .resetn(resetn),
    .if_done(1'b1),
    .id_done(1'b1),
    .exe_done(exe_done),
    .mem_done(1'b1),
    .wb_done(1'b1),
    .dec_is_branch(1'b0),
    .dec_need_exe(1'b1),
    .dec_illegal(1'b0),
    .dec_is_csr(1'b0),
    .dec_is_ecall(1'b0),
    .dec_is_ebreak(1'b0),
    .dec_is_mret(1'b0),
    .dec_is_sret(1'b0),
    .dec_is_nop_like(1'b0),
    .dec_is_fencei(1'b0),
    .dec_is_sfence_vma(1'b0),
    .exe_is_branch(exe_is_branch),
    .exe_need_mem(exe_need_mem),
    .trap_pending(trap_pending),
    .exception_at_decode(1'b0),
    .inst_access_fault_pending(1'b0),
    .data_access_fault_pending(1'b0),
    .inst_page_fault_pending(1'b0),
    .data_page_fault_pending(1'b0),
    .mmu_inst_miss(1'b0),
    .mmu_data_miss(1'b0),
    .mem_data_access(1'b0),
    .init_sig(1'b0),
    .if_valid(),
    .id_valid(),
    .exe_valid(exe_valid),
    .mem_valid(),
    .wb_valid(wb_valid),
    .csr_valid(),
    .trap_enter_valid(trap_enter_valid),
    .trap_return_valid(),
    .exe_to_wb(),
    .fencei_req(),
    .fencei_done(1'b1),
    .sfence_vma_req(),
    .sfence_vma_done(1'b1),
    .state(state)
  );

  cpu_execute u_execute (
    .clk(clk),
    .resetn(resetn),
    .exe_valid(exe_valid),
    .id_exe_bus_r(id_exe_bus_r),
    .csr_rdata(32'b0),
    .exe_done(exe_done),
    .exe_mem_bus(exe_mem_bus),
    .exe_branch_taken(),
    .exe_branch_target(),
    .exe_is_ctrl_flow(),
    .exe_is_branch(exe_is_branch),
    .exe_need_mem(exe_need_mem),
    .exe_pc(),
    .exe_inst(),
    .exe_misalign_valid(),
    .exe_misalign_target(),
    .exe_csr_wen(),
    .exe_csr_waddr(),
    .exe_csr_wdata(),
    .exe_csr_old_val(),
    .dbg_mu_active(dbg_mu_active),
    .dbg_mu_req_valid(),
    .dbg_mu_ready(),
    .dbg_mu_busy(),
    .dbg_mu_result_valid(),
    .dbg_mu_funct3(),
    .dbg_exe_is_mu()
  );

  initial begin
    // MULHU x5, x?, x?: 0xffffffff * 0xffffffff -> high word fffffffe.
    id_exe_bus_r = {
      32'h8000_0104, // pc_plus4
      1'b1,         // valid_inst
      1'b0,         // is_alu
      1'b0,         // is_load
      1'b0,         // is_store
      1'b0,         // is_jal_like
      1'b0,         // is_branch
      1'b0,         // use_fixed_wb
      1'b1,         // wb_we
      5'd5,         // wb_rd
      32'b0,        // wb_fixed_data
      3'b010,       // mem_size
      1'b0,         // mem_unsigned
      16'b0,        // alu_control
      1'b1,         // is_mu
      3'b011,       // MULHU
      32'hffff_ffff,// alu_src1
      32'hffff_ffff,// alu_src2
      32'hffff_ffff,// rs1_value
      32'hffff_ffff,// rs2_value
      3'b0,         // branch_funct3
      1'b0,         // is_csr
      1'b0,         // is_ecall
      1'b0,         // is_ebreak
      1'b0,         // is_mret
      12'b0,        // csr_addr
      3'b0,         // csr_funct3
      5'b0,         // csr_uimm
      32'h8000_0100,// pc
      32'h0200_32b3,// representative MULHU encoding
      1'b0,         // is_amo
      1'b0,         // is_lr
      1'b0,         // is_sc
      5'b0,         // amo_funct5
      1'b0,         // amo_aq
      1'b0          // amo_rl
    };

    repeat (4) @(posedge clk);
    resetn = 1'b1;

    wait (dbg_mu_active);
    @(negedge clk);
    trap_pending = 1'b1;

    while (!exe_done) begin
      @(posedge clk);
      #1;
      if (!exe_done && state != STATE_EXEC)
        $fatal(1, "controller left EXEC while MULHU was active: state=%0d", state);
    end

    if (!exe_mem_bus.result_ok)
      $fatal(1, "MULHU completion was suppressed by pending interrupt");
    if (exe_mem_bus.result_reg !== 32'hffff_fffe)
      $fatal(1, "bad MULHU result: got %08x", exe_mem_bus.result_reg);

    @(posedge clk);
    #1;
    if (state != STATE_WB || !wb_valid)
      $fatal(1, "expected WB before trap, state=%0d", state);

    @(posedge clk);
    #1;
    if (state != STATE_TRAP_ENTER || !trap_enter_valid)
      $fatal(1, "expected trap after WB, state=%0d", state);

    $display("TEST_PASS: in-flight MULHU completed before pending interrupt");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "timeout");
  end
endmodule
