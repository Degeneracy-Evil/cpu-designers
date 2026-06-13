# $fwrite 完整代码模板

## 目录

1. [指令追踪器（Ibex RVFI 风格）](#1-指令追踪器ibex-rvfi-风格)
2. [指令追踪器（SCR1 管道信号风格）](#2-指令追踪器scr1-管管信号风格)
3. [流水线状态转储](#3-流水线状态转储)
4. [Cache 命中/缺失日志](#4-cache-命中缺失日志)
5. [AXI 总线事务日志](#5-axi-总线事务日志)
6. [Spike ISA Simulator 兼容格式](#6-spike-isa-simulator-兼容格式)
7. [异常/中断追踪](#7-异常中断追踪)
8. [多文件 MCD 广播](#8-多文件-mcd-广播)

---

## 1. 指令追踪器（Ibex RVFI 风格）

基于 RISC-V Formal Verification Interface (RVFI)，产生 objdump 兼容的反汇编输出。

**设计要点**：
- 惰性文件打开（首个有效指令时才打开）
- Plusarg 运行时控制
- 压缩/非压缩指令格式化
- 条件寄存器/内存访问记录

```systemverilog
`ifdef SIMULATION
module instr_trace_logger #(
    parameter XLEN = 32,
    parameter LOG_FILE = "instr_trace.log"
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                valid,          // 指令有效
    input  logic [XLEN-1:0]     pc,             // 当前 PC
    input  logic [31:0]         instr,          // 指令字
    input  logic [4:0]          rd_addr,        // 目标寄存器地址
    input  logic [XLEN-1:0]     rd_wdata,       // 目标寄存器写数据
    input  logic [4:0]          rs1_addr,        // 源寄存器 1 地址
    input  logic [XLEN-1:0]     rs1_rdata,       // 源寄存器 1 数据
    input  logic [4:0]          rs2_addr,        // 源寄存器 2 地址
    input  logic [XLEN-1:0]     rs2_rdata,       // 源寄存器 2 数据
    input  logic [XLEN-1:0]     mem_addr,       // 内存访问地址
    input  logic [XLEN-1:0]     mem_wdata,      // 内存写数据
    input  logic [XLEN-1:0]     mem_rdata,      // 内存读数据
    input  logic                mem_write,      // 内存写使能
    input  logic                mem_read        // 内存读使能
);

    int fd;
    logic enable;
    int unsigned cycle_cnt;

    // RISC-V ABI 寄存器名
    function automatic string reg_to_abi(input logic [4:0] addr);
        case (addr)
            5'd0:  return "zero";
            5'd1:  return "ra";
            5'd2:  return "sp";
            5'd3:  return "gp";
            5'd4:  return "tp";
            5'd5:  return "t0";
            5'd6:  return "t1";
            5'd7:  return "t2";
            5'd8:  return "s0/fp";
            5'd9:  return "s1";
            5'd10: return "a0";
            5'd11: return "a1";
            5'd12: return "a2";
            5'd13: return "a3";
            5'd14: return "a4";
            5'd15: return "a5";
            5'd16: return "a6";
            5'd17: return "a7";
            5'd18: return "s2";
            5'd19: return "s3";
            5'd20: return "s4";
            5'd21: return "s5";
            5'd22: return "s6";
            5'd23: return "s7";
            5'd24: return "s8";
            5'd25: return "s9";
            5'd26: return "s10";
            5'd27: return "s11";
            5'd28: return "t3";
            5'd29: return "t4";
            5'd30: return "t5";
            5'd31: return "t6";
            default: return "x??";
        endcase
    endfunction

    // 运行时控制
    initial begin
        enable = 1'b1;
        void'($value$plusargs("instr_trace=%b", enable));
        fd = 0;
        cycle_cnt = 0;
    end

    // 惰性文件打开 + 主追踪循环
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycle_cnt <= 0;
        end else begin
            cycle_cnt <= cycle_cnt + 1;
            if (valid && enable) begin
                // 惰性打开：首个有效指令时才打开文件
                if (fd == 0) begin
                    fd = $fopen(LOG_FILE, "w");
                    $fwrite(fd, "# Instruction Trace Log\n");
                    $fwrite(fd, "# Time\tCycle\tPC\t\tInstr\t\tDecoded\tRegs/Mem\n");
                    $display("[TRACE] Writing instruction trace to %s", LOG_FILE);
                end

                // 写追踪行
                $fwrite(fd, "%15t\t%0d\t%08h\t%08h",
                        $time, cycle_cnt, pc, instr);

                // 寄存器读
                if (rs1_addr != 0)
                    $fwrite(fd, "\t%s:0x%08h", reg_to_abi(rs1_addr), rs1_rdata);
                if (rs2_addr != 0)
                    $fwrite(fd, "\t%s:0x%08h", reg_to_abi(rs2_addr), rs2_rdata);

                // 寄存器写
                if (rd_addr != 0)
                    $fwrite(fd, "\t%s=0x%08h", reg_to_abi(rd_addr), rd_wdata);

                // 内存访问
                if (mem_write)
                    $fwrite(fd, "\tPA:0x%08h store:0x%08h", mem_addr, mem_wdata);
                if (mem_read)
                    $fwrite(fd, "\tPA:0x%08h load:0x%08h", mem_addr, mem_rdata);

                $fwrite(fd, "\n");

                // 定期刷新
                if (cycle_cnt % 10000 == 0) $fflush(fd);
            end
        end
    end

    // 确保文件关闭
    final begin
        if (fd != 0) $fclose(fd);
    end

endmodule
`endif
```

**输出示例**：
```
              5ns    1   00000004    00500093    a0:0x00000000  a0=0x00000005
             10ns    2   00000008    0000a103    a1:0x00000005  PA:0x00000005 load:0x00000042
```

---

## 2. 指令追踪器（SCR1 管道信号风格）

直接从 CPU 管道信号追踪，不依赖 RVFI 接口。适合本项目 `tb_soc_includes.svh` 已暴露的信号。

```systemverilog
`ifdef DEBUG_TRACE
    integer trace_fd;
    integer trace_cycle;
    logic   trace_enable;

    initial begin
        trace_enable = 1'b1;
        void'($value$plusargs("trace_enable=%b", trace_enable));
        if (trace_enable) begin
            trace_fd = $fopen("tracelog_core.log", "w");
            $fwrite(trace_fd, "# RTL Trace Log\n");
            $fwrite(trace_fd, "# Events: N=normal BR=branch TR=trap MR=mret\n");
            $fwrite(trace_fd, "#           Time  Ev  Curr_PC   Instr     Next_PC   Reg       Value\n");
        end
        trace_cycle = 0;
    end

    // 复位标记
    always @(posedge resetn) begin
        if (trace_enable)
            $fwrite(trace_fd, "# ======== Core Reset at time %0d ========\n", $time);
    end

    // 主追踪：IF→ID 阶段
    always @(posedge clk) begin
        if (resetn && trace_enable) begin
            trace_cycle = trace_cycle + 1;

            if (u_soc.cpu.if_done) begin
                // 写公共头
                $fwrite(trace_fd, "%16d  ", $time);
                $fwrite(trace_fd, " %s  ",
                    u_soc.cpu.exe_branch_taken ? "BR" :
                    u_soc.u_trap_csr.u_trap_mgr.trap_pending ? "TR" : "N ");
                $fwrite(trace_fd, " %08x  ", if_pc);
                $fwrite(trace_fd, " %08x  ", if_inst);
                $fwrite(trace_fd, " %08x  ", if_pc + 32'd4);

                // WB 阶段寄存器写回（如果有）
                if (u_soc.cpu.wb_reg_we && u_soc.cpu.wb_reg_addr != 0) begin
                    // 写 ABI 寄存器名
                    case (u_soc.cpu.wb_reg_addr)
                        0:  $fwrite(trace_fd, " ---        --------");
                        1:  $fwrite(trace_fd, " x01_ra    %08x", u_soc.cpu.wb_reg_wdata);
                        2:  $fwrite(trace_fd, " x02_sp    %08x", u_soc.cpu.wb_reg_wdata);
                        // ... 省略 3-30，见 SKILL.md 中 trace_reg_name task
                        31: $fwrite(trace_fd, " x31_t6    %08x", u_soc.cpu.wb_reg_wdata);
                        default: $fwrite(trace_fd, " x%0d       %08x", u_soc.cpu.wb_reg_addr, u_soc.cpu.wb_reg_wdata);
                    endcase
                end else begin
                    $fwrite(trace_fd, " ---        --------");
                end
                $fwrite(trace_fd, "\n");

                if (trace_cycle % 10000 == 0) $fflush(trace_fd);
            end
        end
    end

    final begin
        if (trace_fd != 0) $fclose(trace_fd);
    end
`endif
```

**输出示例**：
```
           1250   N   00000004  00500093  00000008  x10_a0  00000005
           1300   BR  00000040  00000113  00000044  x2_sp   00001000
           5000   TR  80000100  34029073  80000104  ---     --------
```

---

## 3. 流水线状态转储

每周期转储五级流水线各阶段的 PC 和指令。

```systemverilog
`ifdef DEBUG_PIPELINE
    integer pipe_fd;
    integer pipe_cycle;

    initial begin
        pipe_fd = $fopen("pipeline_state.log", "w");
        $fwrite(pipe_fd, "# Pipeline State Dump\n");
        $fwrite(pipe_fd, "# Cycle  IF_PC      IF_Inst    ID_PC      ID_Inst    EX_PC      EX_Inst    MEM_PC     MEM_Inst   WB_PC      WB_Inst\n");
        pipe_cycle = 0;
    end

    always @(posedge clk) begin
        if (resetn) begin
            pipe_cycle = pipe_cycle + 1;
            $fwrite(pipe_fd, "%0d\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\n",
                    pipe_cycle,
                    if_pc,  if_inst,
                    id_pc,  id_inst,
                    exe_pc, exe_inst,
                    mem_pc, mem_inst,
                    wb_pc,  wb_inst);
            if (pipe_cycle % 10000 == 0) $fflush(pipe_fd);
        end
    end

    final begin
        if (pipe_fd != 0) $fclose(pipe_fd);
    end
`endif
```

---

## 4. Cache 命中/缺失日志

```systemverilog
`ifdef DEBUG_CACHE
    integer cache_fd;

    initial begin
        cache_fd = $fopen("cache_access.log", "w");
        $fwrite(cache_fd, "# Cache Access Log\n");
        $fwrite(cache_fd, "# H=Hit M=Miss E=Evict I=Invalidate\n");
        $fwrite(cache_fd, "# Cycle  PC         Type  Result  Way  Tag\n");
    end

    always @(posedge clk) begin
        if (resetn) begin
            // I-Cache 访问
            if (u_soc.cpu.if_done) begin
                $fwrite(cache_fd, "%0d\t%08h\tI\t%s\t%0d\t%08h\n",
                        trace_cycle, if_pc,
                        u_soc.u_icache_wrap.hit ? "H" : "M",
                        u_soc.u_icache_wrap.way_sel,
                        u_soc.u_icache_wrap.tag_out);
            end

            // D-Cache 访问
            if (u_soc.cpu.dcache_req_valid) begin
                $fwrite(cache_fd, "%0d\t%08h\tD\t%s\t%0d\t%08h\n",
                        trace_cycle, exe_pc,
                        u_soc.u_dcache_wrap.hit ? "H" : "M",
                        u_soc.u_dcache_wrap.way_sel,
                        u_soc.u_dcache_wrap.tag_out);
            end
        end
    end

    final begin
        if (cache_fd != 0) $fclose(cache_fd);
    end
`endif
```

---

## 5. AXI 总线事务日志

```systemverilog
`ifdef DEBUG_AXI
    integer axi_fd;
    integer axi_aw_cnt, axi_ar_cnt;

    initial begin
        axi_fd = $fopen("axi_transactions.log", "w");
        $fwrite(axi_fd, "# AXI Bus Transaction Log\n");
        $fwrite(axi_fd, "# Type  Time  Addr       Data       Len  Size  Burst\n");
        axi_aw_cnt = 0;
        axi_ar_cnt = 0;
    end

    // AW 通道写事务
    always @(posedge clk) begin
        if (u_soc.cpu.u_bus_bridge.ahb_inst_valid_r) begin
            $fwrite(axi_fd, "AW\t%0t\t%08h\t%08h\t%0d\t%0d\t%0d\n",
                    $time,
                    u_soc.cpu.u_bus_bridge.addr_r,
                    u_soc.cpu.u_bus_bridge.ahb_inst_data_r,
                    0, 2, 1);  // len=0, size=2(4B), burst=1(INCR)
            axi_aw_cnt = axi_aw_cnt + 1;
        end
    end

    final begin
        $fwrite(axi_fd, "# Summary: AW=%0d AR=%0d\n", axi_aw_cnt, axi_ar_cnt);
        if (axi_fd != 0) $fclose(axi_fd);
    end
`endif
```

---

## 6. Spike ISA Simulator 兼容格式

生成与 Spike commit log 完全兼容的格式，用于 co-simulation 验证。

```systemverilog
`ifdef DEBUG_SPIKE
    integer spike_fd;

    initial begin
        spike_fd = $fopen("spike_commit.log", "w");
    end

    // Spike commit log 格式: <priv> <pc> (<inst_hex>) <rd> <value>
    // 例: 3 0x80000118 (0x00500093) x1 0x00000005
    always @(posedge clk) begin
        if (resetn && u_soc.cpu.wb_done) begin
            // 确定特权级
            $fwrite(spike_fd, "%0d 0x%08h (0x%08h)",
                    u_soc.cpu.priv_level,  // 0=U, 3=M
                    wb_pc, wb_inst);

            // 如果有寄存器写回
            if (u_soc.cpu.wb_reg_we && u_soc.cpu.wb_reg_addr != 0) begin
                $fwrite(spike_fd, " x%0d 0x%08h",
                        u_soc.cpu.wb_reg_addr,
                        u_soc.cpu.wb_reg_wdata);
            end
            $fwrite(spike_fd, "\n");

            if (trace_cycle % 10000 == 0) $fflush(spike_fd);
        end
    end

    final begin
        if (spike_fd != 0) $fclose(spike_fd);
    end
`endif
```

**对比方法**：
```bash
# 生成 Spike 参考追踪
spike --log-commits binary.elf 2> spike_ref.log

# 提取 PC 和指令进行对比
diff <(awk '{print $2, $3}' spike_commit.log) <(awk '{print $2, $3}' spike_ref.log)
```

---

## 7. 异常/中断追踪

```systemverilog
`ifdef DEBUG_TRAP
    integer trap_fd;

    initial begin
        trap_fd = $fopen("trap_events.log", "w");
        $fwrite(trap_fd, "# Trap/Exception/Interrupt Log\n");
        $fwrite(trap_fd, "# Time  Cycle  Event       PC         Cause      Priv  mstatus    mepc\n");
    end

    always @(posedge clk) begin
        if (resetn) begin
            // 异常进入
            if (u_soc.u_trap_csr.u_trap_mgr.trap_pending &&
                !u_soc.u_trap_csr.u_trap_mgr.trap_pending_r) begin
                $fwrite(trap_fd, "%0t\t%0d\tTRAP_ENTER\t%08h\t%08h\t%0d\t%08h\t%08h\n",
                        $time, trace_cycle,
                        exe_pc,
                        u_soc.u_trap_csr.u_trap_mgr.trap_cause,
                        u_soc.cpu.priv_level,
                        u_soc.u_trap_csr.u_csr_if.u_csr.r_mstatus,
                        u_soc.u_trap_csr.u_csr_if.u_csr.r_mepc);
                $fflush(trap_fd);
            end

            // MRET 返回
            if (u_soc.cpu.exe_done && u_soc.cpu.exe_is_mret) begin
                $fwrite(trap_fd, "%0t\t%0d\tMRET\t\t%08h\t--------\t%0d\t%08h\t%08h\n",
                        $time, trace_cycle,
                        exe_pc,
                        u_soc.cpu.priv_level,
                        u_soc.u_trap_csr.u_csr_if.u_csr.r_mstatus,
                        u_soc.u_trap_csr.u_csr_if.u_csr.r_mepc);
                $fflush(trap_fd);
            end
        end
    end

    final begin
        if (trap_fd != 0) $fclose(trap_fd);
    end
`endif
```

---

## 8. 多文件 MCD 广播

同时写入多个文件 + stdout（使用 Multi-Channel Descriptor）。

```systemverilog
`ifdef SIMULATION
    integer mcd_trace;   // 追踪日志 MCD
    integer mcd_detail;  // 详细日志 MCD
    integer mcd_all;     // 广播 MCD

    initial begin
        mcd_trace  = $fopen("trace.log");   // 不指定模式 → MCD
        mcd_detail = $fopen("detail.log");
        mcd_all    = mcd_trace | mcd_detail | 32'b1;  // OR 合并，bit 0 = stdout

        // 广播到所有文件 + stdout
        $fwrite(mcd_all, "Simulation started at %0t\n", $time);
    end

    // ⚠️ 必须逐个关闭，不能对 ORed MCD 调用 $fclose（会崩溃）
    final begin
        $fclose(mcd_trace);
        $fclose(mcd_detail);
    end
`endif
```

---

## 外部项目参考

| 项目 | 追踪模块 | 格式 | 关键特性 |
|------|---------|------|---------|
| **SCR1** (Syntacore) | `scr1_tracelog.sv` | 自定义文本 | ABI 寄存器名、事件分类 (N/E/I/W)、CSR 状态 |
| **Ibex** (lowRISC) | `ibex_tracer.sv` | Tab 分隔 | RVFI 接口、完整指令解码、plusarg 控制 |
| **CVA6** (OpenHW) | `rvfi_tracer.sv` | DASM 格式 | Spike commit log 兼容、多 commit 端口 |
| **CVW/Wally** (OpenHW) | `loggers.sv` | 自定义文本 | ICache/DCache H/M/E 分类、分支预测日志 |
| **PicoRV32** (YosysHQ) | testbench.v | 二进制 hex | 超轻量 36-bit trace_data |
| **RSD** | `Dumper.sv` | Kanata 格式 | 逐周期流水线阶段转储 |
