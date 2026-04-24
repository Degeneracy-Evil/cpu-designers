`timescale 1ns / 1ps
//*************************************************************************
//   > 文件名: simple_cpu_display.v
//   > 描述  : 简单CPU显示模块，调用FPGA板上的IO接口和触摸屏
//   > 作者  : CPU Designers
//   > 日期  : 2026年4月24日
//   > 说明  : 适配dev/2-simpleCPU中的simple_cpu_top模块到FPGA调试
//*************************************************************************
module simple_cpu_display(
    input         clk,
    input         resetn,

    input         btn_clk,

    input  [7:0]  sw,

    output        lcd_rst,
    output        lcd_cs,
    output        lcd_rs,
    output        lcd_wr,
    output        lcd_rd,
    inout  [15:0] lcd_data_io,
    output        lcd_bl_ctr,
    inout         ct_int,
    inout         ct_sda,
    output        ct_scl,
    output        ct_rstn
);

//-----{时钟和复位信号}begin
    wire cpu_clk;
    reg  btn_clk_r1;
    reg  btn_clk_r2;
    always @(posedge clk)
    begin
        if (!resetn)
        begin
            btn_clk_r1 <= 1'b0;
        end
        else
        begin
            btn_clk_r1 <= ~btn_clk;
        end
        btn_clk_r2 <= btn_clk_r1;
    end

    wire clk_en;
    assign clk_en = !resetn || (!btn_clk_r1 && btn_clk_r2);
    BUFGCE cpu_clk_cg(.I(clk), .CE(clk_en), .O(cpu_clk));

    wire reset;
    assign reset = ~resetn;
//-----{时钟和复位信号}end

//-----{调用简单CPU模块}begin
    wire [ 4:0] rf_addr;
    wire [31:0] rf_data;
    reg  [31:0] mem_addr;
    wire [31:0] mem_data;
    wire [31:0] if_pc;
    wire [31:0] if_inst;
    wire [31:0] id_pc;
    wire [31:0] id_inst;
    wire [31:0] exe_pc;
    wire [31:0] exe_inst;
    wire [31:0] mem_pc;
    wire [31:0] mem_inst;
    wire [31:0] wb_pc;
    wire [31:0] wb_inst;
    wire [31:0] display_state;

    simple_cpu_top cpu(
        .clk          (cpu_clk      ),
        .reset        (reset        ),
        .rf_addr      (rf_addr      ),
        .mem_addr     (mem_addr     ),
        .rf_data      (rf_data      ),
        .mem_data     (mem_data     ),
        .if_pc        (if_pc        ),
        .if_inst      (if_inst      ),
        .id_pc        (id_pc        ),
        .id_inst      (id_inst      ),
        .exe_pc       (exe_pc       ),
        .exe_inst     (exe_inst     ),
        .mem_pc       (mem_pc       ),
        .mem_inst     (mem_inst     ),
        .wb_pc        (wb_pc        ),
        .wb_inst      (wb_inst      ),
        .display_state(display_state)
    );
//-----{调用简单CPU模块}end

//---------------------{调用触摸屏模块}begin--------------------//
//-----{实例化触摸屏}begin
    reg         display_valid;
    reg  [39:0] display_name;
    reg  [31:0] display_value;
    wire [5 :0] display_number;
    wire        input_valid;
    wire [31:0] input_value;

    lcd_module lcd_module(
        .clk            (clk           ),
        .resetn         (resetn        ),

        .display_valid  (display_valid ),
        .display_name   (display_name  ),
        .display_value  (display_value ),
        .display_number (display_number),
        .input_valid    (input_valid   ),
        .input_value    (input_value   ),

        .lcd_rst        (lcd_rst       ),
        .lcd_cs         (lcd_cs        ),
        .lcd_rs         (lcd_rs        ),
        .lcd_wr         (lcd_wr        ),
        .lcd_rd         (lcd_rd        ),
        .lcd_data_io    (lcd_data_io   ),
        .lcd_bl_ctr     (lcd_bl_ctr    ),
        .ct_int         (ct_int        ),
        .ct_sda         (ct_sda        ),
        .ct_scl         (ct_scl        ),
        .ct_rstn        (ct_rstn       )
    );
//-----{实例化触摸屏}end

//-----{从触摸屏获取输入}begin
    always @(posedge clk)
    begin
        if (!resetn)
        begin
            mem_addr <= 32'd0;
        end
        else if (input_valid)
        begin
            mem_addr <= input_value;
        end
    end
    assign rf_addr = display_number - 6'd11;
//-----{从触摸屏获取输入}end

//-----{输出到触摸屏显示}begin
//  显示区域分配:
//  1:  IF_PC   取指PC
//  2:  IF_IN   取指指令
//  3:  ID_PC   译码PC
//  4:  EXEPC   执行PC
//  5:  MEMPC   访存PC
//  6:  MEMIN   访存指令
//  7:  WB_PC   回写PC
//  8:  WB_IN   回写指令
//  9:  MADDR   观察内存地址
//  10: MDATA   内存地址对应数据
//  11-42: REG00-REG31  32个通用寄存器
//  43: STATE   CPU FSM状态
//  44: SW      拨码开关状态
    always @(posedge clk)
    begin
        if (display_number > 6'd10 && display_number < 6'd43)
        begin
            display_valid       <= 1'b1;
            display_name[39:16] <= "REG";
            display_name[15:8]  <= {4'b0011, 3'b000, rf_addr[4]};
            display_name[7:0]   <= {4'b0011, rf_addr[3:0]};
            display_value       <= rf_data;
        end
        else
        begin
            case(display_number)
                6'd1 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "IF_PC";
                    display_value <= if_pc;
                end
                6'd2 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "IF_IN";
                    display_value <= if_inst;
                end
                6'd3 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "ID_PC";
                    display_value <= id_pc;
                end
                6'd4 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "EXEPC";
                    display_value <= exe_pc;
                end
                6'd5 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "MEMPC";
                    display_value <= mem_pc;
                end
                6'd6 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "MEMIN";
                    display_value <= mem_inst;
                end
                6'd7 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "WB_PC";
                    display_value <= wb_pc;
                end
                6'd8 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "WB_IN";
                    display_value <= wb_inst;
                end
                6'd9 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "MADDR";
                    display_value <= mem_addr;
                end
                6'd10 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "MDATA";
                    display_value <= mem_data;
                end
                6'd43 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "STATE";
                    display_value <= display_state;
                end
                6'd44 :
                begin
                    display_valid <= 1'b1;
                    display_name  <= "SW   ";
                    display_value <= {24'b0, sw};
                end
                default :
                begin
                    display_valid <= 1'b0;
                    display_name  <= 40'd0;
                    display_value <= 32'd0;
                end
            endcase
        end
    end
//-----{输出到触摸屏显示}end
//----------------------{调用触摸屏模块}end---------------------//
endmodule
