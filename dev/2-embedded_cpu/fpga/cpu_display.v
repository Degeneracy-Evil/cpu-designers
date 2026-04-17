//*************************************************************************
//   > 文件名: cpu_display.v
//   > 描述  ：CPU状态显示模块，调用FPGA板上的IO接口和触摸屏
//   > 作者  : CPU Designers
//   > 日期  : 2026年4月17日
//   > 说明  ：适配dev/2-embedded_cpu中的cpu_top模块到FPGA测试
//*************************************************************************
module cpu_display(
    //时钟与复位信号
    input clk,
    input resetn,    //低电平有效

    //拨码开关，用于切换显示页面
    input [1:0] input_sel, //00/01:核心状态页, 10:内存状态页, 11:总线状态页
    input flush,           // SW2: 高电平时清零锁存显示

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

  // 复位信号转换: resetn(低电平有效) -> reset(高电平有效)
  wire reset;
  assign reset = ~resetn;

  //-----{调用CPU模块}begin
  wire [31:0] debug_pc;
  wire [31:0] debug_instr;
  wire [4:0]  debug_state;
  wire        debug_illegal;
  wire [31:0] debug_mem_addr;
  wire [31:0] debug_mem_wdata;
  wire [31:0] debug_mem_rdata;
  wire [3:0]  debug_mem_wstrb;
  wire [31:0] debug_display_mem_data;

  cpu_top u_cpu_top(
            .clk(clk),
            .reset(reset),
            .debug_pc(debug_pc),
            .debug_instr(debug_instr),
            .debug_state(debug_state),
            .debug_illegal(debug_illegal),
            .debug_mem_addr(debug_mem_addr),
            .debug_mem_wdata(debug_mem_wdata),
            .debug_mem_rdata(debug_mem_rdata),
            .debug_mem_wstrb(debug_mem_wstrb),
            .debug_display_mem_data(debug_display_mem_data)
          );
  //-----{调用CPU模块}end

  //-----{显示锁存寄存器}begin
  reg  [31:0] latched_pc;
  reg  [31:0] latched_instr;
  reg  [31:0] latched_state;
  reg  [31:0] latched_illegal;
  reg  [31:0] latched_mem_addr;
  reg  [31:0] latched_mem_wdata;
  reg  [31:0] latched_mem_rdata;
  reg  [31:0] latched_mem_wstrb;
  reg  [31:0] latched_mem_data;

  localparam STATE_MEM_READ_WAIT = 5'd8;

  always @(posedge clk)
  begin
    if (!resetn || flush)
    begin
      latched_pc       <= 32'd0;
      latched_instr    <= 32'd0;
      latched_state    <= 32'd0;
      latched_illegal  <= 32'd0;
      latched_mem_addr <= 32'd0;
      latched_mem_wdata <= 32'd0;
      latched_mem_rdata <= 32'd0;
      latched_mem_wstrb <= 32'd0;
      latched_mem_data <= 32'd0;
    end
    else
    begin
      latched_pc      <= debug_pc;
      latched_instr   <= debug_instr;
      latched_state   <= {27'b0, debug_state};
      latched_illegal <= {31'b0, debug_illegal};
      latched_mem_addr <= debug_mem_addr;
      latched_mem_data <= debug_display_mem_data;

      if (debug_mem_wstrb != 4'b0000)
      begin
        latched_mem_wdata <= debug_mem_wdata;
        latched_mem_wstrb <= {28'b0, debug_mem_wstrb};
      end

      if (debug_state == STATE_MEM_READ_WAIT)
      begin
        latched_mem_rdata <= debug_mem_rdata;
      end
    end
  end
  //-----{显示锁存寄存器}end

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

  // 触摸输入在CPU显示模式下不参与控制，仅保留接口兼容
  wire unused_input;
  assign unused_input = input_valid ^ input_value[0];

  //-----{输出到触摸屏显示}begin
  // 显示区域分配(每页1-7槽):
  // 核心页(00/01): PC, INSTR, STATE, ILLGL, PSEL, FLUSH, MDATA
  // 内存页(10): MADDR, MWDAT, MRDAT, WSTRB, MDATA, STATE, PSEL
  // 总线页(11): PC, MADDR, MWDAT, MRDAT, WSTRB, INSTR, ILLGL
  always @(posedge clk)
  begin
    display_valid <= 1'b0;
    display_name  <= 40'd0;
    display_value <= 32'd0;

    if (input_sel == 2'b10)
    begin
      case(display_number)
        6'd1 : begin display_valid <= 1'b1; display_name <= "MADDR"; display_value <= latched_mem_addr; end
        6'd2 : begin display_valid <= 1'b1; display_name <= "MWDAT"; display_value <= latched_mem_wdata; end
        6'd3 : begin display_valid <= 1'b1; display_name <= "MRDAT"; display_value <= latched_mem_rdata; end
        6'd4 : begin display_valid <= 1'b1; display_name <= "WSTRB"; display_value <= latched_mem_wstrb; end
        6'd5 : begin display_valid <= 1'b1; display_name <= "MDATA"; display_value <= latched_mem_data; end
        6'd6 : begin display_valid <= 1'b1; display_name <= "STATE"; display_value <= latched_state; end
        6'd7 : begin display_valid <= 1'b1; display_name <= "PSEL "; display_value <= {30'b0, input_sel}; end
        default : begin end
      endcase
    end
    else if (input_sel == 2'b11)
    begin
      case(display_number)
        6'd1 : begin display_valid <= 1'b1; display_name <= "PC   "; display_value <= latched_pc; end
        6'd2 : begin display_valid <= 1'b1; display_name <= "MADDR"; display_value <= latched_mem_addr; end
        6'd3 : begin display_valid <= 1'b1; display_name <= "MWDAT"; display_value <= latched_mem_wdata; end
        6'd4 : begin display_valid <= 1'b1; display_name <= "MRDAT"; display_value <= latched_mem_rdata; end
        6'd5 : begin display_valid <= 1'b1; display_name <= "WSTRB"; display_value <= latched_mem_wstrb; end
        6'd6 : begin display_valid <= 1'b1; display_name <= "INSTR"; display_value <= latched_instr; end
        6'd7 : begin display_valid <= 1'b1; display_name <= "ILLGL"; display_value <= latched_illegal; end
        default : begin end
      endcase
    end
    else
    begin
      case(display_number)
        6'd1 : begin display_valid <= 1'b1; display_name <= "PC   "; display_value <= latched_pc; end
        6'd2 : begin display_valid <= 1'b1; display_name <= "INSTR"; display_value <= latched_instr; end
        6'd3 : begin display_valid <= 1'b1; display_name <= "STATE"; display_value <= latched_state; end
        6'd4 : begin display_valid <= 1'b1; display_name <= "ILLGL"; display_value <= latched_illegal; end
        6'd5 : begin display_valid <= 1'b1; display_name <= "PSEL "; display_value <= {30'b0, input_sel}; end
        6'd6 : begin display_valid <= 1'b1; display_name <= "FLUSH"; display_value <= {31'b0, flush}; end
        6'd7 : begin display_valid <= 1'b1; display_name <= "MDATA"; display_value <= latched_mem_data; end
        default : begin end
      endcase
    end
  end
  //-----{输出到触摸屏显示}end
  //----------------------{调用触摸屏模块}end---------------------//
endmodule
