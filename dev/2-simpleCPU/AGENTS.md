# simpleCPU 接入 Bus4LZU 总线器件计划（busip分支）

目标：在当前基础CPU上适配busip

参考当前目录下PLAN.md

注意需要PROCESS.md记录进度

## 附：资源

### 模拟脚本

tools/mk.py是一个编译、执行脚本，使用其进行verilog模拟。

使用方法见tools/README-mk.md

### coe编译

需要coe文件（icache初始化文件，内部字符串描述指令流）或者tb需要指令的二进制码可以使用tools/rv2coe.py进行编译，支持riscv汇编和c语言（优先汇编，c语言部分功能未经过完全验证）。

使用方法见tools/README-rv2coe.md

### example

example/livep-2文件夹下是一个示例完整多周期CPU，供参考。