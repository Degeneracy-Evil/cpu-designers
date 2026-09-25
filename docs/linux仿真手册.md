# Linux SRAM 仿真操作方法

步骤 1：生成 OpenSBI + kernel + initramfs 平坦二进制镜像。

```sh
bash tools/compile_kernel.sh
```

产物为 `build/opensbi/platform/generic/firmware/fw_payload.bin`（OpenSBI 加载于 0x80000000，kernel payload 位于 0x80400000）。脚本最后会自动执行步骤 2 的 hex 转换。

步骤 2：将 bin 转换成 SRAM `$readmemh` 格式（如步骤 1 已自动完成可跳过）。

```sh
python3 tools/bin2hex.py build/opensbi/platform/generic/firmware/fw_payload.bin \
  build/program/firmware/fw_payload.hex
```

转换器按 little-endian 32-bit word 每行输出一个十六进制数，尾部不足 4 byte 时补零对齐。

步骤 3：可先运行 Linux 专用 testbench 编译烟雾测试（不需要 Linux 镜像）。首次使用需先创建 Vivado 工程；烟雾测试用的小程序 hex 由 test_builder 生成。

```sh
python3 -m tools.vivado project
python3 tools/test_builder.py --test integration/cpu_trap
python3 -m tools.vivado sim kernel_tb_compile_smoke
```

步骤 4：运行完整 SRAM 仿真。

```sh
# SRAM 仿真（默认 runtime 300s，可用 --runtime 覆盖）
python3 -m tools.vivado sim kernel_boot_sram

# DDR3 仿真变体（SIMU_USE_DDR=1，跳过校准）
python3 -m tools.vivado sim kernel_boot_ddr3

# 重复运行直接再次执行 sim 命令即可（复用已有工程）
python3 -m tools.vivado sim kernel_boot_sram --runtime 600s
```

步骤 5：分析结果。仿真产物位于
`build/vivado/project/simplecpu_soc.sim/sim_1/behav/xsim/`，Vivado 批处理日志位于 `build/vivado/logs/sim_kernel_boot_sram.log`。

```sh
# 串口控制台输出（OpenSBI/Linux 启动日志，判断进度的首要依据）
tail -20 build/vivado/project/simplecpu_soc.sim/sim_1/behav/xsim/uart_tx.log

# 异常追踪（每行：cycle pc priv target cause epc tval satp）
tail -20 build/vivado/project/simplecpu_soc.sim/sim_1/behav/xsim/kernel_trap.log

# 进度日志（每行：cycle retired pc priv satp traps）
tail -5 build/vivado/project/simplecpu_soc.sim/sim_1/behav/xsim/kernel_progress.log
```

关键观察点

uart_tx.log 中查找：
- OpenSBI banner → Linux 内核启动日志 → 挂载 rootfs、启动用户空间

kernel_trap.log 中查找：
- cause=12 → instruction page fault
- cause=13 → load page fault
- cause=15 → store page fault
- priv 列：3=M-mode，1=S-mode，0=U-mode
- satp 列非 0 表示分页已启用

kernel_progress.log（以及控制台每 100 万周期打印一次的 `[KERNEL]` 行）中查找：
- PC 从 0x8000xxxx（OpenSBI）→ 0x8040xxxx（Linux kernel）→ 启用分页后的内核虚拟地址
- retired 持续增长说明 CPU 在正常执行

其他：
- CPU 停滞超过 1000 万周期时 testbench 触发 `[KERNEL-WATCHDOG]`，打印 satp/mepc/mcause/sepc/scause/stval 后 `$fatal` 退出
- 仿真结束时打印 `[KERNEL] summary cycles=... retired=... traps=... pc=...`
- 仿真速度可由 kernel_progress.log 中 cycle 随时间的增长估算
