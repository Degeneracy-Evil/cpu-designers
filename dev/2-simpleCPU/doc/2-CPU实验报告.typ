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
  align(center)[#text(size: 18pt)[负责人：王之翼#h(1em)18996388318\    张潘妍    张之恒    陈海攀]]
  align(center)[#text(size: 18pt)[2024级计算机一班#h(1em)课序3第4组#h(1em)2026年4月21日]]
  align(center)[#text(size: 14pt)[（分工表见最后）]]
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
simplecpu_bus/simplecpu_bus.srcs/sources_1/imports/
├─dev
│  ├─1-alu
│  │  └─rtl
│  │          alu_32bit.v               ALU顶层
│  │          alu_result_selector.v     ALU结果选择
│  │          booth_multiplier.v        booth乘法器
│  │          cla_adder_16bit.v         超前进位加法器
│  │          cla_adder_32bit.v
│  │          cla_adder_4bit.v
│  │          logic_unit.v              逻辑运算
│  │          lui.v                     加载
│  │          mux.v                     选择器
│  │          non_restoring_divider.v   除法器
│  │          shifter.v                 位移器
│  │          subtractor.v              减法器
│  │
│  └─2-simpleCPU
│      ├─fpga
│      │      lcd_module.dcp            显示屏模块
│      │
│      ├─program_source                 程序文件夹
│      │      fib10.coe                 斐波那契数列第10位
│      │      icache_init.coe           命令测试
│      │
│      └─rtl
│              branch_comparator.v      分支比较器
│              cpu_controller.v         控制器
│              cpu_decode.v             解码器
│              cpu_execute.v            执行模块
│              cpu_fetch.v              取指模块
│              cpu_mem.v                访存模块
│              cpu_regfile.v            寄存器堆
│              cpu_wb.v                 回写模块
│              op_regroup.v             指令切分
│              simple_cpu_top.v         cpu核顶层
│
└─fpga
        simple_cpu_display.v            项目顶层，显示模块

program_source/
    fib10.c                             斐波那契数列程序源码
    fib10.coe
    fib10.ld
    icache_init.coe
    icache_init.hex
    icache_init.s                       指令测试程序源码
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
总大小为8KB。`iCache，dCache`分别实例化了一个BRAM IP核。

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
  content("2t1", anchor: "north", padding: .1, [#text(size: 10pt, "err_op")])
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

取指模块负责从icache中读取当前PC对应的指令字，并将PC+4。

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

取指模块同时会将PC+4的结果计算并沿总线传递，采取这个设计的原因是除了分支指令都需要这个值，且ALU排班已满，无法添加调用，但是如果直接修改PC寄存器又会导致分支指令需要额外做减法，造成时序负担。

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
```]
#move(dx: 2em)[```v
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
#move(dx: 2em)[
  - `is_branch`：6条分支指令
  - `is_load`：5条Load指令
  - `is_store`：3条Store指令
  - `is_jal_like`：JAL、JALR
  - `is_alu`：所有需要ALU运算的指令（含LUI、AUIPC、Load、Store的地址计算）
]

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

*执行流程：*

#move(dx: 2em)[
  + `use_fixed_wb`为真（如LUI指令）：直接使用`wb_fixed_data`作为结果，1周期完成
  + 否则：向ALU发`req_valid`，等待`result_valid`，采样`alu_result`
]

*分支与跳转处理：*
#move(dx: 2em)[
  - `branch_comparator`模块根据`branch_funct3`和`rs1_value/rs2_value`判断分支条件是否成立
  - 分支目标地址：ALU计算`pc + imm_b`的结果
  - JALR目标地址：`alu_result & 0xFFFFFFFE`（清除最低位）
  - `exe_branch_taken`：分支指令取`branch_cond_true`，JAL/JALR指令取1
]
#move(dx: 2em)[
  - `exe_is_ctrl_flow`：分支或跳转指令时为1，通知顶层更新PC
]

=== 分支比较器（branch\_comparator）

我们采用独立的分支比较器协助处理分支语句的计算任务。分枝比较器内部内部是大小比较器，纯组合逻辑模块，根据`branch_funct3`和两个操作数判断分支条件是否成立。

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

ALU模块基于上一次实验的结果进行了改进，主要是添加了握手逻辑以支持多周期运算的交互。

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

当`use_fixed_wb=1`（LUI指令）时，跳过ALU握手，直接将`wb_fixed_data`锁存为结果，1周期完成。

*控制编码（one-hot，bit0保留）：*

#move(dx: 2em)[#table(
  columns: (auto, auto, auto, auto, auto, auto, auto, auto),
  align: center,
  stroke: 0.5pt,
  inset: 4pt,
  [*15*], [*14*], [*13*], [*12*], [*11*], [*10*], [*9*], [*8*],
  [MUL], [DIV], [NOT], [ADD], [SUB], [SLT], [SLTU], [AND],
  [*7*], [*6*], [*5*], [*4*], [*3*], [*2*], [*1*], [*0*],
  [NOR], [OR], [XOR], [SLL], [SRL], [SRA], [LUI], [—],
)]

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
  content("l4", anchor: "south", padding: .1, [#text(size: 10pt, "done")])

  line("wmod", "wmod2", mark: (end: "straight"), name: "l5")
  content("l5", anchor: "south", padding: .1, [#text(size: 10pt, "1 cycle")])

  line("wmod2", "wcommit", mark: (end: "straight"), name: "l6")
  content("l6", anchor: "south", padding: .1, [#text(size: 10pt, "1 cycle")])

  line(
    "wcommit",
    "idle",
    mark: (end: "straight"),
    name: "l7",
  )
  content(("l7.start", 50%, "l7.end"), angle: "l7.start", padding: .1, anchor: "north", [#text(size: 10pt, "done")])

  // line(
  //   (rel: (-0.8, 0), to: "idle.north"),
  //   (rel: (-0.8, 1.5), to: "idle.north"),
  //   (rel: (0.8, 1.5), to: "read2.north"),
  //   (rel: (0.8, 0), to: "read2.north"),
  //   mark: (end: "straight"),
  //   stroke: (dash: "dashed"),
  //   name: "lb1",
  // )
  // content("lb1", anchor: "south", padding: .1, [#text(size: 10pt, "!is_load&&!is_store→done")])

  // line(
  //   (rel: (0, -0.3), to: "idle.east"),
  //   (rel: (0, 0.3), to: "wmod2.west"),
  //   mark: (end: "straight"),
  //   stroke: (dash: "dashed"),
  //   name: "lb2",
  // )
  // content("lb2", anchor: "north", padding: .1, [#text(size: 10pt, "misalign→done")])
})]

*非访存指令快速通过：*

当`!is_load && !is_store`时，直接将ALU结果作为回写数据，1周期完成。

*地址未对齐检测：*

- LH/LHU：地址最低位不为0
- LW/SW：地址最低2位不为00
- 检测到未对齐时，认为出错，取消写回使能，直接完成。

*Load数据提取与扩展：*

根据`mem_size`和`mem_unsigned`从BRAM读出的32位字中提取对应字节/半字，并进行符号扩展或零扩展：
- byte：按`byte_offset`选择8位，符号扩展或零扩展至32位
- halfword：按`byte_offset[1]`选择16位，符号扩展或零扩展至32位
- word：直接使用32位

*Store读-改-写：*

对于SB/SH指令，需要先读出原32位字，再将待写数据合并到对应字节位置，最后写回整个字。合并逻辑根据`mem_size`和`byte_offset`进行字节级拼接。

#move(dx: 2em)[```v
wire [31:0] store_merged_word;
assign store_merged_word = (mem_size_reg == 3'b010) ? wdata_reg : (mem_size_reg == 3'b001) ? (byte_offset[1] ? {wdata_reg[15:0], mem_word_for_extract[15:0]} : {mem_word_for_extract[31:16], wdata_reg[15:0]}) : (byte_offset == 2'b00) ? {mem_word_for_extract[31:8], wdata_reg[7:0]} : (byte_offset == 2'b01) ? {mem_word_for_extract[31:16], wdata_reg[7:0], mem_word_for_extract[7:0]} : (byte_offset == 2'b10) ? {mem_word_for_extract[31:24], wdata_reg[7:0], mem_word_for_extract[15:0]} : {wdata_reg[7:0], mem_word_for_extract[23:0]};
```]

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
  columns: (auto, auto, 1fr, 2fr),
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

== 寄存器堆

寄存器堆直接使用verilog声明寄存器，其中x0寄存器通过在读写时添加限制逻辑保证其恒为零。

主要驱动代码如下：

#move(dx: 2em)[
  ```v
      reg [31:0] rf[0:31];
      integer i;
      always @(posedge clk or posedge reset) begin
          if (reset) begin
              for (i = 0; i < 32; i = i + 1) begin
                  rf[i] <= 32'b0;
              end
          end else if (wen && (waddr != 5'd0)) begin
              rf[waddr] <= wdata;
          end
      end
      assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : rf[raddr1];
      assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : rf[raddr2];
      assign dbg_rdata = (dbg_raddr == 5'd0) ? 32'b0 : rf[dbg_raddr];
  ```
]

== 结构总览

#align(center)[#cetz.canvas({
  import cetz.draw: *

  let box_w = 2.4
  let box_h = 1.0
  let gap_x = 1
  let gap_y = 1.2

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

  rect((rel: (-1.25 + 1, +1.5), to: "execute"), (rel: (1.25 + 1, +2.5), to: "execute"), fill: gray, name: "regfile")
  content("regfile", [#text(size: 9pt, "RegFile")])

  rect((rel: (-1.25, -1.5), to: "fetch"), (rel: (1.25, -2.5), to: "fetch"), fill: gray, name: "icache")
  content("icache", [#text(size: 9pt, "iCache")])

  rect((rel: (-1.25, -1.5), to: "mem"), (rel: (1.25, -2.5), to: "mem"), fill: gray, name: "dcache")
  content("dcache", [#text(size: 9pt, "dCache")])

  rect((rel: (-1.25, 1.5), to: "fetch"), (rel: (1.25, 2.5), to: "fetch"), name: "ctrl")
  content("ctrl", [#text(size: 9pt, "Controller")])

  line("fetch", "decode", mark: (end: "straight"), name: "lfd")
  content("lfd", anchor: "south", padding: .1, text(size: 9pt, "96bit"))
  line("decode", "execute", mark: (end: "straight"), name: "lde")
  content("lde", anchor: "south", padding: .1, text(size: 9pt, "292bit"))
  line("execute", "mem", mark: (end: "straight"), name: "lem")
  content("lem", anchor: "south", padding: .1, text(size: 9pt, "174bit"))
  line("mem", "wb", mark: (end: "straight"), name: "lmw")
  content("lmw", anchor: "south", padding: .1, text(size: 9pt, "135bit"))

  line("icache", "fetch", mark: (end: "straight"))
  line("dcache", "mem", mark: (symbol: "straight"), bend: -20)

  line("ctrl.south", "fetch", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "decode.north", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "execute.north", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "mem.north", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "wb.north", stroke: (dash: "dashed"), mark: (end: "straight"))
  set-style(content: (frame: "rect", stroke: none, fill: white, padding: .05))
  content((rel: (1.8, -0.9), to: "ctrl"), [#text(size: 12pt, "valid信号")])

  line("regfile.west", "decode.north", mark: (end: "straight"))
  line("wb.north", "regfile.east", mark: (end: "straight"))
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

PC寄存器以及其更新逻辑定义在在顶层(`simple_cpu_top.v`)：

#move(dx: 2em)[
  - 非法指令：`PC ← PC + 4`
  - 分支/跳转：`PC ← exe_branch_target`
  - 其他：`PC ← exe_pc_plus4`（即PC + 4）
]

= 仿真验证

== 测试程序

使用汇编程序`icache_init.s`（在压缩包中`program_source`下）进行综合测试，覆盖全部37条指令：

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
#image("media/cpu1-波形.png")
#figure(
  image("media/cpu1-控制台.png", height: 55%),
  caption: [Vivado xsim（BRAM IP核）：pass=33, fail=0, ALL TESTS PASSED],
)

= FPGA验证

== 显示模块

`simple_cpu_display.v`将CPU连接到FPGA开发板的LCD触摸屏，实现交互式调试：

#move(dx: 2em)[
  - 显示区域1-8：各阶段PC和指令（IF\_PC, IF\_IN, ID\_PC, EXE\_PC, MEM\_PC, MEM\_IN, WB\_PC, WB\_IN）
  - 显示区域9-10：内存观察地址和对应数据
  - 显示区域11-42：32个通用寄存器值
  - 显示区域43：CPU FSM状态
  - 显示区域44：拨码开关状态
  - 触摸屏输入：可设置内存观察地址
  - 使用btn_clk步进调试（即SW_STEP2按钮）
]

#figure(image("media/debug.jpg"), caption: [现在正在执行第3条指令`0xfe010113`，刚刚完成访存以及pc更新])

== 求斐波那契数列第10位

我们使用C语言程序求斐波那契数列第十位，源代码为：
#align(center)[```c
__attribute__((noinline))
static unsigned int fib10(void)
{
    unsigned int a = 0;
    unsigned int b = 1;
    for (unsigned int i = 0; i < 10; i++) {
        unsigned int t = a + b;
        a = b;
        b = t;
    }
    return a;
}
__attribute__((naked, noreturn, section(".text.start")))
void _start(void)
{
    __asm__ volatile(
        "addi sp, x0, 1024\n"
        "jal ra, fib10\n"
        "addi x1, a0, 0\n"
        "1:\n"
        "jal x0, 1b\n"
    );
}
```]
文件为fib10.c，源代码也打包在压缩包中。

使用`gcc-riscv64-unknown-elf`组件进行编译，通过`objdump`提取比特流改为coe文件。在工程中icache组件配置处修改初始化coe文件，`simple_cpu_display.v`中注释掉btn_clk相关内容，改为由系统时钟驱动（压缩包中项目状态就是此状态）。

上板验证可见x1寄存器为我们期望的`0x37=55`，表明程序成功运行。

#figure(image("media/fib10-37.jpg",width: 90%), caption: [x1寄存器以及dcache的`0x3ec`处均为`0x37`])

#figure(image("media/fib10-55.jpg",width: 90%), caption: [dcache的`0x3e8`处为`0x59=89`即下一位])


== 引脚约束

约束文件为`cpu.xdc`，注意不使用SW_STEP2按钮时可能会有警告，可管可不管，需要解决的话就把btn_clk的约束注释即可。

= 性能计算

== 各阶段周期数分析

=== 取指阶段（FETCH）：2周期

icache使用BRAM IP核，具有1周期同步读延迟。取指模块通过`r_bram_sent`寄存器适配：

#move(dx: 2em)[
  - 沿1：`state_r`进入FETCH，`if_valid=1`，`icache_en=1`，地址有效，`r_bram_sent=0`
  - 沿2：BRAM锁存地址并输出数据，`r_bram_sent`置1，`if_done=1`，FSM转移至DECODE
]

=== 解码阶段（DECODE）：1周期

纯组合逻辑，`id_done = id_valid`，当拍完成。

=== 执行阶段（EXEC）

*LUI指令（`use_fixed_wb=1`，旁路ALU）：2周期*

#move(dx: 2em)[
  - 沿1：检测到`exe_valid`，直接锁存`wb_fixed_data`，`done_reg<=1`
  - 沿2：`exe_done=1`，FSM转移
]

*其他指令（需ALU握手）：4周期*

#move(dx: 2em)[
  - 沿1：`req_valid<=1`，`exe_active<=1`（发起ALU请求）
  - 沿2：ALU接收请求（`req_fire`），锁存组合结果，`result_valid_reg<=1`
  - 沿3：`result_valid=1`，执行模块采样结果，`done_reg<=1`
  - 沿4：`exe_done=1`，FSM转移
]

4周期来源：ALU握手协议引入3周期额外开销（请求发射→结果锁存→读取`done_reg`）。

=== 访存阶段（MEM）

*非访存指令（ALU/JAL/JALR）：2周期*

#move(dx: 2em)[
  - 沿1：`mem_valid`有效，检测到`!is_load && !is_store`，直通ALU结果，`done_reg<=1`
  - 沿2：`mem_done=1`，FSM转移至WB
]

*Load指令：4周期*

#move(dx: 2em)[
  - 沿1：MEM\_IDLE→MEM\_READ，设置dcache使能和地址
  - 沿2：MEM\_READ→MEM\_READ2，BRAM锁存地址
  - 沿3：MEM\_READ2→MEM\_IDLE，BRAM输出有效，采样数据，`done_reg<=1`
  - 沿4：`mem_done=1`，FSM转移至WB
]

*Store指令：5周期*

#move(dx: 2em)[
  - 沿1：MEM\_IDLE→MEM\_WRITE\_MODIFY，发起读请求（读-改-写）
  - 沿2：MEM\_WRITE\_MODIFY→MEM\_WRITE\_MODIFY2，BRAM锁存地址
  - 沿3：MEM\_WRITE\_MODIFY2→MEM\_WRITE\_COMMIT，BRAM输出有效，合并数据，发起写请求
  - 沿4：MEM\_WRITE\_COMMIT→MEM\_IDLE，BRAM执行写入，`done_reg<=1`
  - 沿5：`mem_done=1`，FSM转移至WB
]

=== 回写阶段（WB）：1周期

纯组合逻辑，`wb_done = wb_valid`，当拍完成。

== 各指令类型CPI

#table(
  columns: (1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  align: center,
  stroke: 0.5pt,
  inset: 6pt,
  [*指令类型*], [*FETCH*], [*DECODE*], [*EXEC*], [*MEM*], [*WB*], [*CPI*],
  [R-type ALU], [2], [1], [4], [2], [1], [#text(red)[10]],
  [I-type ALU], [2], [1], [4], [2], [1], [#text(red)[10]],
  [AUIPC], [2], [1], [4], [2], [1], [#text(red)[10]],
  [LUI], [2], [1], [2], [2], [1], [#text(red)[8]],
  [JAL / JALR], [2], [1], [4], [2], [1], [#text(red)[10]],
  [Branch], [2], [1], [4], [—], [—], [#text(red)[7]],
  [Load], [2], [1], [4], [4], [1], [#text(red)[12]],
  [Store], [2], [1], [4], [5], [1], [#text(red)[13]],
)

Branch指令跳过MEM和WB阶段（FSM: EXEC→FETCH），故CPI最低为7。LUI因旁路ALU握手，EXEC仅需2周期，CPI为8。Load和Store因BRAM读延迟和读-改-写策略，CPI最高。

== 平均CPI估算

采用推算指令混合比例（此占比仅供参考）：

#table(
  columns: (1fr, 1fr, 1fr, 1fr),
  align: center,
  stroke: 0.5pt,
  inset: 6pt,
  [*类别*], [*占比*], [*CPI*], [*加权*],
  [ALU], [40\%], [10], [4.0],
  [Load], [25\%], [12], [3.0],
  [Store], [10\%], [13], [1.3],
  [Branch], [20\%], [7], [1.4],
  [Jump], [5\%], [10], [0.5],
)

$ "平均CPI" = sum_i p_i dot "CPI"_i = 4.0 + 3.0 + 1.3 + 1.4 + 0.5 = #text(red)[10.2] $

$ "IPC" = 1 / "CPI" approx 0.098 $

若采用完全平均计算，则$"CPI"=10,"IPC"=0.1$。综上，CPI大概就是10左右。

== MIPS

每秒执行的百万条指令数：

$ "MIPS" = 10^8 / (10.2 times 10^6) approx #text(red)[9.804] $

= 遇到的问题以及解决

== BRAM延迟适配

我们最初开发使用的是iverilog进行模拟，使用的行为级模型模块模拟BRAM IP。由于没有料到BRAM具有1周期同步读延迟，导致切换到BRAM IP核后取指和访存模块失效。修改代码增加等待周期后可正常运行。详细周期修改见下：

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

最后模拟成功，结果和最终结构如上所述。

= 结论

本项目成功实现了一个32位RISC-V多周期处理器核，主要成果如下：

#move(dx: 2em)[  + *指令集覆盖*：实现了RV32I中37条指令（除fence和中断相关），涵盖R/I/S/B/U/J全部格式
  + *多周期架构*：采用6状态FSM控制器驱动五级数据通路，不同指令类型跳过不需要的阶段以优化执行效率
  + *哈佛架构*：icache和dcache分别使用True Dual Port BRAM IP核，位宽32位、位深2048
  + *BRAM延迟适配*：通过在取指模块增加`r_bram_sent`等待标志、在访存模块增加`MEM_READ2`和`MEM_WRITE_MODIFY2`等待状态，解决了BRAM同步读延迟问题
  + *完整访存支持*：实现了byte/halfword/word的读写，支持符号扩展和零扩展，采用读-改-写策略处理子字写入
  + *验证通过*：Vivado 采用 BRAM IP核仿真通过全部33项测试
  + *FPGA验证*：实际FPGA运行符合预期]

通过本次实验，我们深化认知了多周期CPU的基本结构、RISC-V指令集的特性以及层次化的设计方法。同时，也认知到了多周期CPU相对于单周期CPU的优势，以及认知到了流水线设计对于CPI的巨大影响。

此次实验，我们的CPU核功能满足需求，但流水线设计和时序逻辑上仍可优化。

= 组员以及分工

#table(
  columns: (1fr,2fr,2fr),
  align: horizon,
  [*姓名*],[*学号*],[*分工*],
  [王之翼],[320240944621],[构建],
  [陈海攀],[320230904051],[测试、DEBUG],
  [张潘妍],[320240944910],[c程序、riscv汇编交叉编译],
  [张之恒],[320240944971],[资料查找、文档整理],
)
