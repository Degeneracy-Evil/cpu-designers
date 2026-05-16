# =============================================================================
# vivado_do.tcl — Vivado 仿真自动化脚本 (SystemVerilog)
#
# 用法:
#   vivado.bat -mode tcl
#   source vivado_do.tcl -notrace -encoding utf-8
#   vivado_do ?-create? ?-sim <tb>? ?-runtime <t>? ?-clear? ?-bitstream? ?-hw_connect? ?-program?
#
# 参数:
#   -create                 创建/打开工程（已存在则打开，不存在则创建并配置 RTL/IP/约束）
#   -sim <testbench_name>   指定 testbench 并运行仿真
#   -runtime <time>         仿真运行时间 (默认按 tb_runtime_map 映射)
#   -clear                  删除已有工程目录（需配合 -create 重建）
#   -bitstream              运行综合、实现并生成 Bitstream (输出 system_top.bit)
#   -hw_connect             连接硬件 (hw_server)
#   -program                下载 bitstream 到 FPGA
#
# 典型用法:
#   # 首次: 创建工程并仿真
#   vivado_do -create -sim tb_simple_cpu_top
#   # 切换 tb: 在当前工程上直接仿真
#   vivado_do -sim tb_ahb_bus
#   # 完全重建: 清除后重新创建
#   vivado_do -clear -create -sim tb_simple_cpu_top
#   # 仅生成 bitstream
#   vivado_do -bitstream
#
# 可选 testbench:
#   tb_simple_cpu_top     — CPU 全功能测试 (34 PASS, 需要 cpu_test.hex)
#   tb_simple_cpu_compute — CPU 计算/访存测试 (42 PASS, 需要 cpu_test_compute.hex)
#   tb_simple_cpu_trap    — CPU 异常/陷阱测试 (10 PASS, 需要 cpu_test_trap.hex)
#   tb_uart_hello         — UART 发送测试 (12 PASS, 需要 uart_hello.hex)
#   tb_led_marquee        — LED 走马灯测试 (16 PASS, 需要 led_marquee.hex)
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
#     例如: "<repo_root>/dev/program_source/cpu_test.hex"
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
set cpu_core_dir    "${dev_dir}/rtl/core"
set ahb_dir         "${dev_dir}/rtl/AHB-lite"
set ahb_ip_dir      "${dev_dir}/rtl/AHB-lite/ip"
set apb_dir         "${dev_dir}/rtl/APB"
set apb_header_dir  "${dev_dir}/rtl/APB/header"
set apb_perips_dir  "${dev_dir}/rtl/APB/perips"
set sys_rtl_dir     "${dev_dir}/rtl"

set tb_dir          "${dev_dir}/tb"
set prog_dir        "${dev_dir}/program_source"
set fpga_dir        "${dev_dir}/fpga"
set ips_dir         "${base_dir}/Reference/ips"

set tcl_dir         "${base_dir}/tools/tcl"

array set tb_coe_map {
    tb_simple_cpu_top     "cpu_test.coe"
    tb_simple_cpu_compute "cpu_test_compute.coe"
    tb_simple_cpu_trap    "cpu_test_trap.coe"
    tb_uart_hello         "uart_hello.coe"
    tb_led_marquee        "led_marquee.coe"
    tb_ahb_bus            ""
    tb_apb_perips         ""
    tb_alu_cpu_integration ""
    tb_mu_unit            ""
    tb_non_restoring_divider ""
}

array set tb_runtime_map {
    tb_simple_cpu_top     "5ms"
    tb_simple_cpu_compute "5ms"
    tb_simple_cpu_trap    "3ms"
    tb_uart_hello         "5ms"
    tb_led_marquee        "2s"
    tb_ahb_bus            "5000ns"
    tb_apb_perips         "2000ns"
    tb_alu_cpu_integration "5000ns"
    tb_mu_unit            "5000ns"
    tb_non_restoring_divider "5000ns"
}

# ---------------------------------------------------------------------------
# 辅助 proc: 确保工程已打开
# ---------------------------------------------------------------------------
proc ensure_project_open {} {
    global proj_dir proj_name
    if { [catch {current_project}] == 0 } {
        return 1
    }
    set xpr_path "${proj_dir}/${proj_name}.xpr"
    if { [file exists $xpr_path] } {
        puts "打开已有工程: $xpr_path"
        open_project $xpr_path
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
    set opt_bitstream 0
    set opt_hwconnect 0
    set opt_program   0

    set i 0
    while { $i < [llength $args] } {
        set arg [lindex $args $i]
        switch -exact -- $arg {
            -create     { set opt_create 1 }
            -sim        { incr i; set opt_sim [lindex $args $i] }
            -runtime    { incr i; set opt_runtime [lindex $args $i] }
            -clear      { set opt_clear 1 }
            -bitstream  { set opt_bitstream 1 }
            -hw_connect { set opt_hwconnect 1 }
            -program    { set opt_program 1 }
            default     { puts "WARNING: 未知参数: $arg" }
        }
        incr i
    }

    puts "参数: -create $opt_create -sim $opt_sim -runtime $opt_runtime -clear $opt_clear -bitstream $opt_bitstream -hw_connect $opt_hwconnect -program $opt_program"

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
    if { $opt_clear && [file exists $proj_dir] } {
        puts "删除已有工程目录: $proj_dir"
        file delete -force $proj_dir
    }

    # --- -create: 创建/打开工程 ---
    if { $opt_create } {
        if { [catch {current_project} cur_proj] == 0 } {
            puts "工程已打开: $cur_proj"
        } elseif { [file exists "${proj_dir}/${proj_name}.xpr"] } {
            puts "打开已有工程: ${proj_dir}/${proj_name}.xpr"
            open_project "${proj_dir}/${proj_name}.xpr"
        } else {
            puts "创建新工程..."
            source -notrace -encoding utf-8 "${tcl_dir}/create_proj.tcl"
            source -notrace -encoding utf-8 "${tcl_dir}/setup_ip.tcl"
            source -notrace -encoding utf-8 "${tcl_dir}/add_constrs.tcl"
        }
    }

    # --- -sim: 添加 testbench 并运行仿真 ---
    if { $opt_sim ne "" } {
        if { ![ensure_project_open] } { return }
        source -notrace -encoding utf-8 "${tcl_dir}/add_tb.tcl"
        source -notrace -encoding utf-8 "${tcl_dir}/run_sim.tcl"
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
        open_hw_manager
        connect_hw_server -allow_non_jtag
        current_hw_target [get_hw_targets *]
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
            set_property PROGRAM.FILE $bit_file [current_hw_device]
            program_hw_devices [current_hw_device]
            refresh_hw_device [current_hw_device]
            puts "--> 下载成功"
        } else {
            puts "--> [ERROR] 找不到 bitstream 文件: $bit_file"
        }
    }

    puts "========================================"
    puts "vivado_do 执行完成"
    if { $opt_sim ne "" } { puts "Testbench: $tb_name" }
    puts "========================================"
}

puts "vivado_do.tcl 已加载。用法: vivado_do ?-create? ?-sim <tb>? ?-runtime <t>? ?-clear? ?-bitstream? ?-hw_connect? ?-program?"
puts "(建议使用 source vivado_do.tcl -notrace 来关闭命令回显功能)"
