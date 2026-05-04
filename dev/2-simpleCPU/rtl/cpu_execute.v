`timescale 1ns / 1ps

module cpu_execute(
    input              clk,
    input              reset,
    input              exe_valid,
    input      [291:0] id_exe_bus_r,
    output             exe_done,
    output     [173:0] exe_mem_bus,
    output             exe_branch_taken,
    output     [31:0]  exe_branch_target,
    output             exe_is_ctrl_flow,
    output             exe_is_branch,

    output     [31:0]  exe_pc,
    output     [31:0]  exe_inst
);

    wire valid_inst;
    wire is_alu;
    wire is_load;
    wire is_store;
    wire is_jal_like;
    wire is_branch;
    wire use_fixed_wb;
    wire wb_we;
    wire [4:0] wb_rd;
    wire [31:0] wb_fixed_data;
    wire [2:0] mem_size;
    wire mem_unsigned;
    wire [15:0] alu_control;
    wire [31:0] alu_src1;
    wire [31:0] alu_src2;
    wire [31:0] rs1_value;
    wire [31:0] rs2_value;
    wire [2:0]  branch_funct3;
    wire [31:0] pc_plus4;
    wire [31:0] pc;
    wire [31:0] inst;

    assign {
        pc_plus4,
        valid_inst,
        is_alu,
        is_load,
        is_store,
        is_jal_like,
        is_branch,
        use_fixed_wb,
        wb_we,
        wb_rd,
        wb_fixed_data,
        mem_size,
        mem_unsigned,
        alu_control,
        alu_src1,
        alu_src2,
        rs1_value,
        rs2_value,
        branch_funct3,
        pc,
        inst
    } = id_exe_bus_r;

    wire is_jalr;
    assign is_jalr = (inst[6:0] == 7'b1100111) && (inst[14:12] == 3'b000);

    wire branch_cond_true; // 比较结果
    branch_comparator u_cmp(
        .rs1_value(rs1_value),
        .rs2_value(rs2_value),
        .branch_funct3(branch_funct3),
        .branch_cond_true(branch_cond_true)
    );

    reg req_valid;
    reg result_ready;
    reg exe_active;
    reg exe_seen_valid;

    wire [31:0] alu_result;
    wire alu_busy;
    wire alu_ready;
    wire result_valid;
    wire illegal_op;
    wire div_by_zero;

    alu_32bit u_alu(
        .clk(clk),
        .reset(reset),
        .alu_control(alu_control),
        .src1(alu_src1),
        .src2(alu_src2),
        .req_valid(req_valid),
        .flush(1'b0),
        .result_ready(result_ready),
        .result(alu_result),
        .alu_busy(alu_busy),
        .alu_ready(alu_ready),
        .result_valid(result_valid),
        .illegal_op(illegal_op),
        .div_by_zero(div_by_zero)
    );

    reg [31:0] result_reg;
    reg        result_ok;
    reg        done_reg;
    reg [31:0] branch_target_reg;
    reg        branch_taken_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            req_valid <= 1'b0;
            result_ready <= 1'b0;
            exe_active <= 1'b0;
            exe_seen_valid <= 1'b0;
            result_reg <= 32'b0;
            result_ok <= 1'b0;
            done_reg <= 1'b0;
            branch_target_reg <= 32'b0;
            branch_taken_reg <= 1'b0;
        end else begin
            done_reg <= 1'b0;
            result_ready <= 1'b0;

            if (!exe_valid) begin
                exe_seen_valid <= 1'b0;
            end

            if (!exe_active && exe_valid && !exe_seen_valid) begin
                if (use_fixed_wb) begin
                    result_reg <= wb_fixed_data;
                    result_ok <= valid_inst;
                    done_reg <= 1'b1;
                    exe_seen_valid <= 1'b1;
                    branch_target_reg <= 32'b0;
                    branch_taken_reg <= 1'b0;
                end else begin
                    req_valid <= 1'b1;
                    exe_active <= 1'b1;
                    exe_seen_valid <= 1'b1;
                end
            end

            if (exe_active) begin
                if (req_valid && alu_ready) begin
                    req_valid <= 1'b0;
                end
                if (result_valid) begin
                    result_ready <= 1'b1;
                    result_reg <= alu_result;
                    result_ok <= valid_inst && !illegal_op;
                    done_reg <= 1'b1;
                    exe_active <= 1'b0;
                    req_valid <= 1'b0;
                    branch_target_reg <= is_jalr ? (alu_result & 32'hffff_fffc) : alu_result;
                    branch_taken_reg <= is_branch ? branch_cond_true : is_jal_like;
                end
            end
        end
    end

    assign exe_done = done_reg;
    assign exe_branch_taken = branch_taken_reg;
    assign exe_branch_target = branch_target_reg;
    assign exe_is_ctrl_flow = is_branch | is_jal_like;
    assign exe_is_branch = is_branch;

    assign exe_mem_bus = {
        pc_plus4,
        result_ok,
        is_jal_like,
        is_load,
        is_store,
        wb_we,
        wb_rd,
        result_reg,
        mem_size,
        mem_unsigned,
        rs2_value,
        pc,
        inst
    };

    assign exe_pc = pc;
    assign exe_inst = inst;

endmodule
