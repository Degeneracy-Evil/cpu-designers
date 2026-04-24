`timescale 1ns / 1ps

module cpu_fetch(
    input         if_valid,         // 模块使能
    input  [31:0] pc,               // pc计数器进线
    input  [31:0] inst_data,        //
    output        icache_en,        // icache使能
    output [10:0] icache_addr,      // 地址
    output        if_done,          // 完成
    output [63:0] if_id_bus,        // 数据总线

    // display展示用
    output [31:0] if_pc,            // pc输出
    output [31:0] if_inst           //
);

    assign icache_en = if_valid;
    assign icache_addr = pc[12:2];

    assign if_done = if_valid;
    assign if_id_bus = {pc, inst_data};

    assign if_pc = pc;
    assign if_inst = inst_data;

endmodule
