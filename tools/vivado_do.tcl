# =============================================================================
# vivado_do.tcl — Vivado 仿真自动化脚本 (SystemVerilog)
#
# 用法:
#   vivado.bat -mode tcl
#   source vivado_do.tcl -notrace -encoding utf-8
#   vivado_do ?-create? ?-sim <tb>? ?-runtime <t>? ?-clear? ?-refresh? ?-bitstream? ?-hw_connect? ?-program? ?-archive?
#
# 参数:
#   -create                 创建/打开工程（已存在则打开，不存在则创建并配置 RTL/IP/约束）
#   -sim <testbench_name>   指定 testbench 并运行仿真
#   -runtime <time>         仿真运行时间 (默认按 tb_runtime_map 映射)
#   -clear                  删除已有工程目录（需配合 -create 重建）
#   -refresh                刷新工程：删除并重建，用于拷贝策略下同步源码变更
#   -bitstream              运行综合、实现并生成 Bitstream (输出 system_top.bit)
#   -hw_connect             连接硬件 (hw_server)
#   -program                下载 bitstream 到 FPGA
#   -archive                导出当前工程为 ZIP 归档（自动按时间戳命名）
#
# 工程策略:
#   - 拷贝策略 (source_mgmt_mode=Copy): 源码完全拷贝到工程目录，与原始源码隔离
#   - IP 仅存储 XCI 文件于 docs/Reference/ips/ 下 (扁平目录，无子文件夹)
#   - 源码变更后使用 -refresh 刷新工程以同步最新源码
#
# 典型用法:
#   # 首次: 创建工程并仿真
#   vivado_do -create -sim tb_simple_cpu_top
#   # 切换 tb: 在当前工程上直接仿真
#   vivado_do -sim tb_ahb_bus
#   # 完全重建: 清除后重新创建
#   vivado_do -clear -create -sim tb_simple_cpu_top
#   # 源码变更后刷新工程
#   vivado_do -refresh
#   # 仅生成 bitstream
#   vivado_do -bitstream
#
# 可选 testbench:
#   tb_simple_cpu_top     — CPU 全功能测试 (42 PASS, 需要 test/cpu_test.hex)
#   tb_simple_cpu_compute — CPU 计算/访存测试 (42 PASS, 需要 test/cpu_test_compute.hex)
#   tb_simple_cpu_trap    — CPU 异常/陷阱测试 (14 PASS, 需要 test/cpu_test_trap.hex)
#   tb_cpu_test_fencei    — fence.i JIT 测试 (需要 test/cpu_test_fencei.hex)
#   tb_cpu_test_access_fault — 访问错误异常测试 (需要 test/cpu_test_access_fault.hex)
#   tb_uart_hello         — UART 发送测试 (12 PASS, 需要 app/uart_hello.hex)
#   tb_led_marquee        — LED 走马灯测试 (16 PASS, 需要 app/led_marquee.hex)
#   tb_ahb_bus            — AHB 总线测试 (3 PASS, 无需 hex)
#   tb_apb_perips         — APB 外设测试 (10 PASS, 无需 hex)
#   tb_alu_cpu_integration — ALU 集成测试
#   tb_mu_unit            — 乘除法器测试
#   tb_non_restoring_divider — 除法器测试
#
# 注意:
#   - testbench 中的 $readmemh 使用相对路径，iverilog 可直接解析
#   - xsim 工作目录为 ${proj_dir}/${proj_name}.sim/sim_1/behav/xsim/
#     相对路径无法解析，需将 $readmemh 路径改为绝对路径
#     例如: "<repo_root>/src/program_source/test/cpu_test.hex"
# =============================================================================

# ---------------------------------------------------------------------------
# 路径与配置 (脚本加载时初始化)
# ---------------------------------------------------------------------------
if { ![info exists base_dir] } {
    set base_dir    [file dirname [file normalize [info script]]]
}

set proj_name       "simplecpu_bus"
set device_part     "xc7a200tfbg676-2"

set proj_dir        "${base_dir}/project/${proj_name}"
set dev_dir         "${base_dir}/dev"

