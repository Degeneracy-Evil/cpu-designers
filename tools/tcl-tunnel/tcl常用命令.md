# 一、创建工程

 1 # 创建工程
 2 create_project MyProject ./MyProject -part xc7a100tfgg484-2
 3 # 该命令创建一个名为 my_project 的新项目，指定 FPGA 芯片型号为 xc7a100tfgg484-2，并将项目存储在 ./my_project 路径下
 4
 5 # 打开现有项目
 6 open_project ./MyProject/MyProject.xpr
 7
 8 # 保存当前项目
 9 save_project_as -force MyProject_Backup
10
11 # 关闭当前项目
12 close_project

# 二、添加文件

 1 # 添加 单个Verilog 源文件
 2 add_files -fileset sources_1 [list ./src/module.sv]
 3
 4 # 递归地将 ./src 目录下的所有文件添加到项目中
 5 add_files -fileset sources_1 -recursive ./src
 6
 7 # 设置顶层文件
 8 set_property top top_module [current_fileset]
 9
10 # 设置文件类型
11 set_property file_type {SystemVerilog} [get_files ./src/module.sv]
12
13 # 添加约束文件
14 add_files -fileset constrs_1 ./constraints/top.xdc
15
16 # 添加 IP 核的 XCI/XCO 文件
17 add_files [list ./ip/clk_wiz_0.xci]

# 三、综合设计

 1 # 综合设计
 2 synth_design -top top_module -part xc7a100tfgg484-2
 3 launch_runs synth_1 -jobs 4 -quiet
 4 wait_on_run synth_1
 5
 6 report_utilization -hierarchy -file D:/WorkSpace/utilireport.txt
 7
 8 # 查看综合结果
 9 open_run synth_1
10 report_utilization -hierarchy -file utilization_report.rpt

# 四、布局布线

 1 # 优化设计
 2 opt_design
 3
 4 # 布局 布线
 5 place_design
 6 route_design
 7
 8 # 生成比特流文件
 9 write_bitstream -file top_module.bit
10
11 # 导出硬件描述文件（用于SDK/Vitis）
12 write_hw_platform -fixed -force -file top.xsa

# 五、综合示例

1、如下提供常见的自动化脚本，将其保存到MyTcl.tcl；

## 1. 初始化环境变量

set outputDir "D:/WorkSpace/FPGA/Temp/output"
set projectName "my_project"
set devicePart "xc7a100tfgg484-2"
file mkdir $outputDir

## 2. 创建新工程

create_project $projectName $outputDir/$projectName -part $devicePart -force
set_property target_language SystemVerilog [current_project]

## 3. 添加设计文件

add_files [glob ./src/*.sv]
set_property top led [current_fileset]
update_compile_order -fileset sources_1

## 4. 添加约束文件

add_files -fileset constrs_1 [glob ./constraints/*.xdc]
set_property target_constrs_file [get_files*.xdc] [current_fileset -constrset]

## 5. 综合配置与执行

set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
launch_runs synth_1 -jobs 8
wait_on_run synth_1

## 6. 实现（布局布线）配置

set_property strategy Performance_Explore [get_runs impl_1]
launch_runs impl_1 -jobs 8
wait_on_run impl_1

## 7. 生成Bit文件

open_run impl_1
write_bitstream -force "$outputDir/${projectName}.bit"

## 8. 生成资源利用率报告

report_utilization -hierarchical -file "$outputDir/utilization.rpt"

## 9. 生成时序报告

report_timing_summary -delay_type max -max_paths 10 -input_pins -file "$outputDir/timing_summary.rpt"
report_timing -from [get_clocks] -to [get_clocks] -file "$outputDir/timing_details.rpt"

## 退出Vivado

exit
