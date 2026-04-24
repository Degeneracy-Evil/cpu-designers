`timescale 1ns / 1ps

module simple_cpu_top(
    input         clk,
    input         reset,

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
    output [31:0] display_state,

    input         uart_rx_pin,
    output        uart_tx_pin
);

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
    wire csr_valid;
    wire trap_enter_valid;
    wire trap_return_valid;
    wire [3:0] fsm_state;

    wire dec_is_branch;
    wire dec_need_exe;
    wire dec_illegal;
    wire dec_is_csr;
    wire dec_is_ecall;
    wire dec_is_ebreak;
    wire dec_is_mret;
    wire dec_is_fence;
    wire [11:0] dec_csr_addr;
    wire [2:0]  dec_csr_funct3;
    wire dec_csr_addr_valid;

    wire exe_branch_taken;
    wire [31:0] exe_branch_target;
    wire exe_is_ctrl_flow;
    wire exe_is_branch;

    wire [95:0]  if_id_bus;
    wire [315:0] id_exe_bus;
    wire [206:0] exe_mem_bus;
    wire [167:0] mem_wb_bus;

    reg [95:0]  if_id_bus_r;
    reg [315:0] id_exe_bus_r;
    reg [206:0] exe_mem_bus_r;
    reg [167:0] mem_wb_bus_r;

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
    wire wb_is_jal_like;

    wire [31:0] id_pc_plus4;
    wire [31:0] exe_pc_plus4;
    wire [31:0] wb_pc_plus4;

    assign id_pc_plus4  = if_id_bus_r[95:64];
    assign exe_pc_plus4 = id_exe_bus_r[315:284];
    assign wb_pc_plus4  = mem_wb_bus_r[167:136];

    wire [31:0] actual_rf_wdata;
    assign actual_rf_wdata = wb_is_jal_like ? wb_pc_plus4 : rf_wdata;

    wire exe_csr_wen;
    wire [11:0] exe_csr_waddr;
    wire [31:0] exe_csr_wdata;
    wire [31:0] exe_csr_old_val;

    wire [31:0] csr_read_data;
    wire csr_addr_valid_out;

    wire [31:0] csr_mstatus;
    wire [31:0] csr_mie;
    wire [31:0] csr_mtvec;
    wire [31:0] csr_mscratch;
    wire [31:0] csr_mepc;
    wire [31:0] csr_mcause;
    wire [31:0] csr_mtval;
    wire [31:0] csr_mip;

    wire hw_csr_wen;
    wire [31:0] hw_mepc_wdata;
    wire [31:0] hw_mcause_wdata;
    wire [31:0] hw_mtval_wdata;
    wire [31:0] hw_mstatus_wdata;

    wire clint_trap_enter;
    wire clint_trap_return;
    wire [31:0] clint_trap_pc;

    wire mem_misalign_load;
    wire mem_misalign_store;
    wire [31:0] mem_misalign_addr;

    wire [31:0] id_pc_wire;
    wire [31:0] id_inst_wire;

    wire exception_at_decode;
    assign exception_at_decode = (id_valid && id_done) && (dec_illegal || dec_is_ecall || dec_is_ebreak);

    wire [31:0] decode_exception_cause;
    assign decode_exception_cause = dec_illegal  ? {1'b0, 27'd0, 5'd2} :
                                    dec_is_ecall ? {1'b0, 27'd0, 5'd11} :
                                    {1'b0, 27'd0, 5'd3};

    wire [31:0] decode_exception_mtval;
    assign decode_exception_mtval = dec_illegal ? id_inst_wire : 32'b0;

    reg exception_valid_r;
    reg [31:0] exception_cause_r;
    reg [31:0] exception_pc_r;
    reg [31:0] exception_mtval_r;

    wire misalign_exception_valid;
    wire [31:0] misalign_exception_cause;
    wire [31:0] misalign_exception_pc;
    wire [31:0] misalign_exception_mtval;

    assign misalign_exception_valid = mem_valid && mem_done && (mem_misalign_load || mem_misalign_store);
    assign misalign_exception_cause = mem_misalign_load  ? {1'b0, 27'd0, 5'd4} :
                                      {1'b0, 27'd0, 5'd6};
    assign misalign_exception_pc    = mem_pc;
    assign misalign_exception_mtval = mem_misalign_addr;

    wire exception_valid;
    wire [31:0] exception_cause;
    wire [31:0] exception_pc;
    wire [31:0] exception_mtval;

    assign exception_valid = exception_at_decode || misalign_exception_valid;
    assign exception_cause = exception_at_decode ? decode_exception_cause : misalign_exception_cause;
    assign exception_pc   = exception_at_decode ? id_pc_wire : misalign_exception_pc;
    assign exception_mtval= exception_at_decode ? decode_exception_mtval : misalign_exception_mtval;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            exception_valid_r <= 1'b0;
            exception_cause_r <= 32'b0;
            exception_pc_r    <= 32'b0;
            exception_mtval_r <= 32'b0;
        end else begin
            if (exception_valid) begin
                exception_valid_r <= exception_valid;
                exception_cause_r <= exception_cause;
                exception_pc_r    <= exception_pc;
                exception_mtval_r <= exception_mtval;
            end else if (trap_enter_valid || trap_return_valid) begin
                exception_valid_r <= 1'b0;
            end
        end
    end

    wire trap_pending;
    assign trap_pending = clint_trap_enter && !exception_valid_r;

    wire uart_rx_valid;
    wire [31:0] uart_read_data;

    wire [11:0] csr_sw_addr;
    wire csr_sw_wen;
    wire [31:0] csr_sw_wdata;

    wire [2:0] csr_funct3_bus;
    wire [4:0] csr_uimm_bus;
    wire [4:0] csr_rs1_bus;
    wire [31:0] csr_rs1_val_bus;
    wire [4:0] csr_rd_bus;
    wire [31:0] csr_pc_plus4_bus;
    wire [31:0] csr_pc_bus;
    wire [31:0] csr_inst_bus;

    assign csr_funct3_bus   = id_exe_bus_r[71:69];
    assign csr_uimm_bus    = id_exe_bus_r[68:64];
    assign csr_rs1_bus     = id_exe_bus_r[275:271];
    assign csr_rs1_val_bus = id_exe_bus_r[154:123];
    assign csr_rd_bus      = id_exe_bus_r[275:271];
    assign csr_pc_plus4_bus= id_exe_bus_r[315:284];
    assign csr_pc_bus      = id_exe_bus_r[63:32];
    assign csr_inst_bus    = id_exe_bus_r[31:0];

    wire [31:0] csr_new_val;
    assign csr_new_val = (csr_funct3_bus == 3'b001) ? csr_rs1_val_bus :
                         (csr_funct3_bus == 3'b010) ? (csr_read_data | csr_rs1_val_bus) :
                         (csr_funct3_bus == 3'b011) ? (csr_read_data & ~csr_rs1_val_bus) :
                         (csr_funct3_bus == 3'b101) ? {27'b0, csr_uimm_bus} :
                         (csr_funct3_bus == 3'b110) ? (csr_read_data | {27'b0, csr_uimm_bus}) :
                         (csr_funct3_bus == 3'b111) ? (csr_read_data & ~{27'b0, csr_uimm_bus}) :
                         csr_read_data;

    wire csr_no_write;
    assign csr_no_write = ((csr_funct3_bus == 3'b010 || csr_funct3_bus == 3'b011) && (csr_rs1_bus == 5'd0)) ||
                          ((csr_funct3_bus == 3'b110 || csr_funct3_bus == 3'b111) && (csr_uimm_bus == 5'd0));

    assign csr_sw_addr  = dec_csr_addr;
    assign csr_sw_wen   = csr_valid && !csr_no_write;
    assign csr_sw_wdata = csr_new_val;

    wire [167:0] csr_wb_bus;
    assign csr_wb_bus = {csr_pc_plus4_bus, 1'b0, 1'b1, 1'b1, csr_rd_bus, csr_read_data, csr_read_data, csr_pc_bus, csr_inst_bus};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 32'b0;
            if_id_bus_r <= 96'b0;
            id_exe_bus_r <= 316'b0;
            exe_mem_bus_r <= 207'b0;
            mem_wb_bus_r <= 168'b0;
        end else begin
            if (if_done) begin
                if_id_bus_r <= if_id_bus;
            end
            if (id_done && (dec_need_exe || dec_is_csr)) begin
                id_exe_bus_r <= id_exe_bus;
            end
            if (exe_done) begin
                exe_mem_bus_r <= exe_mem_bus;
            end
            if (mem_done) begin
                mem_wb_bus_r <= mem_wb_bus;
            end
            if (csr_valid) begin
                mem_wb_bus_r <= csr_wb_bus;
            end

            if (trap_enter_valid) begin
                pc <= clint_trap_pc;
            end else if (trap_return_valid) begin
                pc <= clint_trap_pc;
            end else if (exe_valid && exe_done) begin
                if (exe_is_ctrl_flow && exe_branch_taken) begin
                    pc <= exe_branch_target;
                end else begin
                    pc <= exe_pc_plus4;
                end
            end else if (csr_valid) begin
                pc <= csr_pc_plus4_bus;
            end else if (id_valid && id_done && dec_is_fence) begin
                pc <= id_pc_plus4;
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
        .dec_is_csr(dec_is_csr),
        .dec_is_ecall(dec_is_ecall),
        .dec_is_ebreak(dec_is_ebreak),
        .dec_is_mret(dec_is_mret),
        .dec_is_fence(dec_is_fence),
        .exe_is_branch(exe_is_branch),
        .trap_pending(trap_pending),
        .exception_at_decode(exception_at_decode),
        .if_valid(if_valid),
        .id_valid(id_valid),
        .exe_valid(exe_valid),
        .mem_valid(mem_valid),
        .wb_valid(wb_valid),
        .csr_valid(csr_valid),
        .trap_enter_valid(trap_enter_valid),
        .trap_return_valid(trap_return_valid),
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
        .dec_is_branch(dec_is_branch),
        .dec_need_exe(dec_need_exe),
        .id_exe_bus(id_exe_bus),
        .id_pc(id_pc_wire),
        .id_inst(id_inst_wire),
        .dec_is_csr(dec_is_csr),
        .dec_is_ecall(dec_is_ecall),
        .dec_is_ebreak(dec_is_ebreak),
        .dec_is_mret(dec_is_mret),
        .dec_is_fence(dec_is_fence),
        .dec_csr_addr(dec_csr_addr),
        .dec_csr_funct3(dec_csr_funct3),
        .dec_csr_addr_valid(dec_csr_addr_valid)
    );

    cpu_execute u_execute(
        .clk(clk),
        .reset(reset),
        .exe_valid(exe_valid),
        .id_exe_bus_r(id_exe_bus_r),
        .csr_rdata(csr_read_data),
        .exe_done(exe_done),
        .exe_mem_bus(exe_mem_bus),
        .exe_branch_taken(exe_branch_taken),
        .exe_branch_target(exe_branch_target),
        .exe_is_ctrl_flow(exe_is_ctrl_flow),
        .exe_is_branch(exe_is_branch),
        .exe_pc(exe_pc),
        .exe_inst(exe_inst),
        .exe_csr_wen(exe_csr_wen),
        .exe_csr_waddr(exe_csr_waddr),
        .exe_csr_wdata(exe_csr_wdata),
        .exe_csr_old_val(exe_csr_old_val)
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
        .mem_inst(mem_inst),
        .mem_misalign_load(mem_misalign_load),
        .mem_misalign_store(mem_misalign_store),
        .mem_misalign_addr(mem_misalign_addr)
    );

    cpu_wb u_wb(
        .wb_valid(wb_valid),
        .mem_wb_bus_r(mem_wb_bus_r),
        .rf_wen(rf_wen),
        .rf_waddr(rf_waddr),
        .rf_wdata(rf_wdata),
        .wb_done(wb_done),
        .wb_is_jal_like(wb_is_jal_like),
        .wb_pc_plus4(wb_pc_plus4),
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
        .wdata(actual_rf_wdata),
        .rdata1(rs1_value),
        .rdata2(rs2_value),
        .dbg_raddr(rf_addr),
        .dbg_rdata(rf_data)
    );

    cpu_csr u_csr(
        .clk(clk),
        .reset(reset),
        .sw_csr_addr(csr_sw_addr),
        .sw_csr_wen(csr_sw_wen),
        .sw_csr_wdata(csr_sw_wdata),
        .sw_csr_rdata(csr_read_data),
        .csr_addr_valid(csr_addr_valid_out),
        .hw_csr_wen(hw_csr_wen),
        .hw_mepc_wdata(hw_mepc_wdata),
        .hw_mcause_wdata(hw_mcause_wdata),
        .hw_mtval_wdata(hw_mtval_wdata),
        .hw_mstatus_wdata(hw_mstatus_wdata),
        .ext_meip(uart_rx_valid),
        .ext_msip(1'b0),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mtvec(csr_mtvec),
        .csr_mscratch(csr_mscratch),
        .csr_mepc(csr_mepc),
        .csr_mcause(csr_mcause),
        .csr_mtval(csr_mtval),
        .csr_mip(csr_mip)
    );

    cpu_clint u_clint(
        .clk(clk),
        .reset(reset),
        .exception_valid(exception_valid_r),
        .exception_cause(exception_cause_r),
        .exception_pc(exception_pc_r),
        .exception_mtval(exception_mtval_r),
        .mret_req(trap_return_valid),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mtvec(csr_mtvec),
        .csr_mepc(csr_mepc),
        .csr_mip(csr_mip),
        .trap_enter(clint_trap_enter),
        .trap_return(clint_trap_return),
        .trap_pc(clint_trap_pc),
        .hw_csr_wen(),
        .hw_mepc_wdata(hw_mepc_wdata),
        .hw_mcause_wdata(hw_mcause_wdata),
        .hw_mtval_wdata(hw_mtval_wdata),
        .hw_mstatus_wdata(hw_mstatus_wdata)
    );

    assign hw_csr_wen = trap_enter_valid || trap_return_valid;

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

    uart_top u_uart(
        .clk(clk),
        .reset(reset),
        .i_cs_1(1'b1),
        .i_rw_1(1'b0),
        .i_addr_32(32'h0),
        .i_wrData_32(32'b0),
        .i_rx_1(uart_rx_pin),
        .o_rdData_32(uart_read_data),
        .o_rxDataValid_1(uart_rx_valid),
        .o_tx_1(uart_tx_pin)
    );

    assign display_state = {28'b0, fsm_state};

    assign id_pc   = id_pc_wire;
    assign id_inst = id_inst_wire;

endmodule
