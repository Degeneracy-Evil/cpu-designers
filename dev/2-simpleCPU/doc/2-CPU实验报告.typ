// 数字电路实验报告模板（Typst）
#set title("基础处理器设计实验报告")
#import "@local/cetz:0.5.0"
// 段落缩进
#set par(first-line-indent: (amount: 2em, all: true))
// 强调改进
#show strong: text.with(font: "Microsoft YaHei")
#show emph: text.with(font: ("Calibri", "LiSu"))

#set page(paper: "a4", margin: (top: 2cm, bottom: 2cm, left: 2.5cm, right: 2cm))
#set heading(numbering: "1.")
#show heading: it => {
  block([*#it*], below: 1em)
}
#set text(size: 24pt)
#align(horizon, {
  [#align(center)[2026 年春季学期\
    计算机组成原理课程]]
  v(2em)
  align(center)[32 位 RISC-V 多周期CPU 核]
  v(2em)
  align(center)[#text(40pt)[设\ 计\ 报\ 告]]

  v(4em)
  align(center)[#text(size: 18pt)[负责人：]]
  align(center)[#text(size: 18pt)[2026年4月21日]]
})
#pagebreak()
//普通文本
#set text(size: 14pt)
#set page(numbering: "1 / 1")

= 项目简述

== 项目环境与级别

设计语言：Verilog

仿真环境：Vivado~2018.3版本

== 设计目标

#move(dx: 2em)[
  + 支持`RISCV32-I`指令集除`fence`和中断相关指令
  + 采用多周期处理器
  + 哈佛架构（`iCache`和`dCache`），使用BLOCK RAM
  + 使用上一次实验的ALU（经过了优化）
  + 交叉编译rv32I汇编为coe文件并导入执行
]

== 参考资料

#move(dx: 2em)[
  + RISC-V-Reader-Chinese-v2p12017.pdf
  + FPGA-A7-PRJ-UDB_V1.0-引脚坐标参考.pdf
  + 所有课程PPT（指导老师：何安平）
]

== 项目文件夹结构


```text
2-simpleCPU/
├── rtl/                     RTL设计源文件
│   ├── simple_cpu_top.v     顶层模块，实例化所有子模块并完成互连
│   ├── cpu_controller.v     控制器模块，FSM状态机驱动各阶段使能
│   ├── cpu_fetch.v          取指模块，从icache读取指令
│   ├── cpu_decode.v         解码模块，指令译码、立即数生成、ALU控制信号生成
│   ├── cpu_execute.v        执行模块，调用ALU完成运算，分支判断
│   ├── cpu_mem.v            访存模块，读写dcache，支持byte/halfword/word及符号/零扩展
│   ├── cpu_wb.v             回写模块，将结果写回寄存器堆
│   ├── cpu_regfile.v        32×32bit寄存器堆，x0硬连线为0
│   ├── op_regroup.v         指令重组电路，提取opcode/funct3/funct7/rs1/rs2/rd及各类型立即数
│   ├── branch_comparator.v  分支比较器，判断beq/bne/blt/bge/bltu/bgeu条件
│   ├── icache.v             icache行为级模型（True Dual Port BRAM），使用hex文件初始化
│   └── dcache.v             dcache行为级模型（True Dual Port BRAM），全零初始化
├── tb/                      测试台文件
│   └── tb_simple_cpu_top.v  顶层测试台，包含寄存器和内存检查任务
├── program_source/          程序源文件
│   ├── icache_init.s        综合测试汇编程序（37条指令全覆盖）
│   ├── icache_init.hex      编译后的hex初始化文件
│   ├── icache_init.coe      Vivado COE格式初始化文件
│   ├── fib10.c              斐波那契数列C语言测试程序
│   └── fib10.coe            fib10编译后的COE文件
├── fpga/                    FPGA上板相关文件
│   ├── simple_cpu_display.v FPGA显示模块，连接LCD触摸屏调试
│   ├── cpu.xdc              Vivado引脚约束文件
│   └── lcd_module.dcp       LCD触摸屏IP核
└── doc/                     项目文档
    ├── 简单CPU项目描述.md     项目架构与模块定义
    ├── instruction-set.md   指令集实现定义
    ├── exception-interrupt.md 异常与中断机制设计
    └── PROCESS.md           BRAM IP核读延迟适配记录
```

= 实现细节

== 指令集选取

我们选取了`RISCV32-I`指令集除`fence`和中断相关以外的指令，即

#table(
  columns: (1fr, 1fr, 1fr, 1fr, 1fr),
  align: center,
  text(orange)[add], text(orange)[sub], text(orange)[sll], text(orange)[slt], text(orange)[sltu],
  text(orange)[xor], text(orange)[srl], text(orange)[sra], text(orange)[or], text(orange)[and],
  text(maroon)[jalr], text(maroon)[lb], text(maroon)[lh], text(maroon)[lw], text(maroon)[lbu],
  text(maroon)[lhu], text(maroon)[addi], text(maroon)[slti], text(maroon)[sltiu], text(maroon)[xori],
  text(maroon)[ori], text(maroon)[andi], text(maroon)[slli], text(maroon)[srli], text(maroon)[srai],
  text(fuchsia)[sb], text(fuchsia)[sh], text(fuchsia)[sw], text(olive)[beq], text(olive)[bne],
  text(olive)[blt], text(olive)[bge], text(olive)[bltu], text(olive)[bgeu], text(blue)[lui],
  text(blue)[auipc], [jal],
)

