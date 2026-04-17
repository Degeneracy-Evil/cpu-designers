# 09 - 代码规范

## 1. 通用规范

1. 使用统一、清晰、可读的模块命名与信号命名
2. 模块接口命名体现信号用途，不使用语义不明的缩写
3. 时序逻辑与组合逻辑必须分离书写
4. 状态机使用三段式写法（状态转移、下一状态逻辑、输出逻辑）
5. 严禁未经说明地复制第三方现成 CPU 实现
6. ALU 必须使用项目已有实现

## 2. 命名规范

### 2.1 模块命名

- 小写字母，下划线分隔
- 例：`pc_reg`、`main_control`、`alu_wrapper`

### 2.2 信号命名

- 输入/输出信号：小写，有意义（例：`instr`、`alu_result`）
- 内部 wire/reg：小写，下划线分隔
- 参数：大写，下划线分隔（例：`DATA_WIDTH`）
- 状态参数：大写，下划线分隔（例：`FETCH`、`DECODE`）

### 2.3 文件命名

- 与模块名一致，`.v` 后缀
- 测试平台：`tb_<module_name>.v`

## 3. 时序规范

- 统一使用 `timescale 1ns / 1ps`
- 时钟上升沿有效
- 高电平异步复位

## 4. 模块接口模板

### 4.1 组合逻辑模块

```verilog
module module_name(
    input  [N-1:0] input1,
    input  [M-1:0] input2,
    output [K-1:0] output1
);
```

### 4.2 时序逻辑模块

```verilog
module module_name(
    input         clk,
    input         reset,
    input  [N-1:0] data_in,
    output [M-1:0] data_out
);
```

## 5. 状态机模板

```verilog
localparam IDLE    = 3'b000;
localparam WORK    = 3'b001;
localparam DONE    = 3'b010;

reg [2:0] state, next_state;

always @(posedge clk or posedge reset) begin
    if (reset)
        state <= IDLE;
    else
        state <= next_state;
end

always @(*) begin
    case (state)
        IDLE:   next_state = ...;
        WORK:   next_state = ...;
        DONE:   next_state = ...;
        default: next_state = IDLE;
    endcase
end

always @(*) begin
    // 输出逻辑
end
```

## 6. 注释要求

核心模块必须附带必要注释：
- 模块功能
- 关键输入输出
- 关键状态或控制信号含义
