`timescale 1ns / 1ps

// Phase-2 CPU top integration.
module cpu_top #(
    parameter IMEM_DEPTH = 256,
    parameter IMEM_ADDR_WIDTH = 8,
    parameter IMEM_INIT_FILE = "",
    parameter DMEM_DEPTH = 256,
    parameter DMEM_ADDR_WIDTH = 8
)(
    input         clk,
    input         reset,
    output [31:0] debug_pc,
    output [31:0] debug_instr,
    output [4:0]  debug_state,
    output        debug_illegal,
    output [31:0] debug_mem_addr,
    output [31:0] debug_mem_wdata,
    output [31:0] debug_mem_rdata,
    output [3:0]  debug_mem_wstrb,
    output [31:0] debug_display_mem_data
);

    reg  [31:0] instr_reg;
    reg  [31:0] instr_pc_reg;
    reg  [31:0] mem_data_reg;

    wire [31:0] pc;
    wire [31:0] pc_plus4_fetch;
    wire [31:0] pc_plus4_instr;
    wire [31:0] instr_word;

    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [4:0] rd_addr;
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;

    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] imm;

    wire [31:0] alu_src_a_data;
    wire [31:0] alu_src_b_data;
    wire [31:0] alu_exec_src1;
    wire [31:0] alu_exec_src2;
    wire [31:0] alu_result;

    wire [15:0] alu_ctrl;
    wire        alu_decode_illegal;
    wire        alu_req_ready;
    wire        alu_result_valid;
    wire        alu_busy;
    wire        alu_illegal_op;
    wire        alu_div_by_zero;

    wire        ir_write;
    wire        pc_write;
    wire [1:0]  pc_source;
    wire        reg_write;
    wire        exec_req;
    wire        mem_req;
    wire        mem_write_en;
    wire [1:0]  wb_sel;
    wire [1:0]  alu_src_a;
    wire [1:0]  alu_src_b;
    wire [2:0]  imm_type;
    wire        illegal_instr;
    wire        irq_sample_en;

    wire        mem_ready;
    wire        mem_rvalid;
    wire        mem_wdone;
    wire [31:0] mem_rdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [31:0] mem_data_display;
    wire [31:0] load_data;
    wire [7:0]  load_byte;
    wire [15:0] load_half;

    wire        branch_taken;
    wire [31:0] branch_target;
    wire [31:0] jump_target;
    wire [31:0] wb_data;
    wire        is_rtype_shift;
    wire        is_itype_shift;

    localparam ALU_SRC_A_RS1  = 2'b00;
    localparam ALU_SRC_A_PC   = 2'b01;
    localparam ALU_SRC_A_ZERO = 2'b10;

    localparam ALU_SRC_B_RS2 = 2'b00;
    localparam ALU_SRC_B_IMM = 2'b01;

    localparam PC_PLUS4  = 2'b00;
    localparam PC_BRANCH = 2'b01;
    localparam PC_JUMP   = 2'b10;

    localparam WB_ALU = 2'b00;
    localparam WB_MEM = 2'b01;
    localparam WB_PC4 = 2'b10;

    localparam OPCODE_BRANCH = 7'b1100011;
    localparam OPCODE_JALR   = 7'b1100111;

    assign pc_plus4_fetch = pc + 32'd4;
    assign pc_plus4_instr = instr_pc_reg + 32'd4;

    assign debug_pc = pc;
    assign debug_instr = instr_reg;
    assign debug_illegal = illegal_instr;
    assign debug_mem_addr = mem_addr;
    assign debug_mem_wdata = mem_wdata;
    assign debug_mem_rdata = mem_rdata;
    assign debug_mem_wstrb = mem_wstrb;
    assign debug_display_mem_data = mem_data_display;

    assign rs1_addr = instr_reg[19:15];
    assign rs2_addr = instr_reg[24:20];
    assign rd_addr  = instr_reg[11:7];
    assign opcode   = instr_reg[6:0];
    assign funct3   = instr_reg[14:12];
    assign funct7   = instr_reg[31:25];

    assign alu_src_a_data = (alu_src_a == ALU_SRC_A_PC)   ? instr_pc_reg :
                            (alu_src_a == ALU_SRC_A_ZERO) ? 32'b0 :
                                                             rs1_data;

    assign alu_src_b_data = (alu_src_b == ALU_SRC_B_IMM) ? imm : rs2_data;

    assign is_rtype_shift = (opcode == 7'b0110011) && ((funct3 == 3'b001) || (funct3 == 3'b101));
    assign is_itype_shift = (opcode == 7'b0010011) && ((funct3 == 3'b001) || (funct3 == 3'b101));

    assign alu_exec_src1 = is_rtype_shift ? rs2_data :
                           is_itype_shift ? {27'b0, instr_reg[24:20]} :
                                            alu_src_a_data;

    assign alu_exec_src2 = is_rtype_shift ? rs1_data :
                           is_itype_shift ? rs1_data :
                                            alu_src_b_data;

    assign branch_target = instr_pc_reg + imm;
    assign jump_target = (opcode == OPCODE_JALR) ? ((rs1_data + imm) & 32'hffff_fffe) : (instr_pc_reg + imm);

    assign mem_addr = rs1_data + imm;
    assign mem_wdata = (funct3 == 3'b000) ? {4{rs2_data[7:0]}} :
                       (funct3 == 3'b001) ? {2{rs2_data[15:0]}} :
                                            rs2_data;

    assign load_byte = (mem_addr[1:0] == 2'b00) ? mem_data_reg[7:0] :
                       (mem_addr[1:0] == 2'b01) ? mem_data_reg[15:8] :
                       (mem_addr[1:0] == 2'b10) ? mem_data_reg[23:16] :
                                                   mem_data_reg[31:24];

    assign load_half = mem_addr[1] ? mem_data_reg[31:16] : mem_data_reg[15:0];

    assign load_data = (funct3 == 3'b000) ? {{24{load_byte[7]}}, load_byte} :
                       (funct3 == 3'b001) ? {{16{load_half[15]}}, load_half} :
                       (funct3 == 3'b010) ? mem_data_reg :
                       (funct3 == 3'b100) ? {24'b0, load_byte} :
                       (funct3 == 3'b101) ? {16'b0, load_half} :
                                            mem_data_reg;

    assign wb_data = (wb_sel == WB_MEM) ? load_data :
                     (wb_sel == WB_PC4) ? pc_plus4_instr :
                                          alu_result;

    assign branch_taken = (opcode == OPCODE_BRANCH) ?
                          ((funct3 == 3'b000) ? (rs1_data == rs2_data) :
                           (funct3 == 3'b001) ? (rs1_data != rs2_data) :
                           (funct3 == 3'b100) ? ($signed(rs1_data) < $signed(rs2_data)) :
                           (funct3 == 3'b101) ? ($signed(rs1_data) >= $signed(rs2_data)) :
                           (funct3 == 3'b110) ? (rs1_data < rs2_data) :
                           (funct3 == 3'b111) ? (rs1_data >= rs2_data) :
                                                1'b0) :
                          1'b0;

    assign mem_wstrb = (funct3 == 3'b000) ? (4'b0001 << mem_addr[1:0]) :
                       (funct3 == 3'b001) ? (mem_addr[1] ? 4'b1100 : 4'b0011) :
                       4'b1111;

    pc_reg u_pc_reg(
        .clk(clk),
        .reset(reset),
        .write_en(pc_write),
        .next_pc((pc_source == PC_PLUS4)  ? pc_plus4_fetch :
                 (pc_source == PC_BRANCH) ? branch_target :
                                            jump_target),
        .pc(pc)
    );

    instr_mem #(
        .MEM_DEPTH(IMEM_DEPTH),
        .ADDR_WIDTH(IMEM_ADDR_WIDTH),
        .INIT_FILE(IMEM_INIT_FILE)
    ) u_instr_mem (
        .clk(clk),
        .addr(pc),
        .instr(instr_word)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            instr_reg <= 32'h00000013;
            instr_pc_reg <= 32'b0;
        end else if (ir_write) begin
            instr_reg <= instr_word;
            instr_pc_reg <= pc;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset)
            mem_data_reg <= 32'b0;
        else if (mem_rvalid)
            mem_data_reg <= mem_rdata;
    end

    regfile u_regfile(
        .clk(clk),
        .reset(reset),
        .write_en(reg_write),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .rd_data(wb_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    imm_gen u_imm_gen(
        .instr(instr_reg),
        .imm_type(imm_type),
        .imm(imm)
    );

    alu_control u_alu_control(
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .alu_control(alu_ctrl),
        .illegal_instr(alu_decode_illegal)
    );

    alu_wrapper u_alu_wrapper(
        .clk(clk),
        .reset(reset),
        .req_valid(exec_req),
        .flush(1'b0),
        .alu_control(alu_ctrl),
        .src1(alu_exec_src1),
        .src2(alu_exec_src2),
        .result(alu_result),
        .ready(alu_req_ready),
        .result_valid(alu_result_valid),
        .busy(alu_busy),
        .illegal_op(alu_illegal_op),
        .div_by_zero(alu_div_by_zero)
    );

    data_mem #(
        .MEM_DEPTH(DMEM_DEPTH),
        .ADDR_WIDTH(DMEM_ADDR_WIDTH)
    ) u_data_mem (
        .clk(clk),
        .reset(reset),
        .req(mem_req),
        .write_en(mem_write_en),
        .addr(mem_addr),
        .wdata(mem_wdata),
        .wstrb(mem_wstrb),
        .rdata(mem_rdata),
        .ready(mem_ready),
        .rvalid(mem_rvalid),
        .wdone(mem_wdone),
        .mem_addr(mem_addr),
        .mem_data(mem_data_display)
    );

    main_control u_main_control(
        .clk(clk),
        .reset(reset),
        .opcode(opcode),
        .funct3(funct3),
        .alu_decode_illegal(alu_decode_illegal),
        .exec_ready(alu_req_ready),
        .exec_done(alu_result_valid),
        .mem_ready(mem_ready),
        .mem_rvalid(mem_rvalid),
        .mem_wdone(mem_wdone),
        .branch_taken(branch_taken),
        .ir_write(ir_write),
        .pc_write(pc_write),
        .pc_source(pc_source),
        .reg_write(reg_write),
        .exec_req(exec_req),
        .mem_req(mem_req),
        .mem_write_en(mem_write_en),
        .wb_sel(wb_sel),
        .alu_src_a(alu_src_a),
        .alu_src_b(alu_src_b),
        .imm_type(imm_type),
        .illegal_instr(illegal_instr),
        .state_dbg(debug_state),
        .irq_sample_en(irq_sample_en)
    );

endmodule