共37条指令，涉及到全部#text(orange)[`R`] #text(maroon)[`I`] #text(fuchsia)[`S`] #text(olive)[`B`] #text(blue)[`U`] `J`类别，能够实现基本CPU核。

== IP核使用

我们使用了BRAM IP核做为`iCache/dCache`，详细配置为：
#move(dx: 4em)[
  - 真双口(True Dual Port RAM)
  - 位宽：32
  - 位深：2048
  - Primitives Output Register：否
  - Core Output Register：否
  - iCache使用coe文件初始化
]
`iCache，dCache`分别实例化了一个BRAM IP核。

== 流水线设计

使用基础五级多周期流水线：

#align(center)[#cetz.canvas({
  import cetz.draw: *
  let draw_line(x, y, w, h, d, alist) = {
    let px = x
    let count = 0
    for obj in alist {
      let id = obj.at(0)
      let text = obj.at(1)
      rect((px, y), (px + w, y + h), name: id)
      content(id, [#text])
      if count > 0 {
        line(alist.at(count - 1).at(0), id, mark: (end: "straight"))
      }
      px = px + w + d
      count = count + 1
    }
  }

  let water_line = (("if", "取指"), ("dc", "解码"), ("exe", "执行"), ("mem", "访存"), ("wb", "回写"))
  draw_line(0, 0, 2, 1.5, 1, water_line)
  line("wb", (rel: (0, -1.5), to: "wb"), (rel: (0, -1.5), to: "if"), "if", mark: (end: "straight"))
})]

多周期处理器在每个时钟周期只执行一个阶段，由控制器依据FSM依次驱动进行取指→解码→执行→访存→回写。可跳过当前指令不需要的阶段（如R-Type跳过访存，Branch跳过访存和回写）。

== 控制器模块

=== 状态机

控制器采用6状态FSM，状态编码如下：