set alu_rtl_dir     "${dev_dir}/rtl/ALU"
set mu_rtl_dir      "${dev_dir}/rtl/MU"
set fpu_rtl_dir     "${dev_dir}/rtl/FPU"
set cpu_core_dir    "${dev_dir}/rtl/core"
set common_dir      "${dev_dir}/rtl/common"
set ahb_dir         "${dev_dir}/rtl/axi"
set ahb_ip_dir      "${dev_dir}/rtl/axi/ip"
set amba_dir        "${dev_dir}/rtl/AMBA"
set ram_wrap_dir    "${dev_dir}/rtl/ram_wrap"
set apb_dir         "${dev_dir}/rtl/APB"
set apb_header_dir  "${dev_dir}/rtl/APB/header"
set apb_perips_dir  "${dev_dir}/rtl/APB/perips"
set sys_rtl_dir     "${dev_dir}/rtl"

set tb_dir          "${dev_dir}/tb"
set prog_dir        "${dev_dir}/program_source"
# 子目录: test/ = CPU 验证测试程序, app/ = FPGA 演示应用程序
set fpga_dir        "${dev_dir}/fpga"
set ips_dir         "${base_dir}/docs/Reference/newips"

set tcl_dir         "${base_dir}/tools/vivado_core/tcl"

array set tb_coe_map {
    tb_simple_cpu_top     "test/cpu_test.coe"
    tb_simple_cpu_compute "test/cpu_test_compute.coe"
    tb_simple_cpu_trap    "test/cpu_test_trap.coe"
    tb_cpu_test_fencei    "test/cpu_test_fencei.coe"
    tb_cpu_test_access_fault "test/cpu_test_access_fault.coe"
    tb_simple_cpu_priv    "test/cpu_test_priv.coe"
    tb_uart_hello         "app/uart_hello.coe"
    tb_led_marquee        "app/led_marquee.coe"
    tb_ahb_bus            ""
    tb_apb_perips         ""
    tb_alu_cpu_integration ""
    tb_mu_unit            ""
    tb_non_restoring_divider ""
    tb_isa_alu            "test/isa/alu.coe"
    tb_isa_branch         "test/isa/branch.coe"
    tb_isa_memory         "test/isa/memory.coe"
    tb_isa_upper_imm      "test/isa/upper_imm.coe"
    tb_isa_jump           "test/isa/jump.coe"
    tb_isa_csr            "test/isa/csr.coe"
    tb_isa_m_ext          "test/isa/m_ext.coe"
    tb_exception_ecall         "test/exception/ecall.coe"
    tb_exception_ebreak        "test/exception/ebreak.coe"
    tb_exception_illegal_inst  "test/exception/illegal_inst.coe"
    tb_exception_access_fault  "test/exception/access_fault.coe"
    tb_exception_timer_irq     "test/exception/timer_irq.coe"
    tb_exception_interrupt_basic "test/exception/interrupt_basic.coe"
    tb_mmu_sv32_basic    "test/mmu/sv32_basic.coe"
    tb_mmu_tlb_basic     "test/mmu/tlb_basic.coe"
    tb_mmu_tlb_replace   "test/mmu/tlb_replace.coe"
    tb_mmu_tlb_flush     "test/mmu/tlb_flush.coe"
    tb_mmu_tlb_asid      "test/mmu/tlb_asid.coe"
    tb_mmu_tlb_megapage  "test/mmu/tlb_megapage.coe"
    tb_mmu_tlb_stress    "test/mmu/tlb_stress.coe"
    tb_mmu_ptw_walk      "test/mmu/ptw_walk.coe"
    tb_mmu_page_fault    "test/mmu/page_fault.coe"
    tb_mmu_permission    "test/mmu/permission.coe"
    tb_mmu_sv32_edge     "test/mmu/sv32_edge.coe"
    tb_cache_icache_basic "test/cache/icache_basic.coe"
    tb_cache_dcache_basic "test/cache/dcache_basic.coe"
    tb_cache_dcache_dirty "test/cache/dcache_dirty.coe"
    tb_cache_fencei       "test/cache/fencei.coe"
    tb_cache_cache_mmu_interact "test/cache/cache_mmu_interact.coe"
    tb_mmio_clint         "test/mmio/clint.coe"
    tb_mmio_plic          "test/mmio/plic.coe"
}

