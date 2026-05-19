# Cache-主存体系建立计划

## 目标

建立cache与主存之间的映射和交换机制。

## 背景

当前项目报告见`dev\docs\simpleCPU-design-report.md`。

简述：rv32-im，cache采用哈佛存储结构，主存暂未使用，AHB系统总线，APB外设总线，仅M特权级。

## 设计

主存和缓存均使用BRAM IP（新IP文件在`Reference\newips`文件夹下，当前项目使用的旧IP在`Reference\ips`文件夹下），参数如下：

- SRAM:$32bit *8192=32KB$
  - 地址宽:15bit
  - 块大小:32字节
  - IP设置：没有开启字节读写，wea,web宽度只有1
- i/dcache-d:$256bit *4路 *8组=1KB$（cache数据段）
  - 行大小:32字节
  - 组数:8组
  - offset:5bit
  - 组号:3bit
  - IP设置：开启字节读写，wea,web宽度32
- i/dcache-t:$16bit *4路 *8组=64B$（cache标志段）
  - tag:$15-5-3=7bit$
  - 有效位:1bit
  - 脏位:1bit
  - PLRU状态位:3bit
  - resave:4bit
  - IP设置：没有开启字节读写，wea,web宽度只有1

计划采用写回设计，tree-PLRU替换算法，使用4路组相连。

icache进行只读特殊优化：脏位恒为零，替换时不进行回写到主存

## 验收

验收目标：将coe加载到主存，cpu完成执行且结果正确，预计不需要更改测试程序。

注意：cpu复位应该读取0x8000_0000（内存模型主存首地址），当前不是这样，需要改为这样。

## 参考资料

上一阶段完成后项目整体报告：dev\docs\simpleCPU-design-report.md
tree-PLRU替换算法描述：dev\docs\Mem\tree-PLRU.txt

## 工具

vivado_do.tcl：vivado tcl 脚本，使用其进行模拟
tools\rv2coe.py：rv汇编/C程序编译脚本，输出格式HEX/COE/...

## 开发约束

将更改和进度输出到dev\PROCESS-mcs.md中。
