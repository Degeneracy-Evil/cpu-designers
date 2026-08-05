## 附录E：位操作扩展汇编代码示例

以下示例提供软件优化指导。

## E.1. strlen

orc.b指令允许高效检测XLEN大小数据块中的NUL字节：

- 在不包含任何NUL字节的块上执行orc.b的结果将是全1，且
- 在对orc.b的结果按位取反后，第一个NUL字节（如果有）之前的数据字节数可以通过ctz/clz检测（取决于数据的字节序）。

以下是strlen函数的完整示例，它使用这些技术，还演示了其在未对齐/部分数据上的使用：

```
#include <sys/asm.h>
```

```
    .text
    .globl strlen
    .type  strlen, @function
strlen:
    andi    a3, a0, (SZREG-1)   // 偏移量
    andi    a1, a0, -SZREG      // 对齐指针
.Lprologue:
    li      a4, SZREG
    sub     a4, a4, a3          // XLEN - 偏移量
    slli    a3, a3, 3           // 偏移量 * 8
    REG_L   a2, 0(a1)           // 块
    /*
     * 移位我们加载的部分/未对齐块以移除字符串开始之前的字节，
     * 在末尾添加NUL字节。
     */
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    srl     a2, a2 ,a3          // chunk >> (offset * 8)
#else
    sll     a2, a2, a3
#endif
    orc.b   a2, a2
    not     a2, a2
    /*
     * 字符串中的非NUL字节已扩展为0x00，
     * 而NUL字节已变为0xff。搜索第一个设置位
     * （对应于原始块中的NUL字节）。
     */
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    ctz     a2, a2
#else
    clz     a2, a2
```

```
#endif
    /*
     * 第一个块是特殊的：与此块中有效字节数比较。
     */
    srli    a0, a2, 3
    bgtu    a4, a0, .Ldone
    addi    a3, a1, SZREG
    li      a4, -1
    .align 2
    /*
     * 我们的关键循环是4条指令，处理4字节或8字节块的数据。
     */
.Lloop:
    REG_L   a2, SZREG(a1)
    addi    a1, a1, SZREG
    orc.b   a2, a2
    beq     a2, a4, .Lloop
.Lepilogue:
    not     a2, a2
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    ctz     a2, a2
#else
    clz     a2, a2
#endif
    sub     a1, a1, a3
    add     a0, a0, a1
    srli    a2, a2, 3
    add     a0, a0, a2
.Ldone:
    ret
```

## E.2. strcmp

```
#include <sys/asm.h>
  .text
  .globl strcmp
  .type  strcmp, @function
strcmp:
  or    a4, a0, a1
  li    t2, -1
  and   a4, a4, SZREG-1
  bnez  a4, .Lsimpleloop
  # 对齐字符串的主循环
```

```
.Lloop:
  REG_L a2, 0(a0)
  REG_L a3, 0(a1)
  orc.b t0, a2
  bne   t0, t2, .Lfoundnull
  addi  a0, a0, SZREG
  addi  a1, a1, SZREG
  beq   a2, a3, .Lloop
  # 字不匹配，且第一个字中没有空字节。
  # 以大端序获取字节并比较。
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
  rev8  a2, a2
  rev8  a3, a3
#endif
  # 以无分支序列合成 (a2 >= a3) ? 1 : -1。
  sltu a0, a2, a3
  neg  a0, a0
  ori  a0, a0, 1
  ret
.Lfoundnull:
  # 找到空字节。
  # 如果字不匹配，回退到简单循环。
  bne   a2, a3, .Lsimpleloop
  # 否则，字符串相等。
  li    a0, 0
  ret
  # 未对齐字符串的简单循环
.Lsimpleloop:
  lbu   a2, 0(a0)
  lbu   a3, 0(a1)
  addi  a0, a0, 1
  addi  a1, a1, 1
  bne   a2, a3, 1f
  bnez  a2, .Lsimpleloop
1:
  sub   a0, a2, a3
  ret
.size   strcmp, .-strcmp
```
