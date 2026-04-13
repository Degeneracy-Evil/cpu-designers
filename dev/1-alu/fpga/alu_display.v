//*************************************************************************
//   > 文件名: alu_display.v
//   > 描述  ：ALU显示模块，调用FPGA板上的IO接口和触摸屏
//   > 作者  : CPU Designers
//   > 日期  : 2026年3月31日
//   > 说明  ：适配dev/1alu中的alu_32bit模块到FPGA测试
//*************************************************************************
module alu_display(
    //时钟与复位信号
    input clk,
    input resetn,    //低电平有效

    //拨码开关，用于选择输入数
    input [1:0] input_sel, //00:输入为控制信号(alu_control)
    //10:输入为源操作数1(alu_src1)
    //11:输入为源操作数2(alu_src2)
    input flush,           // SW2: 高电平时触发flush并清空当前控制输入

    //触摸屏相关接口
    output lcd_rst,
    output lcd_cs,
    output lcd_rs,
    output lcd_wr,
    output lcd_rd,
    inout[15:0] lcd_data_io,
    output lcd_bl_ctr,
    inout ct_int,
    inout ct_sda,
    output ct_scl,
    output ct_rstn
  );

  //-----{调用ALU模块}begin
  reg   [15:0] alu_control;  // ALU控制信号(16位one-hot)
  reg          launch_pending; // 待发射请求标记
  reg   [31:0] alu_src1;     // ALU操作数1
  reg   [31:0] alu_src2;     // ALU操作数2
  wire  [31:0] alu_result;   // ALU结果
  reg   [31:0] alu_result_latched; // 锁存最近一次有效结果
  wire         alu_ready;
  wire         alu_result_valid;

  // 复位信号转换: resetn(低电平有效) -> reset(高电平有效)
  wire reset;
  assign reset = ~resetn;

  // 调用自己开发的ALU模块
  alu_32bit alu_module(
              .clk(clk),
              .reset(reset),
              .alu_control(alu_control),
              .src1(alu_src1),
              .src2(alu_src2),
              .req_valid(launch_pending),
              .flush(flush),
              .result_ready(1'b1),
              .result(alu_result),
              .alu_busy(),
              .alu_ready(alu_ready),
              .result_valid(alu_result_valid),
              .illegal_op(),
              .div_by_zero()
            );
  //-----{调用ALU模块}end

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

               //调用触摸屏的接口
               .display_valid  (display_valid ),
               .display_name   (display_name  ),
               .display_value  (display_value ),
               .display_number (display_number),
               .input_valid    (input_valid   ),
               .input_value    (input_value   ),

               //lcd触摸屏相关接口
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
  //当input_sel为00时，输入控制信号
  always @(posedge clk)
  begin
    if (!resetn)
    begin
      alu_control <= 16'd0;
      launch_pending <= 1'b0;
    end
    else
    begin
      if (flush)
      begin
        alu_control <= 16'd0;
        launch_pending <= 1'b0;
      end
      else if (input_valid && input_sel==2'b00)
      begin
        alu_control <= input_value[15:0];  // 只取低16位
        launch_pending <= (input_value[15:0] != 16'd0);
      end
      else if (launch_pending && alu_ready)
      begin
        launch_pending <= 1'b0;
      end
    end
  end

  //当input_sel为10时，输入源操作数1
  always @(posedge clk)
  begin
    if (!resetn)
    begin
      alu_src1 <= 32'd0;
    end
    else if (input_valid && input_sel==2'b10)
    begin
      alu_src1 <= input_value;
    end
  end

  //当input_sel为11时，输入源操作数2
  always @(posedge clk)
  begin
    if (!resetn)
    begin
      alu_src2 <= 32'd0;
    end
    else if (input_valid && input_sel==2'b11)
    begin
      alu_src2 <= input_value;
    end
  end

  always @(posedge clk)
  begin
    if (!resetn)
    begin
      alu_result_latched <= 32'd0;
    end
    else if (alu_result_valid)
    begin
      alu_result_latched <= alu_result;
    end
  end
  //-----{从触摸屏获取输入}end

  //-----{输出到触摸屏显示}begin
  // 显示区域分配:
  // 1: SRC_1 (源操作数1)
  // 2: SRC_2 (源操作数2)
  // 3: CONTR (控制信号)
  // 4: RESUL (运算结果)
  // 5: RVALD (结果有效)
  // 6: INSEL (当前input_sel)
  // 7: FLUSH (当前flush)
  always @(posedge clk)
  begin
    case(display_number)
      6'd1 :
      begin
        display_valid <= 1'b1;
        display_name  <= "SRC_1";
        display_value <= alu_src1;
      end
      6'd2 :
      begin
        display_valid <= 1'b1;
        display_name  <= "SRC_2";
        display_value <= alu_src2;
      end
      6'd3 :
      begin
        display_valid <= 1'b1;
        display_name  <= "OP";
        display_value <= {16'b0, alu_control};  // 扩展到32位显示
      end
      6'd4 :
      begin
        display_valid <= 1'b1;
        display_name  <= "RESUL";
        display_value <= alu_result_latched;
      end
      6'd5 :
      begin
        display_valid <= 1'b1;
        display_name  <= "RVALD";
        display_value <= {31'b0, alu_result_valid};
      end
      6'd6 :
      begin
        display_valid <= 1'b1;
        display_name  <= "INSEL";
        display_value <= {30'b0, input_sel};  // 显示input_sel[1:0]
      end
      6'd7 :
      begin
        display_valid <= 1'b1;
        display_name  <= "FLUSH";
        display_value <= {31'b0, flush};  // 显示flush开关状态
      end
      default :
      begin
        display_valid <= 1'b0;
        display_name  <= 40'd0;
        display_value <= 32'd0;
      end
    endcase
  end
  //-----{输出到触摸屏显示}end
  //----------------------{调用触摸屏模块}end---------------------//
endmodule