array set tb_runtime_map {
    tb_simple_cpu_top     "5ms"
    tb_simple_cpu_compute "5ms"
    tb_simple_cpu_trap    "3ms"
    tb_cpu_test_fencei    "5ms"
    tb_cpu_test_access_fault "3ms"
    tb_simple_cpu_priv    "20ms"
    tb_uart_hello         "40ms"
    tb_led_marquee        "2s"
    tb_ahb_bus            "5000ns"
    tb_apb_perips         "2000ns"
    tb_alu_cpu_integration "5000ns"
    tb_mu_unit            "5000ns"
    tb_non_restoring_divider "5000ns"
    tb_isa_alu            "5ms"
    tb_isa_branch         "5ms"
    tb_isa_memory         "5ms"
    tb_isa_upper_imm      "5ms"
    tb_isa_jump           "5ms"
    tb_isa_csr            "5ms"
    tb_isa_m_ext          "5ms"
    tb_exception_ecall         "5ms"
    tb_exception_ebreak        "5ms"
    tb_exception_illegal_inst  "5ms"
    tb_exception_access_fault  "5ms"
    tb_exception_timer_irq     "10ms"
    tb_exception_interrupt_basic "5ms"
    tb_mmu_sv32_basic    "20ms"
    tb_mmu_tlb_basic     "20ms"
    tb_mmu_tlb_replace   "20ms"
    tb_mmu_tlb_flush     "20ms"
    tb_mmu_tlb_asid      "20ms"
    tb_mmu_tlb_megapage  "20ms"
    tb_mmu_tlb_stress    "30ms"
    tb_mmu_ptw_walk      "20ms"
    tb_mmu_page_fault    "20ms"
    tb_mmu_permission    "20ms"
    tb_mmu_sv32_edge     "20ms"
    tb_cache_icache_basic "5ms"
    tb_cache_dcache_basic "5ms"
    tb_cache_dcache_dirty "5ms"
    tb_cache_fencei       "10ms"
    tb_cache_cache_mmu_interact "20ms"
    tb_mmio_clint         "10ms"
    tb_mmio_plic          "5ms"
}

# ---------------------------------------------------------------------------
# 辅助 proc: 确保没有工程打开，防止删文件冲突
# ---------------------------------------------------------------------------
proc ensure_project_closed {} {
    set cur_proj [current_project -quiet]
    if { $cur_proj ne "" } {
        puts "关闭当前打开的工程: $cur_proj"
        catch { close_project }
    }
}

# ---------------------------------------------------------------------------
# 辅助 proc: 确保目标工程已打开
# ---------------------------------------------------------------------------
proc ensure_project_open {} {
    global proj_dir proj_name
    set cur_proj [current_project -quiet]
    if { $cur_proj ne "" } {
        if { $cur_proj == $proj_name } {
            return 1
        } else {
            puts "关闭当前打开的其他工程: $cur_proj"
            catch { close_project }
        }
    }
    set xpr_path "${proj_dir}/${proj_name}.xpr"
    if { [file exists $xpr_path] } {
        puts "打开已有工程: $xpr_path"
        if { [catch {open_project $xpr_path} err] } {
            puts "ERROR: 打开工程失败: $err"
            return 0
        }
        return 1
    }
    puts "ERROR: 工程不存在，请先使用 -create 创建工程"
    return 0
}

