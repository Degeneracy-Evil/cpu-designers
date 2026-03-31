# Vivado项目创建脚本
# 使用方法: 在Vivado Tcl Console中运行 source create_project.tcl

# 项目设置
set project_name "alu_fpga"
set project_dir "./vivado"

# FPGA型号（根据实际板卡修改）
set fpga_part "xc7a100tfgg484-2"

# 创建项目
create_project $project_name $project_dir -part $fpga_part

# 设置项目属性
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

# 添加RTL文件
add_files {
    ../rtl/basic_gates.v
    ../rtl/mux.v
    ../rtl/cla_adder_4bit.v
    ../rtl/cla_adder_16bit.v
    ../rtl/cla_adder_32bit.v
    ../rtl/subtractor.v
    ../rtl/shifter.v
    ../rtl/logic_unit.v
    ../rtl/lui.v
    ../rtl/booth_multiplier.v
    ../rtl/non_restoring_divider.v
    ../rtl/alu_result_selector.v
    ../rtl/alu_32bit.v
    ./alu_display.v
}

# 添加IP核（需要先将lcd_module.dcp复制到当前目录）
if {[file exists "lcd_module.dcp"]} {
    add_files lcd_module.dcp
} else {
    puts "警告: lcd_module.dcp不存在，请从example/1alu复制"
}

# 添加约束文件
add_files -fileset constrs_1 ./alu.xdc

# 设置顶层模块
set_property top alu_display [current_fileset]

# 更新编译顺序
update_compile_order -fileset sources_1

puts "项目创建完成！"
puts "下一步："
puts "1. 确保lcd_module.dcp已添加"
puts "2. 运行综合: synth_design -top alu_display"
puts "3. 运行实现: place_design; route_design"
puts "4. 生成比特流: write_bitstream -force alu.bit"