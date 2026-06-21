# 完整操作方法
步骤 1：生成 hex 文件（已完成）
# bin → hex 转换（已生成，如需重新转换）
python3 tools/bin2hex.py /tmp/fws/firmware/fw_payload.bin dev/program_source/firmware/fw_payload.hex
# 产出: 2352542 words (9.0 MB)
hex 文件已在 dev/program_source/firmware/fw_payload.hex。
步骤 2：运行仿真
# 快速模式（仅 trap 追踪，~10K cycles/s）
python3 -m tools.vivado_cli -task linux_boot -create -sim --debug trap

# 完整模式（trap + 指令追踪 + 波形，更慢）
python3 -m tools.vivado_cli -task linux_boot -create -sim --debug trace,trap,wave

# 复用已有 session（不重建项目，仅重新仿真）
python3 -m tools.vivado_cli -task linux_boot -sim --debug trap
步骤 3：分析结果
# 仿真产物位置
# project/linux_boot/simplecpu_soc.sim/sim_1/behav/xsim/

# trap 追踪（关键 — 查找 cause=13 load page fault）
tail -20 project/linux_boot/simplecpu_soc.sim/sim_1/behav/xsim/trap_trace.log

# 指令追踪（完整模式才有）
tail -20 project/linux_boot/simplecpu_soc.sim/sim_1/behav/xsim/instr_trace.log

# Vivado 日志（FIFO-MON 显示周期和 PC）
grep "FIFO-MON" project/linux_boot/vivado.log | tail -10
关键观察点
trap_trace.log 中查找：
- cause=12 → instruction page fault（旧 bug，应已修复）
- cause=13 → load page fault（目标故障）
- cause=15 → store page fault
- PC 从 804xxxxx（Linux kernel）进入 C037xxxx（Sv32 虚拟空间）
FIFO-MON 中查找：
- PC 从 800xxxxx（OpenSBI）→ 804xxxxx（Linux kernel）→ C037xxxx（启用 Sv32 后）
- 预计需要 50-200M 周期到达故障点
LCD Page 4 新增 d-side 信号（上板诊断用，sw7:6=11）：
信号	含义
MD_ST	d-side FSM 状态
MD_HT	d-side TLB hit
MD_VL	d-side TLB valid
MD_PM	d-side perm fault
MD_PW	d_pf_from_ptw: 0=TLB perm fault, 1=PTW walk fault
MD_MS	d-side TLB miss
仿真速度参考
- --debug trap：~10K cycles/s，到达 Linux kernel 约 30-60 分钟
- --debug trace,trap,wave：~5K cycles/s，更慢但信息完整
- 仿真只到达 OpenSBI 80020xxx（6M 周期 / 10 分钟），需继续运行到 80400000+