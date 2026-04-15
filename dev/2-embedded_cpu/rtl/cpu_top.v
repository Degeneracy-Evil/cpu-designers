`timescale 1ns / 1ps

// Phase-1 CPU top integration.
// Integrates PC, instruction memory, decode helpers, regfile, imm_gen,
// ALU control/wrapper, and the main multi-cycle FSM controller.
module cpu_top #(
    // Instruction memory depth in words.
    parameter IMEM_DEPTH = 256,
    // Optional instruction memory initialization file.
    parameter IMEM_INIT_FILE = ""
)(
    // Global clock.
    input         clk,
    // Asynchronous active-high reset.
    input         reset,
    // Debug current PC.
    output [31:0] debug_pc,
    // Debug latched instruction.
    output [31:0] debug_instr,
    // Debug FSM state.
    output [4:0]  debug_state,
    // Debug illegal instruction indication.
    output        debug_illegal
);

    // Instruction register.
    reg  [31:0] instr_reg;

    // Fetch path signals.
    wire [31:0] pc;
    wire [31:0] next_pc;
    wire [31:0] instr_word;

    // Decoded instruction fields.
    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [4:0] rd_addr;
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;

    // Datapath signals.
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] imm;
    wire [31:0] alu_src_a_data;
    wire [31:0] alu_src_b_data;
    wire [31:0] alu_result;

    // Execute/ALU control and handshake signals.
    wire [15:0] alu_ctrl;
    wire        alu_decode_illegal;
    wire        alu_req_ready;
    wire        alu_result_valid;
    wire        alu_busy;
    wire        alu_illegal_op;
    wire        alu_div_by_zero;

    // Main control outputs.
    wire        ir_write;
    wire        pc_write;
    wire [1:0]  pc_source;
    wire        reg_write;
    wire        exec_req;
    wire [1:0]  alu_src_a;
    wire [1:0]  alu_src_b;
    wire [2:0]  imm_type;
    wire        illegal_instr;
    wire        irq_sample_en;

    // ALU source select encodings (must match main_control).
    localparam ALU_SRC_A_RS1  = 2'b00;
    localparam ALU_SRC_A_PC   = 2'b01;
    localparam ALU_SRC_A_ZERO = 2'b10;

    localparam ALU_SRC_B_RS2 = 2'b00;
    localparam ALU_SRC_B_IMM = 2'b01;

    // Next sequential PC.
    assign next_pc = pc + 32'd4;

    // Debug exports.
    assign debug_pc = pc;
    assign debug_instr = instr_reg;
    assign debug_illegal = illegal_instr;

    // Instruction field extraction.
    assign rs1_addr = instr_reg[19:15];
    assign rs2_addr = instr_reg[24:20];
    assign rd_addr  = instr_reg[11:7];
    assign opcode   = instr_reg[6:0];
    assign funct3   = instr_reg[14:12];
    assign funct7   = instr_reg[31:25];

    // ALU operand A select mux.
    assign alu_src_a_data = (alu_src_a == ALU_SRC_A_PC)   ? pc :
                            (alu_src_a == ALU_SRC_A_ZERO) ? 32'b0 :
                                                             rs1_data;

    // ALU operand B select mux.
    assign alu_src_b_data = (alu_src_b == ALU_SRC_B_IMM) ? imm : rs2_data;

    // Program counter register.
    pc_reg u_pc_reg(
        .clk(clk),
        .reset(reset),
        .write_en(pc_write),
        // Phase-1 only uses +4 path.
        .next_pc((pc_source == 2'b00) ? next_pc : next_pc),
        .pc(pc)
    );

    // Instruction memory (read-only).
    instr_mem #(
        .MEM_DEPTH(IMEM_DEPTH),
        .INIT_FILE(IMEM_INIT_FILE)
    ) u_instr_mem (
        .addr(pc),
        .instr(instr_word)
    );

    // Instruction register write in FETCH state.
    always @(posedge clk or posedge reset) begin
        if (reset)
            // Reset IR to NOP.
            instr_reg <= 32'h00000013;
        else if (ir_write)
            instr_reg <= instr_word;
    end

    // Integer register file.
    regfile u_regfile(
        .clk(clk),
        .reset(reset),
        .write_en(reg_write),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .rd_data(alu_result),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    // Immediate generator.
    imm_gen u_imm_gen(
        .instr(instr_reg),
        .imm_type(imm_type),
        .imm(imm)
    );

    // Decode ALU operation.
    alu_control u_alu_control(
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .alu_control(alu_ctrl),
        .illegal_instr(alu_decode_illegal)
    );

    // Execute unit wrapper.
    alu_wrapper u_alu_wrapper(
        .clk(clk),
        .reset(reset),
        .req_valid(exec_req),
        // No flush path used in phase-1.
        .flush(1'b0),
        .alu_control(alu_ctrl),
        .src1(alu_src_a_data),
        .src2(alu_src_b_data),
        .result(alu_result),
        .ready(alu_req_ready),
        .result_valid(alu_result_valid),
        .busy(alu_busy),
        .illegal_op(alu_illegal_op),
        .div_by_zero(alu_div_by_zero)
    );

    // Main FSM controller.
    main_control u_main_control(
        .clk(clk),
        .reset(reset),
        .opcode(opcode),
        .alu_decode_illegal(alu_decode_illegal),
        .exec_ready(alu_req_ready),
        .exec_done(alu_result_valid),
        .ir_write(ir_write),
        .pc_write(pc_write),
        .pc_source(pc_source),
        .reg_write(reg_write),
        .exec_req(exec_req),
        .alu_src_a(alu_src_a),
        .alu_src_b(alu_src_b),
        .imm_type(imm_type),
        .illegal_instr(illegal_instr),
        .state_dbg(debug_state),
        .irq_sample_en(irq_sample_en)
    );

endmodule
