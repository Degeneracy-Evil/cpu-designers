# 常用命令速查

> 更新：2026-09-25 · 主工具：`python3 -m tools.vivado`

## 1. 仿真（最常用）

```bash
python3 -m tools.vivado list                # 列出所有任务和组
python3 -m tools.vivado sim cpu_full        # 跑一个仿真
python3 -m tools.vivado sim isa_alu
python3 -m tools.vivado sim kernel_boot_sram --runtime 3600   # 限时运行
python3 -m tools.vivado project             # 重建 Vivado 工程
python3 -m tools.vivado clean               # 删除生成的工程
```

仿真日志在 `build/logs/`。

## 2. 回归

```bash
python3 -m tools.vivado regress short       # 顺序跑一组（现有组：short）
```

## 3. 测试程序构建（test_builder）

```bash
python3 tools/test_builder.py               # 构建全部（读 config/programs.yaml）
python3 tools/test_builder.py --test isa/alu
python3 tools/test_builder.py --category mmu
python3 tools/test_builder.py --app led_marquee
python3 tools/test_builder.py --list        # 列出所有测试
python3 tools/test_builder.py --dry-run
python3 tools/test_builder.py --clean
python3 tools/test_builder.py -v
```

## 4. FPGA 上板

```bash
python3 -m tools.vivado bitstream --task fpga                # 生成 bitstream
python3 -m tools.vivado bitstream --task fpga --output my.bit
python3 -m tools.vivado program                              # 烧写 FPGA
python3 -m tools.vivado program --bitstream my.bit
```

### 上板流程（看 bootloader LED）

1. `python3 -m tools.vivado program` 烧板
2. 等 LED0 常亮（DDR 自检通过，等待上传）
   - LED 全亮 = DDR 自检失败
   - 0x5555 交替闪 = 魔数错误
3. 上传固件，约 7-8 分钟：

```bash
python3 -m tools.uart_console -p /dev/ttyUSB0 \
  -f build/opensbi/platform/generic/firmware/fw_payload.bin
```

4. 上传完自动进入控制台

## 5. 分析与辅助工具

```bash
# trace 日志分析
python3 -m tools.trace_analyzer parse <log>
python3 -m tools.trace_analyzer find-fail <log>        # 定位 PC 跳变
python3 -m tools.trace_analyzer diff <log> <spike.log> # 与 Spike 对比
python3 -m tools.trace_analyzer stats <log>

# 编译单个程序（默认 march rv32im_zicsr_zifencei）
python3 tools/rv2coe.py -i in.c -o out.coe

# bin 转 hex
python3 tools/bin2hex.py <in.bin> <out.hex>

# UART 控制台（默认波特率 230400，上传 + 控制台）
python3 -m tools.uart_console -p /dev/ttyUSB0 -f <bin/hex>

# 内核 / musl 编译
python3 tools/compile_kernel.sh
python3 tools/compile_musl.sh
```

## 6. 任务速查

| 类别 | 任务名 |
|------|--------|
| 集成 | cpu_full, cpu_full_ddr3, cpu_compute, cpu_trap |
| ISA | isa_alu, isa_branch, isa_memory, isa_upper_imm, isa_jump, isa_csr, isa_m_ext, isa_a_ext |
| 异常 | exception_ecall, exception_ebreak, exception_illegal_inst, exception_access_fault, exception_timer_irq, exception_interrupt_basic |
| 特权 | privilege_priv_transition, privilege_delegation, privilege_csr_access_priv, privilege_wfi, privilege_counter_access |
| MMU | mmu_sv32_basic, mmu_tlb_basic, mmu_tlb_flush, mmu_tlb_asid, mmu_tlb_megapage, mmu_tlb_stress, mmu_tlb_replace, mmu_ptw_walk, mmu_page_fault, mmu_permission, mmu_sv32_edge, mmu_unified_mmu, mmu_sfence_handshake_unit |
| Cache | cache_icache_basic, cache_dcache_basic, cache_dcache_dirty, cache_fencei, cache_mmu_interact |
| MMIO | mmio_clint, mmio_plic |
| 回归 | reg_tlb_fill_way, reg_ptw_fault_latch, reg_sfence_during_walk, reg_stale_paddr, reg_bare_no_miss, reg_mmio_ready, reg_dcache_refill_error, reg_dcache_store_error, reg_pf_latch, reg_linux_ptr_reload, reg_linux_field_values, regression_m_irq_precision |
| 外设/应用 | uart_hello, uart_echo, led_marquee, axi_interconnect, apb_peripherals |
| 单元 | axi4lite_plic_unit, axi4lite_clint_unit, cpu_trap_router_unit, csr_privileged_unit, ptw_global_unit, cpu_controller_unit, cpu_mem_contract_unit, exception_contract_unit, stage_exception_unit, pmp_pma_unit, cpu_bus_bridge_unit, dcache_writethrough_unit, icache_blocking_unit |
| Kernel | kernel_boot_sram, kernel_boot_ddr3, kernel_tb_compile_smoke |
| FPGA | fpga |

完整列表用 `python3 -m tools.vivado list` 查看。

## 7. 文件位置

```
配置            config/vivado.yaml, config/simulations.yaml, config/programs.yaml
Vivado 工程     build/vivado/project/
bitstream       build/vivado/simplecpu_soc.bit
仿真/构建日志   build/logs/
程序产物        build/program/
测试台          test/bench/
测试源          test/program/
固件            build/opensbi/platform/generic/firmware/fw_payload.bin
                build/program/firmware/fw_payload.hex
```
