# Cache-主存体系建立计划

## 目标

建立cache与主存之间的映射和交换机制。

## 背景

当前项目报告见`dev\docs\simpleCPU-design-report.md`。

简述：rv32-im，cache采用哈佛存储结构，主存暂未使用，AHB系统总线，APB外设总线，仅M特权级。

## 设计

主存和缓存均使用BRAM IP（在`Reference\ips`文件夹下），参数如下：

.

计划采用写回设计，LRU替换算法，使用4路组相连。

icache进行只读特殊优化：脏位恒为零，替换时不进行回写到主存

*意向： 考虑进行算法层面的优化？icache使用FIFO？
