`timescale 1ns / 1ps

module cpu_fetch(
    input         clk,
    input         reset,
    input         if_valid,         // 模块使能（来自 controller STATE_FETCH）
    input         init_sig,         // Bus4LZU 初始化暂停信号，高有效时冻结取指
    input  [31:0] pc,               // PC 计数器
    input  [31:0] instData_32,      // 从总线/Bus4LZU 返回的指令数据（1周期延迟）
    output [31:0] instAddr_32,      // 发给总线的取指地址（字节地址 = PC）
    output        if_done,          // 取指完成：发地址后的第2个周期置1
    output [95:0] if_id_bus,        // 数据总线 {pc_plus4, pc, inst_data}

    // display展示用
    output [31:0] if_pc,
    output [31:0] if_inst
);

    wire [31:0] pc_plus4;
    assign pc_plus4 = pc + 32'd4;
    assign instAddr_32 = pc;

    // 等待标志：记录是否已经在当前 if_valid 周期发了地址
    // 0 = 刚进入 FETCH，需要发地址并等待1周期
    // 1 = 已经发过地址，下一周期 instData_32 有效
    reg r_wait;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_wait <= 1'b0;
        end else if (init_sig) begin
            // 初始化期间冻结：强制清0，if_done 永不为1
            r_wait <= 1'b0;
        end else if (if_valid) begin
            // 在 FETCH 状态每周期翻转
            // 第1周期：r_wait=0 -> if_done=0，下一周期 r_wait=1
            // 第2周期：r_wait=1 -> if_done=1，下一周期 r_wait=0
            r_wait <= ~r_wait;
        end else begin
            // if_valid 为 0 时（controller 离开 FETCH），重置等待标志
            r_wait <= 1'b0;
        end
    end

    // 取指完成：只有在第2周期（r_wait==1）时才置1
    assign if_done = if_valid && r_wait;

    // if_id_bus 在第一周期输出旧数据，但 controller 只在 if_done 时采样
    // 第二周期 instData_32 已更新，采样正确
    assign if_id_bus = {pc_plus4, pc, instData_32};

    assign if_pc = pc;
    assign if_inst = instData_32;

endmodule