#table(
  columns: (1fr, 1fr, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*编码*], [*状态*], [*说明*],
  [3'd0], [`STATE_IDLE`], [复位后的初始状态，直接转入FETCH],
  [3'd1], [`STATE_FETCH`], [取指阶段，等待icache输出有效后转入DECODE],
  [3'd2], [`STATE_DECODE`], [解码阶段，完成后根据指令类型决定下一状态],
  [3'd3], [`STATE_EXEC`], [执行阶段，完成后分支指令直接回FETCH，其余进入MEM],
  [3'd4], [`STATE_MEM`], [访存阶段，等待dcache操作完成后转入WB],
  [3'd5], [`STATE_WB`], [回写阶段，完成后转入FETCH开始下一条指令],
)

状态转移逻辑：

#align(center)[#cetz.canvas({
  import cetz.draw: *
  let states = (("s0", "IDLE"), ("s1", "FETCH"), ("s2", "DECODE"), ("s3", "EXEC"), ("s4", "MEM"), ("s5", "WB"))
  let px = 0
  let py = 0
  let w = 2
  let h = 1.5
  let d = 1.6
  for (i, s) in states.enumerate() {
    let (id, label) = s
    rect((px + i * (w + d), py), (px + i * (w + d) + w, py + h), name: id)
    content(id, [#text(size: 12pt, label)])
  }
  line("s0", "s1", mark: (end: "straight"))
  line(
    (rel: (0, 0.25), to: "s1.east"),
    (rel: (0, 0.25), to: "s2.west"),
    mark: (end: "straight"),
    name: "1t2",
  )
  content("1t2", anchor: "south", padding: .1, [#text(size: 10pt, "if_done")])
  line("s2", "s3", mark: (end: "straight"), name: "2t3")
  content("2t3", anchor: "south", padding: .1, [#text(size: 10pt, "need_exe")])
  line(
    (rel: (0, -0.25), to: "s2.west"),
    (rel: (0, -0.25), to: "s1.east"),
    mark: (end: "straight"),
    name: "2t1",
  )
  content("2t1", anchor: "north", padding: .1, [#text(size: 10pt, "!need_exe")])
  line("s3", "s4", mark: (end: "straight"), name: "3t4")
  content("3t4", anchor: "south", padding: .1, [#text(size: 10pt, "!branch")])
  line(
    "s3",
    (rel: (0, 1.5), to: "s3"),
    (rel: (0, 1.5), to: "s1"),
    "s1",
    mark: (end: "straight"),
    name: "3t1",
  )
  content("3t1", anchor: "south", padding: .0, [#text(size: 10pt, "branch")])
  line("s4", "s5", mark: (end: "straight"), name: "4t5")
  content("4t5", anchor: "south", padding: .1, [#text(size: 9pt, "mem_done")])
  line(
    "s5",
    (rel: (0, -1.5), to: "s5"),
    (rel: (0, -1.5), to: "s1"),
    "s1",
    mark: (end: "straight"),
    name: "5t1",
  )
  content("5t1", anchor: "north", padding: .0, [#text(size: 10pt, "wb_done")])
})]

控制器输出5路使能信号`if_valid`、`id_valid`、`exe_valid`、`mem_valid`、`wb_valid`，分别对应当前FSM处于对应状态时为高电平。此外还输出`state`信号供FPGA调试显示。

解码阶段的特殊处理：
- 非法指令（`dec_illegal`）：直接跳回FETCH，PC←PC+4

执行阶段的特殊处理：
- 分支指令（`exe_is_branch`）：跳回FETCH，由`exe_branch_taken`决定PC更新

非分支指令则进入MEM阶段，由控制器决定是否真正开启MEM功能。

== 取指模块

取指模块负责从icache中读取当前PC对应的指令字。

*接口信号：*

#table(
  columns: (1fr, 1fr, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*方向*], [*信号*], [*说明*],
  [输入], [`pc`], [当前程序计数器，32位],
  [输入], [`inst_data`], [icache输出的指令数据],
  [输出], [`icache_en`], [icache使能，等于`if_valid`],
  [输出], [`icache_addr`], [icache地址，取`pc[12:2]`（字对齐）],
  [输出], [`if_done`], [取指完成标志，`if_valid && r_bram_sent`],
  [输出], [`if_id_bus`], [取指→解码总线，96位],
)

*输出总线（if\_id\_bus，96位）位映射：*

#table(
  columns: (1fr, 1fr, 1fr, 3fr),
  align: (center, center, center, left),
  stroke: 0.5pt,
  inset: 4pt,
  [*位域*], [*宽度*], [*字段*], [*说明*],
  [95:64], [32], [`pc_plus4`], [PC+4（用于JAL/JALR返回地址）],
  [63:32], [32], [`pc`], [当前PC],
  [31:0], [32], [`inst`], [指令字（icache输出）],
)

*BRAM延迟适配：*

由于icache使用BRAM IP核，具有1周期同步读延迟。取指阶段icache\_en和icache\_addr为组合逻辑输出，BRAM在下一个时钟沿锁存地址、再下一个沿输出数据。因此引入`r_bram_sent`寄存器：

```v
    // 固定进行一周期的等待（即到上升沿icache发送数据后）
    reg r_bram_sent;
    always @(posedge clk or posedge reset) begin
        if (reset)
            r_bram_sent <= 1'b0;
        else if (if_valid)
            r_bram_sent <= 1'b1;
        else
            r_bram_sent <= 1'b0;
    end
```

#move(dx: 2em)[
  - 沿E：`state_r`进入FETCH，`if_valid=1`，`icache_en=1`，地址有效
  - 沿E+1：BRAM锁存地址，`r_bram_sent`置1，`if_done=1`
  - 沿E+2：`if_id_bus_r`捕获`icache_dout`（数据已有效）
]

即需要两个时钟上升沿才能完成动作，确保数据稳定后才通知控制器完成取指。

== 解码模块

解码模块是CPU中逻辑最复杂的组合逻辑模块，负责从32位指令中提取所有控制信号和操作数。

*指令重组（op\_reggroup）：*

通过`op_regroup`子模块完成指令字段提取：
#move(dx: 2em)[```v
  assign opcode=op32bit[6:0];
  assign funct3=op32bit[14:12];
  assign funct7=op32bit[31:25];
  assign rd=op32bit[11:7];
  assign rs1=op32bit[19:15];
  assign rs2=op32bit[24:20];
```]
- 五种立即数生成（均符号扩展）：
#move(dx: 2em)[```v
  assign H=op32bit[31];
  assign D4=op32bit[30:25];
  assign D3=op32bit[24:21];
  assign M=op32bit[20];
  assign D2=op32bit[19:12];
  assign D1=op32bit[11:8];
  assign L=op32bit[7];
  assign immI={{21{H}},D4,D3,M};
  assign immS={{21{H}},D4,D1,L};
  assign immB={{19{H}},H,L,D4,D1,1'b0};
  assign immU={H,D4,D3,M,D2,{12{1'b0}}};
  assign immJ={{12{H}},D2,M,D4,D3,1'b0};
```]

*指令识别：*

当前实现中我们通过opcode、funct3、funct7的组合匹配识别37条指令，产生独立的单比特标志信号（如`inst_add`、`inst_beq`等），这样利于排查以及后续添加指令。完成具体指令识别后，指令会被再归类为：
#move(dx: 2em)[- `is_branch`：6条分支指令
- `is_load`：5条Load指令
- `is_store`：3条Store指令
- `is_jal_like`：JAL、JALR
- `is_alu`：所有需要ALU运算的指令（含LUI、AUIPC、Load、Store的地址计算）]

*ALU操作数选择：*

#table(
  columns: (1fr, 2fr, 2fr),
  align: center,
  stroke: 0.5pt,
  inset: 6pt,
  [*指令类别*], [*alu\_src1*], [*alu\_src2*],
  [LUI], [`rs1_value`], [`imm_u`],
  [AUIPC], [`pc`], [`imm_u`],
  [JAL], [`pc`], [`imm_j`],
  [JALR], [`rs1_value`], [`imm_i`],
  [Branch], [`pc`], [`imm_b`],
  [I-Type算术], [`rs1_value`], [`imm_i`],
  [移位指令], [`rs1_value`], [`shamt/rs2_value`],
  [R-Type], [`rs1_value`], [`rs2_value`],
  [Load], [`rs1_value`], [`imm_i`（计算地址）],
  [Store], [`rs1_value`], [`imm_s`（计算地址）],
)

*ALU控制信号：*

16位`alu_control`信号根据指令类型编码，传递给执行模块的ALU。例如ADD/ADDI/AUIPC/Load/Store/JAL/JALR/Branch均映射为加法操作，SUB映射为减法操作等。

*输出总线（id\_exe\_bus，292位）位映射：*

#table(
  columns: (1fr, 1fr, 2fr, auto),
  align: (center, center, center, left),
  stroke: 0.5pt,
  inset: 4pt,
  [*位域*], [*宽度*], [*字段*], [*说明*],
  [291:260], [32], [`pc_plus4`], [PC+4],
  [259], [1], [`valid_inst`], [合法指令标志],
  [258], [1], [`is_alu`], [ALU运算类],
  [257], [1], [`is_load`], [Load指令],
  [256], [1], [`is_store`], [Store指令],
  [255], [1], [`is_jal_like`], [JAL/JALR指令],
  [254], [1], [`is_branch`], [Branch指令],
  [253], [1], [`use_fixed_wb`], [使用固定回写数据（LUI）],
  [252], [1], [`wb_we`], [寄存器写使能],
  [251:247], [5], [`rd`], [目标寄存器号],
  [246:215], [32], [`wb_fixed_data`], [固定回写数据],
  [214:212], [3], [`mem_size`], [访存宽度：000=byte, 001=half, 010=word],
  [211], [1], [`mem_unsigned`], [零扩展标志（lbu/lhu）],
  [210:195], [16], [`alu_control`], [ALU操作控制码],
  [194:163], [32], [`alu_src1`], [ALU源操作数1],
  [162:131], [32], [`alu_src2`], [ALU源操作数2],
  [130:99], [32], [`rs1_value`], [rs1寄存器值],
  [98:67], [32], [`rs2_value`], [rs2寄存器值],
  [66:64], [3], [`branch_funct3`], [分支funct3（条件类型）],
  [63:32], [32], [`pc`], [当前PC],
  [31:0], [32], [`inst`], [原始指令字],
)

== 执行模块

执行模块调用ALU完成运算，并处理分支和跳转指令的目标地址计算与条件判断。

*ALU接口：*

使用`alu_32bit`模块（来自1-alu实验）ALU可能需要多个周期（乘除法），通过握手协议交互：
#move(dx: 2em)[
- `req_valid`→`alu_ready`：发起运算请求
- `result_valid`→`result_ready`：接收运算结果
]
详细接口和握手逻辑见2.7.2节。

*执行流程：*

#move(dx: 2em)[
  + `use_fixed_wb`为真（如LUI指令）：直接使用`wb_fixed_data`作为结果，1周期完成
  + 否则：向ALU发`req_valid`，等待`result_valid`，采样`alu_result`
]

*分支与跳转处理：*

#move(dx: 2em)[- `branch_comparator`模块根据`branch_funct3`和`rs1_value/rs2_value`判断分支条件是否成立
- 分支目标地址：ALU计算`pc + imm_b`的结果
- JALR目标地址：`alu_result & 0xFFFFFFFE`（清除最低位）
- `exe_branch_taken`：分支指令取`branch_cond_true`，JAL/JALR指令取1
- `exe_is_ctrl_flow`：分支或跳转指令时为1，通知顶层更新PC]

=== 分支比较器（branch\_comparator）

纯组合逻辑模块，根据`branch_funct3`和两个操作数判断分支条件是否成立。

*接口：*

#table(
  columns: (auto, 1fr, 2fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*方向*], [*信号*], [*说明*],
  [输入], [`rs1_value[31:0]`], [寄存器rs1的值],
  [输入], [`rs2_value[31:0]`], [寄存器rs2的值],
  [输入], [`branch_funct3[2:0]`], [分支条件类型（来自指令funct3）],
  [输出], [`branch_cond_true`], [分支条件成立标志],
)

*判断逻辑：*

内部先计算三个基础比较结果：

#move(dx: 2em)[
  - `rs1_eq_rs2 = (rs1_value == rs2_value)`
  - `rs1_lt_rs2_s = $signed(rs1_value) < $signed(rs2_value)`（有符号比较）
  - `rs1_lt_rs2_u = rs1_value < rs2_value`（无符号比较）
]

再根据`branch_funct3`选择：

#table(
  columns: (1fr, 1fr, 2fr, 2fr),
  align: center,
  stroke: 0.5pt,
  inset: 6pt,
  [*funct3*], [*指令*], [*条件*], [*表达式*],
  [000], [beq], [相等], [`rs1_eq_rs2`],
  [001], [bne], [不等], [`!rs1_eq_rs2`],
  [100], [blt], [有符号小于], [`rs1_lt_rs2_s`],
  [101], [bge], [有符号大于等于], [`!rs1_lt_rs2_s`],
  [110], [bltu], [无符号小于], [`rs1_lt_rs2_u`],
  [111], [bgeu], [无符号大于等于], [`!rs1_lt_rs2_u`],
)

=== ALU接口与握手协议

执行模块通过握手协议与`alu_32bit`模块交互，支持单周期组合运算和多周期乘除法运算。

*ALU端口映射：*

#table(
  columns: (auto, auto, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*方向*], [*信号*], [*说明*],
  [→ALU], [`alu_control[15:0]`], [one-hot操作码，bit0保留],
  [→ALU], [`src1[31:0]`], [源操作数1（alu\_src1）],
  [→ALU], [`src2[31:0]`], [源操作数2（alu\_src2）],
  [→ALU], [`req_valid`], [请求有效，CPU发起运算],
  [→ALU], [`flush`], [冲刷信号（当前固定为0）],
  [→ALU], [`result_ready`], [下游消费确认],
  [ALU→], [`result[31:0]`], [运算结果],
  [ALU→], [`alu_ready`], [ALU可接收新请求],
  [ALU→], [`result_valid`], [结果有效标志],
  [ALU→], [`alu_busy`], [乘除法执行中],
  [ALU→], [`illegal_op`], [非法操作码标志],
  [ALU→], [`div_by_zero`], [除零标志],
)

*握手时序：*

定义请求接收条件：`req_fire = req_valid && alu_ready && !illegal_op`

#move(dx: 2em)[
  + *发射*：`exe_valid`有效且`use_fixed_wb`为假时，拉高`req_valid`，置`exe_active=1`
  + *接收*：ALU在`req_fire`当拍采样操作数；若`req_valid && alu_ready`则下一拍`req_valid`清零
  + *等待*：组合指令1拍出结果，乘除法`alu_busy=1`期间持续等待
  + *采样*：`result_valid`上升时，锁存`alu_result`到`result_reg`，拉高`result_ready`一个周期作为消费确认
  + *完成*：`exe_active`清零，`done_reg`置1
]

*use\_fixed\_wb快速路径：*

当`use_fixed_wb=1`（如LUI指令）时，跳过ALU握手，直接将`wb_fixed_data`锁存为结果，1周期完成。

*控制编码（one-hot，bit0保留）：*

#table(
  columns: (auto, auto, auto, auto, auto, auto, auto, auto),
  align: center,
  stroke: 0.5pt,
  inset: 4pt,
  [*15*], [*14*], [*13*], [*12*], [*11*], [*10*], [*9*], [*8*],
  [MUL], [DIV], [NOT], [ADD], [SUB], [SLT], [SLTU], [AND],
)
#table(
  columns: (auto, auto, auto, auto, auto, auto, auto, auto),
  align: center,
  stroke: 0.5pt,
  inset: 4pt,
  [*7*], [*6*], [*5*], [*4*], [*3*], [*2*], [*1*], [*0*],
  [NOR], [OR], [XOR], [SLL], [SRL], [SRA], [LUI], [—],
)

*输出总线（exe\_mem\_bus，174位）位映射：*

#table(
  columns: (1fr, 1fr, 2fr, 3fr),
  align: (center, center, center, left),
  stroke: 0.5pt,
  inset: 4pt,
  [*位域*], [*宽度*], [*字段*], [*说明*],
  [173:142], [32], [`pc_plus4`], [PC+4],
  [141], [1], [`result_ok`], [运算结果有效],
  [140], [1], [`is_jal_like`], [JAL/JALR标志],
  [139], [1], [`is_load`], [Load指令],
  [138], [1], [`is_store`], [Store指令],
  [137], [1], [`wb_we`], [寄存器写使能],
  [136:132], [5], [`wb_rd`], [写回目标寄存器号],
  [131:100], [32], [`result_reg`], [ALU运算结果],
  [99:97], [3], [`mem_size`], [访存宽度],
  [96], [1], [`mem_unsigned`], [零扩展标志],
  [95:64], [32], [`rs2_value`], [Store源数据（rs2值）],
  [63:32], [32], [`pc`], [当前PC],
  [31:0], [32], [`inst`], [原始指令字],
)

== 访存模块

访存模块负责与dcache交互，支持字节（byte）、半字（halfword）、字（word）的读写操作，以及符号扩展和零扩展。

*子状态机（6状态）：*

#table(
  columns: (auto, auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*编码*], [*状态*], [*说明*],
  [3'd0], [`MEM_IDLE`], [空闲，等待`mem_valid`有效],
  [3'd1], [`MEM_READ`], [发起读请求，设置dcache使能和地址],
  [3'd2], [`MEM_READ2`], [等待BRAM输出有效，采样数据],
  [3'd3], [`MEM_WRITE_MODIFY`], [发起读请求（读-改-写），获取旧数据],
  [3'd4], [`MEM_WRITE_MODIFY2`], [等待BRAM输出有效，合并新旧数据],
  [3'd5], [`MEM_WRITE_COMMIT`], [发起写请求，将合并后数据写入dcache],
)

*子状态转移条件：*

#align(center)[#cetz.canvas({
  import cetz.draw: *

  let sw = 4.0
  let sh = 1.3
  let dx = 5.6
  let dy = -2.8

  rect((0, 0), (sw, sh), name: "idle")
  content("idle", [#text(size: 9pt, "IDLE")])

  rect((dx, 0), (dx + sw, sh), name: "read")
  content("read", [#text(size: 9pt, "READ")])

  rect((2 * dx, 0), (2 * dx + sw, sh), name: "read2")
  content("read2", [#text(size: 9pt, "READ2")])

  rect((0, dy), (sw, dy + sh), name: "wmod")
  content("wmod", [#text(size: 9pt, "W_MODIFY")])

  rect((dx, dy), (dx + sw, dy + sh), name: "wmod2")
  content("wmod2", [#text(size: 9pt, "W_MODIFY2")])

  rect((2 * dx + 0.25, dy), (2 * dx + sw, dy + sh), name: "wcommit")
  content("wcommit", [#text(size: 9pt, "W_COMMIT")])

  line("idle", "read", mark: (end: "straight"), name: "l1")
  content("l1", anchor: "south", padding: .1, [#text(size: 10pt, "is_load")])

  line("idle", "wmod", mark: (end: "straight"), name: "l2")
  content("l2", anchor: "east", padding: .1, [#text(size: 10pt, "is_store")])

  line("read", "read2", mark: (end: "straight"), name: "l3")
  content("l3", anchor: "south", padding: .1, [#text(size: 10pt, "1 cycle")])

  line("read2", (rel: (0, 1.8), to: "read2"), (rel: (0, 1.8), to: "idle"), "idle", mark: (end: "straight"), name: "l4")
  content("l4", anchor: "south", padding: .0, [#text(size: 10pt, "sample→done")])

  line("wmod", "wmod2", mark: (end: "straight"), name: "l5")
  content("l5", anchor: "south", padding: .1, [#text(size: 10pt, "1 cycle")])

  line("wmod2", "wcommit", mark: (end: "straight"), name: "l6")
  content("l6", anchor: "south", padding: .1, [#text(size: 10pt, "merge→we")])

  line(
    "wcommit",
    (rel: (0, +1.2), to: "wcommit"),
    (rel: (1, -1), to: "idle"),
    "idle",
    mark: (end: "straight"),
    name: "l7",
  )
  content("l7", anchor: "east", padding: .0, [#text(size: 10pt, "done")])

  line(
    (rel: (-0.8, 0), to: "idle.north"),
    (rel: (-0.8, 1.5), to: "idle.north"),
    (rel: (0.8, 1.5), to: "read2.north"),
    (rel: (0.8, 0), to: "read2.north"),
    mark: (end: "straight"),
    stroke: (dash: "dashed"),
    name: "lb1",
  )
  content("lb1", anchor: "south", padding: .1, [#text(size: 10pt, "!is_load&&!is_store→done")])

  line(
    (rel: (0, -0.3), to: "idle.east"),
    (rel: (0, 0.3), to: "wmod2.west"),
    mark: (end: "straight"),
    stroke: (dash: "dashed"),
    name: "lb2",
  )
  content("lb2", anchor: "north", padding: .1, [#text(size: 10pt, "misalign→done")])
})]

*非访存指令快速通过：*

当`!is_load && !is_store`时，直接将ALU结果作为回写数据，1周期完成。

*地址未对齐检测：*

- LH/LHU：地址最低位不为0
- LW/SW：地址最低2位不为00
- 检测到未对齐时，取消写回使能，直接完成。

*Load数据提取与扩展：*

根据`mem_size`和`mem_unsigned`从BRAM读出的32位字中提取对应字节/半字，并进行符号扩展或零扩展：
- byte：按`byte_offset`选择8位，符号扩展或零扩展至32位
- halfword：按`byte_offset[1]`选择16位，符号扩展或零扩展至32位
- word：直接使用32位

*Store读-改-写：*

对于SB/SH指令，需要先读出原32位字，再将待写数据合并到对应字节位置，最后写回整个字。合并逻辑根据`mem_size`和`byte_offset`进行字节级拼接。

*BRAM延迟适配时序（读路径）：*

#move(dx: 2em)[
  - 沿A：MEM\_IDLE设置`en_reg=1, daddr_reg=addr`，进入MEM\_READ
  - 沿A+1：dcache\_en=1，地址有效，BRAM锁存地址，进入MEM\_READ2
  - 沿A+2：BRAM输出有效，采样`dcache_rdata`，`done=1`
]

*BRAM延迟适配时序（写路径）：*

#move(dx: 2em)[
  - 沿A：MEM\_IDLE设置读使能和地址，进入MEM\_WRITE\_MODIFY
  - 沿A+1：BRAM锁存地址，进入MEM\_WRITE\_MODIFY2
  - 沿A+2：BRAM输出有效，采样旧数据，合并后设置写使能，进入MEM\_WRITE\_COMMIT
  - 沿A+3：BRAM执行写入，`done=1`
]

*输出总线（mem\_wb\_bus，135位）位映射：*

#table(
  columns: (auto, auto, auto, auto),
  align: (center, center, center, left),
  stroke: 0.5pt,
  inset: 4pt,
  [*位域*], [*宽度*], [*字段*], [*说明*],
  [134:103], [32], [`pc_plus4`], [PC+4（用于JAL/JALR写回）],
  [102], [1], [`is_jal_like`], [JAL/JALR标志],
  [101], [1], [`wb_we_reg`], [寄存器写使能],
  [100:96], [5], [`wb_rd_reg`], [写回目标寄存器号],
  [95:64], [32], [`wb_data_reg`], [写回数据（ALU结果或Load数据）],
  [63:32], [32], [`pc`], [当前PC],
  [31:0], [32], [`inst`], [原始指令字],
)

== 回写模块

回写模块是纯组合逻辑，负责将访存阶段的结果写回寄存器堆。

*逻辑：*
- `rf_wen = wb_valid && wb_we`：仅在WB阶段且写使能有效时写入
- `rf_waddr = wb_rd`：写回目标寄存器
- `rf_wdata = wb_data`：写回数据（ALU结果或Load数据）

*JAL/JALR特殊处理：*

在顶层`simple_cpu_top`中，对于JAL/JALR指令，实际写回数据为`PC+4`（返回地址），而非ALU运算结果。通过`wb_is_jal_like`信号选择：
```verilog
assign actual_rf_wdata = wb_is_jal_like ? wb_pc_plus4 : rf_wdata;
```

*寄存器堆（cpu\_regfile）：*
- 32个32位寄存器，x0硬连线为0
- 组合读：`rdata1 = (raddr1 == 0) ? 0 : rf[raddr1]`
- 同步写：`wen && waddr != 0`时写入（不写x0）
- 额外调试读端口`dbg_rdata`供FPGA显示

== 结构总览

#align(center)[#cetz.canvas({
  import cetz.draw: *

  let box_w = 2.4
  let box_h = 1.0
  let gap_x = 0.8
  let gap_y = 1.2

  rect((-1.2, 2 * gap_y), (-1.2 + box_w, 2 * gap_y + box_h), name: "ctrl")
  content("ctrl", [#text(size: 9pt, "Controller")])

  let stages = (
    ("fetch", "Fetch"),
    ("decode", "Decode"),
    ("execute", "Execute"),
    ("mem", "Memory"),
    ("wb", "Writeback"),
  )
  for (i, s) in stages.enumerate() {
    let (id, label) = s
    let x_pos = i * (box_w + gap_x)
    rect((x_pos, 0), (x_pos + box_w, box_h), name: id)
    content(id, [#text(size: 9pt, label)])
  }

  rect((rel: (-1.25 + 1, +1.5), to: "execute"), (rel: (1.25 + 1, +2.5), to: "execute"), name: "regfile")
  content("regfile", [#text(size: 9pt, "RegFile")])

  rect((rel: (-1.25, -1.5), to: "fetch"), (rel: (1.25, -2.5), to: "fetch"), name: "icache")
  content("icache", [#text(size: 9pt, "iCache")])

  rect((rel: (-1.25, -1.5), to: "mem"), (rel: (1.25, -2.5), to: "mem"), name: "dcache")
  content("dcache", [#text(size: 9pt, "dCache")])

  line("fetch", "decode", mark: (end: "straight"), label: [#text(size: 7pt, "96bit")], label-side: left)
  line("decode", "execute", mark: (end: "straight"), label: [#text(size: 7pt, "292bit")], label-side: left)
  line("execute", "mem", mark: (end: "straight"), label: [#text(size: 7pt, "174bit")], label-side: left)
  line("mem", "wb", mark: (end: "straight"), label: [#text(size: 7pt, "135bit")], label-side: left)

  line("icache", "fetch", mark: (end: "straight"))
  line("dcache", "mem", mark: (symbol: "straight"), bend: -20)

  line("ctrl", (rel: (0, -2), to: "ctrl"), stroke: (dash: "dashed"))
  content((rel: (0, -1), to: "ctrl"), [#text(size: 10pt, "valid信号")])

  line("regfile.west", "decode.north", mark: (symbol: "straight"))
  line("wb.north", "regfile.east", mark: (symbol: "straight"))
})]

*模块间数据通路：*

各阶段间通过总线（pipeline register）传递数据，总线宽度设计如下：

#table(
  columns: (1fr, 1fr, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*总线*], [*位宽*], [*主要内容*],
  [`if_id_bus`], [96], [`pc_plus4`(32) + `pc`(32) + `inst`(32)],
  [`id_exe_bus`], [292], [PC信息 + 控制标志 + ALU控制 + 操作数 + 寄存器值 + 指令],
  [`exe_mem_bus`], [174], [PC信息 + 结果 + 控制标志 + 访存参数 + store数据],
  [`mem_wb_bus`], [135], [PC信息 + 控制标志 + 写回地址 + 写回数据],
)

总线数据在阶段完成时锁存到对应的流水线寄存器（`if_id_bus_r`等），保证时序切换时数据稳定。

*PC更新逻辑（在顶层）：*

#move(dx: 2em)[
  - 非法指令：`PC ← PC + 4`
  - 分支/跳转且taken：`PC ← exe_branch_target`
  - 其他：`PC ← exe_pc_plus4`（即PC + 4）
]

= 仿真验证

== 测试程序

使用汇编程序`icache_init.s`进行综合测试，覆盖全部37条指令：

#move(dx: 2em)[
  + R-Type运算：add, sub, sll, slt, sltu, xor, srl, sra, or, and
  + I-Type运算：addi, slti, sltiu, xori, ori, andi, slli, srli, srai
  + U-Type：lui, auipc
  + Store：sw, sb, sh
  + Load：lw, lb, lbu, lh, lhu
  + Branch：beq, bne, blt, bge, bltu, bgeu
  + Jump：jal, jalr
]

== 测试结果

测试台运行5000个时钟周期后检查寄存器和内存值：

#table(
  columns: (2fr, 2fr, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*检查项*], [*期望值*], [*结果*],
  [x1 (addi x1, x0, 5)], [0x00000037], [PASS],
  [x2 (addi x2, x0, 7)], [0x00000400], [PASS],
  [x10 (sra x10, x8, x1)], [0x00000037], [PASS],
  [x14 (sltiu x14, x1, -1)], [0x0000000A], [PASS],
  [mem[0x3E8] (sw结果)], [0x00000059], [PASS],
  [mem[0x3EC] (fib结果)], [0x00000037], [PASS],
)

*iverilog仿真：pass=33, fail=0, ALL TESTS PASSED*

*Vivado xsim（BRAM IP核）：pass=33, fail=0, ALL TESTS PASSED*

== BRAM延迟适配

从行为级模型切换到BRAM IP核后，由于BRAM具有1周期同步读延迟，进行了以下修改：

#table(
  columns: (auto, auto, auto),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*操作*], [*原始周期*], [*修改后周期*],
  [取指（FETCH）], [1], [2（r\_bram\_sent等待）],
  [读内存（lw/lb/lh）], [2（IDLE→ READ）], [3（IDLE→ READ→ READ2）],
  [写内存（sw/sb/sh）], [3（IDLE→ MODIFY→ COMMIT）], [4（IDLE→ MODIFY→ MODIFY2→ COMMIT）],
)

= FPGA上板

== 显示模块

`simple_cpu_display.v`将CPU连接到FPGA开发板的LCD触摸屏，实现交互式调试：

#move(dx: 2em)[
  - 显示区域1-8：各阶段PC和指令（IF\_PC, IF\_IN, ID\_PC, EXE\_PC, MEM\_PC, MEM\_IN, WB\_PC, WB\_IN）
  - 显示区域9-10：内存观察地址和对应数据
  - 显示区域11-42：32个通用寄存器值
  - 显示区域43：CPU FSM状态
  - 显示区域44：拨码开关状态
  - 触摸屏输入：可设置内存观察地址
]

== 引脚约束

使用`cpu.xdc`约束文件，适配xc7a200tfbg676-2器件，LCD触摸屏和拨码开关引脚已绑定。

= 结论

本项目成功实现了一个32位RISC-V多周期处理器核，主要成果如下：

#move(dx: 2em)[
  + *指令集覆盖*：实现了RV32I中37条指令（除fence和中断相关），涵盖R/I/S/B/U/J全部格式
  + *多周期架构*：采用6状态FSM控制器驱动五级数据通路，不同指令类型跳过不需要的阶段以优化执行效率
  + *哈佛架构*：icache和dcache分别使用True Dual Port BRAM IP核，位宽32位、位深2048
  + *BRAM延迟适配*：通过在取指模块增加`r_bram_sent`等待标志、在访存模块增加`MEM_READ2`和`MEM_WRITE_MODIFY2`等待状态，解决了BRAM同步读延迟问题
  + *完整访存支持*：实现了byte/halfword/word的读写，支持符号扩展和零扩展，采用读-改-写策略处理子字写入
  + *验证通过*：iverilog行为级仿真和Vivado BRAM IP核仿真均通过全部33项测试
  + *FPGA上板*：通过LCD触摸屏实现交互式调试，可实时观察PC、指令、寄存器和内存状态
]
