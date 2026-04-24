`timescale 1ns / 1ps

module simple_cpu_top(
    input         clk,
    input         reset,

    // 用于display的信号
    input  [4:0]  rf_addr,
    input  [31:0] mem_addr,
    output [31:0] rf_data,
    output [31:0] mem_data,
    output [31:0] if_pc,
    output [31:0] if_inst,
    output [31:0] id_pc,
    output [31:0] id_inst,
    output [31:0] exe_pc,
    output [31:0] exe_inst,
    output [31:0] mem_pc,
    output [31:0] mem_inst,
    output [31:0] wb_pc,
    output [31:0] wb_inst,
    output [31:0] display_state
);

    localparam OPCODE_JAL  = 7'b1101111;
    localparam OPCODE_JALR = 7'b1100111;

    reg [31:0] pc;

    wire if_done;
    wire id_done;
    wire exe_done;
    wire mem_done;
    wire wb_done;

    wire if_valid;
    wire id_valid;
    wire exe_valid;
    wire mem_valid;
    wire wb_valid;
    wire [2:0] fsm_state;

    wire dec_is_branch;
    wire dec_is_ctrl_flow;
    wire dec_is_jal_like;
    wire dec_need_exe;
    wire dec_illegal;

    wire branch_taken;
    wire [31:0] branch_target;

    wire [63:0] if_id_bus;
    wire [223:0] id_exe_bus;
    wire [140:0] exe_mem_bus;
    wire [101:0] mem_wb_bus;

    reg [63:0] if_id_bus_r;
    reg [223:0] id_exe_bus_r;
    reg [140:0] exe_mem_bus_r;
    reg [101:0] mem_wb_bus_r;

    wire icache_en;
    wire [10:0] icache_addr;
    wire [31:0] icache_dout;

    wire dcache_en;
    wire [0:0] dcache_we;
    wire [10:0] dcache_addr;
    wire [31:0] dcache_wdata;
    wire [31:0] dcache_rdata;

    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [31:0] rs1_value;
    wire [31:0] rs2_value;

    wire rf_wen;
    wire [4:0] rf_waddr;
    wire [31:0] rf_wdata;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 32'b0;
            if_id_bus_r <= 64'b0;
            id_exe_bus_r <= 224'b0;
            exe_mem_bus_r <= 141'b0;
            mem_wb_bus_r <= 102'b0;
        end else begin
            if (if_done) begin
                if_id_bus_r <= if_id_bus;
            end
            if (id_done && dec_need_exe) begin
                id_exe_bus_r <= id_exe_bus;
            end
            if (exe_done) begin
                exe_mem_bus_r <= exe_mem_bus;
            end
            if (mem_done) begin
                mem_wb_bus_r <= mem_wb_bus;
            end

            if (id_valid && id_done) begin
                if (dec_is_ctrl_flow) begin
                    if (branch_taken) begin
                        if (dec_is_jal_like) begin
                            pc <= branch_target & 32'hffff_fffc;
                        end else begin
                            pc <= branch_target;
                        end
                    end else begin
                        pc <= pc + 32'd4;
                    end
                end else if (dec_illegal) begin // 错误指令，暂时未处理
                    pc <= pc + 32'd4;
                end
            end

            if (wb_valid && wb_done) begin
                if ((wb_inst[6:0] != OPCODE_JAL) && (wb_inst[6:0] != OPCODE_JALR)) begin
                    pc <= pc + 32'd4;
                end
            end
        end
    end

    cpu_controller u_ctrl(
        .clk(clk),
        .reset(reset),
        .if_done(if_done),
        .id_done(id_done),
        .exe_done(exe_done),
        .mem_done(mem_done),
        .wb_done(wb_done),
        .dec_is_branch(dec_is_branch),
        .dec_need_exe(dec_need_exe),
        .dec_illegal(dec_illegal),
        .if_valid(if_valid),
        .id_valid(id_valid),
        .exe_valid(exe_valid),
        .mem_valid(mem_valid),
        .wb_valid(wb_valid),
        .state(fsm_state)
    );

    cpu_fetch u_fetch(
        .if_valid(if_valid),
        .pc(pc),
        .inst_data(icache_dout),
        .icache_en(icache_en),
        .icache_addr(icache_addr),
        .if_done(if_done),
        .if_id_bus(if_id_bus),
        .if_pc(if_pc),
        .if_inst(if_inst)
    );

    cpu_decode u_decode(
        .id_valid(id_valid),
        .if_id_bus_r(if_id_bus_r),
        .rs1_value(rs1_value),
        .rs2_value(rs2_value),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .id_done(id_done),
        .illegal_inst(dec_illegal),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .dec_is_branch(dec_is_branch),
        .dec_is_ctrl_flow(dec_is_ctrl_flow),
        .dec_is_jal_like(dec_is_jal_like),
        .dec_need_exe(dec_need_exe),
        .id_exe_bus(id_exe_bus),
        .id_pc(id_pc),
        .id_inst(id_inst)
    );

    cpu_execute u_execute(
        .clk(clk),
        .reset(reset),
        .exe_valid(exe_valid),
        .id_exe_bus_r(id_exe_bus_r),
        .exe_done(exe_done),
        .exe_mem_bus(exe_mem_bus),
        .exe_pc(exe_pc),
        .exe_inst(exe_inst)
    );

    cpu_mem u_mem(
        .clk(clk),
        .reset(reset),
        .mem_valid(mem_valid),
        .exe_mem_bus_r(exe_mem_bus_r),
        .dcache_en(dcache_en),
        .dcache_we(dcache_we),
        .dcache_addr(dcache_addr),
        .dcache_wdata(dcache_wdata),
        .dcache_rdata(dcache_rdata),
        .mem_done(mem_done),
        .mem_wb_bus(mem_wb_bus),
        .mem_pc(mem_pc),
        .mem_inst(mem_inst)
    );

    cpu_wb u_wb(
        .wb_valid(wb_valid),
        .mem_wb_bus_r(mem_wb_bus_r),
        .rf_wen(rf_wen),
        .rf_waddr(rf_waddr),
        .rf_wdata(rf_wdata),
        .wb_done(wb_done),
        .wb_pc(wb_pc),
        .wb_inst(wb_inst)
    );

    cpu_regfile u_regfile(
        .clk(clk),
        .reset(reset),
        .wen(rf_wen),
        .raddr1(rs1_addr),
        .raddr2(rs2_addr),
        .waddr(rf_waddr),
        .wdata(rf_wdata),
        .rdata1(rs1_value),
        .rdata2(rs2_value),
        .dbg_raddr(rf_addr),
        .dbg_rdata(rf_data)
    );

    icache u_icache(
        .clka(clk),
        .ena(icache_en),
        .wea(1'b0),
        .addra(icache_addr),
        .dina(32'b0),
        .douta(icache_dout),
        .clkb(clk),
        .enb(1'b0),
        .web(1'b0),
        .addrb(11'b0),
        .dinb(32'b0),
        .doutb()
    );

    dcache u_dcache(
        .clka(clk),
        .ena(dcache_en),
        .wea(dcache_we),
        .addra(dcache_addr),
        .dina(dcache_wdata),
        .douta(dcache_rdata),
        .clkb(clk),
        .enb(1'b1),
        .web(1'b0),
        .addrb(mem_addr[12:2]),
        .dinb(32'b0),
        .doutb(mem_data)
    );

    assign display_state = {29'b0, fsm_state};

endmodule
