# =============================================================================
# vivado_sim.tcl — Vivado 仿真自动化脚本 (SystemVerilog)
#
# 用法:
#   vivado.bat -mode tcl
#   source vivado_sim.tcl
#   vivado_sim ?-tb <name>? ?-step <step>? ?-runtime <t>? ?-clean? ?-reuse?
#
# 参数:
#   -tb <testbench_name>   指定 testbench (默认 tb_simple_cpu_top)
#   -step <step>           执行到哪一步: create|ip|constrs|tb|sim|all (默认 all)
#   -runtime <time>        仿真运行时间 (默认按 tb_runtime_map 映射)
#   -clean                 删除已有工程目录后重建
#   -reuse                 复用已打开的工程，仅切换 tb 并仿真 (等价 -step tb)
#
# 典型用法:
#   # 首次: 全流程
#   vivado_sim -tb tb_simple_cpu_top -step all
#   # 切换 tb: 复用已有工程，无需重建
#   vivado_sim -tb tb_ahb_bus -reuse
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
# 主 proc: vivado_sim
# ---------------------------------------------------------------------------
proc vivado_sim {args} {
    global base_dir proj_name device_part proj_dir dev_dir
    global alu_rtl_dir mu_rtl_dir cpu_core_dir ahb_dir ahb_ip_dir
    global apb_dir apb_header_dir apb_perips_dir sys_rtl_dir
    global tb_dir prog_dir fpga_dir ips_dir tcl_dir
    global tb_coe_map tb_runtime_map

    set opt_tb       "tb_simple_cpu_top"
    set opt_step     "all"
    set opt_runtime  ""
    set opt_clean    0
    set opt_reuse    0

    set i 0
    while { $i < [llength $args] } {
        set arg [lindex $args $i]
        switch -exact -- $arg {
            -tb       { incr i; set opt_tb      [lindex $args $i] }
            -step     { incr i; set opt_step    [lindex $args $i] }
            -runtime  { incr i; set opt_runtime [lindex $args $i] }
            -clean    { set opt_clean 1 }
            -reuse    { set opt_reuse 1 }
            default   { puts "WARNING: 未知参数: $arg" }
        }
        incr i
    }

    if { $opt_reuse } {
        set opt_step "tb"
    }

    puts "参数: -tb $opt_tb -step $opt_step -runtime $opt_runtime -clean $opt_clean -reuse $opt_reuse"

    set tb_name $opt_tb

    set icache_coe_file ""
    set dcache_coe_file ""
    if { [info exists tb_coe_map($tb_name)] } {
        set coe_name $tb_coe_map($tb_name)
        if { $coe_name ne "" } {
            set icache_coe_file "${prog_dir}/${coe_name}"
            set dcache_coe_file "${prog_dir}/${coe_name}"
        }
    }

    if { $opt_runtime ne "" } {
        set sim_run_time $opt_runtime
    } elseif { [info exists tb_runtime_map($tb_name)] } {
        set sim_run_time $tb_runtime_map($tb_name)
    } else {
        set sim_run_time "100000ns"
    }

    set ip_output_dir "${proj_dir}/${proj_name}.srcs/sources_1/ip"

    if { $opt_clean && [file exists $proj_dir] } {
        puts "删除已有工程目录: $proj_dir"
        file delete -force $proj_dir
    }

    set steps [list create ip constrs tb sim]

    if { $opt_step eq "all" } {
        set run_steps $steps
    } else {
        set run_steps [list]
        set found 0
        foreach s $steps {
            if { $s eq $opt_step } { set found 1 }
            if { $found } { lappend run_steps $s }
        }
        if { ![llength $run_steps] } {
            puts "ERROR: 未知 step '$opt_step', 可选: [join $steps {, }], all"
            return
        }
    }

    puts "将执行步骤: [join $run_steps { -> }]"

    foreach s $run_steps {
        switch -exact -- $s {
            create  { source "${tcl_dir}/create_proj.tcl" }
            ip      { source "${tcl_dir}/setup_ip.tcl" }
            constrs { source "${tcl_dir}/add_constrs.tcl" }
            tb      { source "${tcl_dir}/add_tb.tcl" }
            sim     { source "${tcl_dir}/run_sim.tcl" }
        }
    }

    puts "========================================"
    puts "vivado_sim 执行完成"
    puts "Testbench: $tb_name"
    puts "Steps: [join $run_steps {, }]"
    puts "========================================"
}

puts "vivado_sim.tcl 已加载。用法: vivado_sim ?-tb <name>? ?-step <step>? ?-runtime <t>? ?-clean? ?-reuse?"