# ---------------------------------------------------------------------------
# 主 proc: vivado_do
# ---------------------------------------------------------------------------
proc vivado_do {args} {
    global base_dir proj_name device_part proj_dir dev_dir
    global alu_rtl_dir mu_rtl_dir cpu_core_dir ahb_dir ahb_ip_dir
    global apb_dir apb_header_dir apb_perips_dir sys_rtl_dir
    global tb_dir prog_dir fpga_dir ips_dir tcl_dir
    global tb_coe_map tb_runtime_map

    set opt_create    0
    set opt_sim       ""
    set opt_runtime   ""
    set opt_clear     0
    set opt_refresh   0
    set opt_bitstream 0
    set opt_hwconnect 0
    set opt_program   0
    set opt_archive   0

    set i 0
    while { $i < [llength $args] } {
        set arg [lindex $args $i]
        switch -exact -- $arg {
            -create     { set opt_create 1 }
            -sim        { incr i; set opt_sim [lindex $args $i] }
            -runtime    { incr i; set opt_runtime [lindex $args $i] }
            -clear      { set opt_clear 1 }
            -refresh    { set opt_refresh 1 }
            -bitstream  { set opt_bitstream 1 }
            -hw_connect { set opt_hwconnect 1 }
            -program    { set opt_program 1 }
            -archive    { set opt_archive 1 }
            default     { puts "WARNING: 未知参数: $arg" }
        }
        incr i
    }

    puts "参数: -create $opt_create -sim $opt_sim -runtime $opt_runtime -clear $opt_clear -refresh $opt_refresh -bitstream $opt_bitstream -hw_connect $opt_hwconnect -program $opt_program -archive $opt_archive"

    set tb_name $opt_sim

    set icache_coe_file ""
    set dcache_coe_file ""
    if { $tb_name ne "" && [info exists tb_coe_map($tb_name)] } {
        set coe_name $tb_coe_map($tb_name)
        if { $coe_name ne "" } {
            set icache_coe_file "${prog_dir}/${coe_name}"
            set dcache_coe_file "${prog_dir}/${coe_name}"
        }
    }

    if { $opt_runtime ne "" } {
        set sim_run_time $opt_runtime
    } elseif { $tb_name ne "" && [info exists tb_runtime_map($tb_name)] } {
        set sim_run_time $tb_runtime_map($tb_name)
    } else {
        set sim_run_time "100000ns"
    }

    set ip_output_dir "${proj_dir}/${proj_name}.srcs/sources_1/ip"

    # --- -clear: 删除工程目录 ---
    if { $opt_clear } {
        if { [file exists $proj_dir] } {
            ensure_project_closed
            puts "删除已有工程目录: $proj_dir"
            if { [catch {file delete -force $proj_dir} err] } {
                puts "WARNING: 删除目录失败: $err"
            } else {
                puts "--> 成功删除工程目录"
            }
        } else {
            puts "工程目录不存在，无需删除: $proj_dir"
        }
    }

    # --- -create: 创建/打开工程 ---
    if { $opt_create } {
        set cur_proj [current_project -quiet]
        if { $cur_proj ne "" && $cur_proj != $proj_name } {
            puts "关闭当前打开的其他工程: $cur_proj"
            catch { close_project }
            set cur_proj ""
        }
        
        if { $cur_proj == $proj_name } {
            puts "工程已打开: $cur_proj"
        } elseif { [file exists "${proj_dir}/${proj_name}.xpr"] } {
            puts "打开已有工程: ${proj_dir}/${proj_name}.xpr"
            open_project "${proj_dir}/${proj_name}.xpr"
        } else {
            puts "创建新工程..."
            source -notrace -encoding utf-8 "${tcl_dir}/_create.tcl"
            source -notrace -encoding utf-8 "${tcl_dir}/_setup_ip.tcl"
            source -notrace -encoding utf-8 "${tcl_dir}/_add_constrs.tcl"
        }
    }

    # --- -refresh: 刷新工程 (删除并重建，同步源码变更) ---
    if { $opt_refresh } {
        puts "========================================"
        puts "刷新工程 (拷贝策略下同步源码)..."
        puts "========================================"
        ensure_project_closed
        if { [file exists $proj_dir] } {
            puts "删除工程目录: $proj_dir"
            if { [catch {file delete -force $proj_dir} err] } {
                puts "ERROR: 删除工程目录失败: $err (可能文件被占用)"
                return
            }
        }
        puts "重建工程..."
        source -notrace -encoding utf-8 "${tcl_dir}/_create.tcl"
        source -notrace -encoding utf-8 "${tcl_dir}/_setup_ip.tcl"
        source -notrace -encoding utf-8 "${tcl_dir}/_add_constrs.tcl"
        puts "--> 工程刷新完成"
    }

    # --- -sim: 添加 testbench 并运行仿真 ---
    if { $opt_sim ne "" } {
        if { ![ensure_project_open] } { return }
        source -notrace -encoding utf-8 "${tcl_dir}/_add_tb.tcl"
        source -notrace -encoding utf-8 "${tcl_dir}/_run_sim.tcl"
    }

    # --- -bitstream: 生成 bitstream ---
    if { $opt_bitstream } {
        if { ![ensure_project_open] } { return }
        puts "========================================"
        puts "开始生成 bitstream..."
        puts "========================================"
        set_property top system_top [current_fileset]
        update_compile_order -fileset sources_1

        reset_run synth_1
        launch_runs synth_1 -jobs 14
        wait_on_run synth_1

        launch_runs impl_1 -jobs 14
        wait_on_run impl_1

        launch_runs impl_1 -to_step write_bitstream -jobs 14
        wait_on_run impl_1

        set bit_file "${proj_dir}/${proj_name}.runs/impl_1/system_top.bit"
        if { [file exists $bit_file] } {
            file copy -force $bit_file "${base_dir}/system_top.bit"
            puts "--> 成功生成 bitstream: ${base_dir}/system_top.bit"
        } else {
            puts "--> [ERROR] Bitstream 生成失败"
        }
    }

    # --- -hw_connect: 连接硬件 ---
    if { $opt_hwconnect } {
        puts "========================================"
        puts "开始连接硬件 (hw_server)..."
        puts "========================================"
        catch { open_hw }
        connect_hw_server
        open_hw_target
        current_hw_device [lindex [get_hw_devices] 0]
        refresh_hw_device -update_hw_probes false [lindex [get_hw_devices] 0]
        puts "--> 硬件连接成功"
    }

    # --- -program: 下载 bitstream ---
    if { $opt_program } {
        puts "========================================"
        puts "开始下载 bitstream 到 FPGA..."
        puts "========================================"
        set bit_file "${base_dir}/system_top.bit"
        if { [file exists $bit_file] } {
            catch { open_hw }
            catch { connect_hw_server }
            catch { open_hw_target }
            set hw_device [lindex [get_hw_devices] 0]
            current_hw_device $hw_device
            refresh_hw_device -update_hw_probes false $hw_device
            
            set_property PROBES.FILE {} $hw_device
            set_property FULL_PROBES.FILE {} $hw_device
            set_property PROGRAM.FILE $bit_file $hw_device
            
            program_hw_devices $hw_device
            refresh_hw_device $hw_device
            close_hw
            puts "--> 下载成功"
        } else {
            puts "--> [ERROR] 找不到 bitstream 文件: $bit_file"
        }
    }

    # --- -archive: 导出工程压缩包 ---
    if { $opt_archive } {
        if { ![ensure_project_open] } { return }
        puts "========================================"
        puts "开始导出项目 Archive..."
        puts "========================================"
        set time_str [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
        set target_archive_dir "${base_dir}/archive"
        set archive_path "${target_archive_dir}/${proj_name}_${time_str}.xpr.zip"
        
        if { ![file exists $target_archive_dir] } {
            file mkdir $target_archive_dir
        }
        
        if { [catch {archive_project $archive_path -force -include_local_ip_cache -include_config_settings} err] } {
            if { [catch {archive_project $archive_path -force} err2] } {
                puts "--> [ERROR] 导出项目 Archive 失败: $err2"
            } else {
                puts "--> 成功导出项目 Archive (基础模式): $archive_path"
            }
        } else {
            puts "--> 成功导出项目 Archive: $archive_path"
        }
    }

    puts "========================================"
    puts "vivado_do 执行完成"
    if { $opt_sim ne "" } { puts "Testbench: $tb_name" }
    puts "========================================"
}

puts "vivado_do.tcl 已加载。用法: vivado_do ?-create? ?-sim <tb>? ?-runtime <t>? ?-clear? ?-refresh? ?-bitstream? ?-hw_connect? ?-program? ?-archive?"
puts "(建议使用 source vivado_do.tcl -notrace 来关闭命令回显功能)"
