## 第15章. "Zacas" 原子 Compare-and-Swap (CAS) 指令扩展, 版本 1.0.0

Compare-and-Swap (CAS) 提供了一种简单且通常更快的方式来执行线程同步操作，当作为硬件指令支持时。CAS 通常被无锁和无等待算法使用。此扩展定义了操作 32 位、64 位和 128 位（仅 RV64）数据值的 CAS 指令。Zacas 扩展依赖于 Zaamo 扩展。

## 15.1. 字/双字/四字 CAS (AMOCAS.W/D/Q) 指令

|15.1. 字/双字/四字 CAS (AMOCAS.W/D/Q) 指令|15.1. 字/双字/四字 CAS (AMOCAS.W/D/Q) 指令|15.1. 字/双字/四字 CAS (AMOCAS.W/D/Q) 指令|15.1. 字/双字/四字 CAS (AMOCAS.W/D/Q) 指令|15.1. 字/双字/四字 CAS (AMOCAS.W/D/Q) 指令|15.1. 字/双字/四字 CAS (AMOCAS.W/D/Q) 指令|15.1. 字/双字/四字 CAS (AMOCAS.W/D/Q) 指令|15.1. 字/双字/四字 CAS (AMOCAS.W/D/Q) 指令|
|---|---|---|---|---|---|---|---|
|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31||||||||
|00101|aq|rl|rs2|rs1|funct3|rd|opcode|
|AMO<br>dest<br>010<br>011<br>100<br>addr<br>src<br>AMOCAS.W<br>AMOCAS.D<br>AMOCAS.Q||||||||

对于 RV32，`AMOCAS.W` 原子地从 `rs1` 中的地址加载一个 32 位数据值，将加载的值与 `rd` 中保存的 32 位值进行比较，如果比较是逐位相等的，则将 `rs2` 中保存的 32 位值存储到 `rs1` 中的原始地址。从内存加载的值被放入寄存器 `rd`。`AMOCAS.W` 在 RV32 中执行的操作如下：

```
    temp = mem[X(rs1)]
    if ( temp == X(rd) )
        mem[X(rs1)] = X(rs2)
    X(rd) = temp
```

`AMOCAS.D` 与 `AMOCAS.W` 类似，但操作 64 位数据值。

对于 RV32，`AMOCAS.D` 原子地从 `rs1` 中的地址加载 64 位数据值，将加载的值与由 `rd` 和 `rd+1` 组成的寄存器对中保存的 64 位值进行比较，如果比较是逐位相等的，则将寄存器对 `rs2` 和 `rs2+1` 中保存的 64 位值存储到 `rs1` 中的原始地址。从内存加载的值被放入寄存器对 `rd` 和 `rd+1`。该指令要求寄存器对中的第一个寄存器为偶数编号；在 `rs2` 和 `rd` 中指定奇数编号寄存器的编码是保留的。当源寄存器对的第一个寄存器是 `x0` 时，该对的两半都读为零。当目标寄存器对的第一个寄存器是 `x0` 时，整个寄存器结果被丢弃，且两个目标寄存器都不被写入。`AMOCAS.D` 在 RV32 中执行的操作如下：

```
    temp0 = mem[X(rs1)+0]
    temp1 = mem[X(rs1)+4]
    comp0 = (rd == x0)  ? 0 : X(rd)
    comp1 = (rd == x0)  ? 0 : X(rd+1)
    swap0 = (rs2 == x0) ? 0 : X(rs2)
    swap1 = (rs2 == x0) ? 0 : X(rs2+1)
    if ( temp0 == comp0 ) && ( temp1 == comp1 )
        mem[X(rs1)+0] = swap0
        mem[X(rs1)+4] = swap1
    endif
    if ( rd != x0 )
        X(rd)   = temp0
        X(rd+1) = temp1
    endif
```

对于 RV64，`AMOCAS.W` 原子地从 `rs1` 中的地址加载一个 32 位数据值，将加载的值与 `rd` 中保存的值的低 32 位进行比较，如果比较是逐位相等的，则将 `rs2` 中保存的值的低 32 位存储到 `rs1` 中的原始地址。从内存加载的 32 位值被符号扩展并放入寄存器 `rd`。`AMOCAS.W` 在 RV64 中执行的操作如下：

```
    temp[31:0] = mem[X(rs1)]
    if ( temp[31:0] == X(rd)[31:0] )
        mem[X(rs1)] = X(rs2)[31:0]
    X(rd) = SignExtend(temp[31:0])
```

对于 RV64，`AMOCAS.D` 原子地从 `rs1` 中的地址加载 64 位数据值，将加载的值与 `rd` 中保存的 64 位值进行比较，如果比较是逐位相等的，则将 `rs2` 中保存的 64 位值存储到 `rs1` 中的原始地址。从内存加载的值被放入寄存器 `rd`。`AMOCAS.D` 在 RV64 中执行的操作如下：

```
    temp = mem[X(rs1)]
    if ( temp == X(rd) )
        mem[X(rs1)] = X(rs2)
    X(rd) = temp
```

`AMOCAS.Q`（仅 RV64）原子地从 `rs1` 中的地址加载 128 位数据值，将加载的值与由 `rd` 和 `rd+1` 组成的寄存器对中保存的 128 位值进行比较，如果比较是逐位相等的，则将寄存器对 `rs2` 和 `rs2+1` 中保存的 128 位值存储到 `rs1` 中的原始地址。从内存加载的值被放入寄存器对 `rd` 和 `rd+1`。该指令要求寄存器对中的第一个寄存器为偶数编号；在 `rs2` 和 `rd` 中指定奇数编号寄存器的编码是保留的。当源寄存器对的第一个寄存器是 `x0` 时，该对的两半都读为零。当目标寄存器对的第一个寄存器是 `x0` 时，整个寄存器结果被丢弃，且两个目标寄存器都不被写入。`AMOCAS.Q` 执行的操作如下：

```
    temp0 = mem[X(rs1)+0]
    temp1 = mem[X(rs1)+8]
    comp0 = (rd == x0)  ? 0 : X(rd)
    comp1 = (rd == x0)  ? 0 : X(rd+1)
    swap0 = (rs2 == x0) ? 0 : X(rs2)
    swap1 = (rs2 == x0) ? 0 : X(rs2+1)
    if ( temp0 == comp0 ) && ( temp1 == comp1 )
        mem[X(rs1)+0] = swap0
        mem[X(rs1)+8] = swap1
    endif
    if ( rd != x0 )
        X(rd)   = temp0
        X(rd+1) = temp1
    endif
```

**评论：** _某些算法可能将内存位置的先前数据值加载到被 Zacas 指令用作比较数据值源的寄存器中。当使用寄存器对来提供比较值的 Zacas 指令时，这两个寄存器可以通过两个单独的加载来加载。两次单独的加载可能读取到不一致的值对，但这没有问题，因为 `AMOCAS` 操作本身使用来自内存的原子加载对来获取用于比较的数据值。_

**评论：** _以下示例代码序列说明了在 RV32 实现中使用 `AMOCAS.D` 对 64 位计数器进行原子递增。_

##

```
# a0 - address of the counter.
increment:
  lw   a2, (a0)      # Load current counter value using
  lw   a3, 4(a0)     # two individual loads.
retry:
  mv   a6, a2        # Save the low 32 bits of the current value.
  mv   a7, a3        # Save the high 32 bits of the current
value.
  addi a4, a2, 1     # Increment the low 32 bits.
  sltu a1, a4, a2    # Determine if there is a carry out.
  add  a5, a3, a1    # Add the carry if any to high 32 bits.
  amocas.d.aqrl a2, a4, (a0)
  bne  a2, a6, retry # If amocas.d failed then retry
  bne  a3, a7, retry # using current values loaded by amocas.d.
  ret
```

与 A 扩展中的 AMO 一样，`AMOCAS.W/D/Q` 要求 `rs1` 中保存的地址自然对齐到操作数的大小（即四字为 16 字节对齐，双字为八字节对齐，字为四字节对齐）。如果地址未自然对齐，同样的异常选项适用。

与 A 扩展中的 AMO 一样，`AMOCAS.W/D/Q` 可选地使用 `aq` 和 `rl` 位提供 release consistency 语义，以帮助实现多处理器同步。`AMOCAS.W/D/Q` 执行的内存操作在成功时，如果 `aq` 位为 1 则具有 acquire 语义，如果 `rl` 位为 1 则具有 release 语义。`AMOCAS.W/D/Q` 执行的内存操作在不成功时，如果 `aq` 位为 1 则具有 acquire 语义，但不具有 release 语义，无论 `rl` 为何值。

FENCE 指令可用于对 `AMOCAS.W/D/Q` 指令的内存读取访问以及（如果产生的话）内存写入访问进行排序。

**评论：** _不成功的 `AMOCAS.W/D/Q` 可以不执行内存写入，也可以将旧值写回内存。如果产生内存写入，则无论 `rl` 为何值，它都不具有 release 语义。无论实际上是否执行写入，该指令在 RVWMO PPO 规则中被视为 AMO。_

`AMOCAS.W/D/Q` 指令始终要求写权限。

**评论：** _以下示例代码序列说明了使用 `AMOCAS.Q` 实现非阻塞并发队列的入队操作，采用 (Michael & Scott, 1996) 中概述的算法。该算法使用 `AMOCAS.Q` 指令对指针及其关联的修改计数器进行原子操作，以避免 ABA 问题。_

```
# Enqueue operation of a non-blocking concurrent queue.
# Data structures used by the queue:
#   structure pointer_t {ptr:   node_t *, count: uint64_t}
#   structure node_t    {next: pointer_t, value: data type}
#   structure queue_t   {Head: pointer_t, Tail:  pointer_t}
# Inputs to the procedure:
#   a0 - address of Tail variable
#   a4 - address of a new node to insert at tail
enqueue:
  ld   a6, (a0)          # a6 = Tail.ptr
  ld   a7, 8(a0)         # a7 = Tail.count
  ld   a2, (a6)          # a2 = Tail.ptr->next.ptr
  ld   a3, 8(a6)         # a3 = Tail.ptr->next.count
  ld   t1, (a0)
  ld   t2, 8(a0)
  bne  a6, t1, enqueue   # Retry if Tail & next are not
consistent
  bne  a7, t2, enqueue   # Retry if Tail & next are not
consistent
  bne  a2, x0, move_tail # Was tail pointing to the last node?
  mv   t1, a2            # Save Tail.ptr->next.ptr
  mv   t2, a3            # Save Tail.ptr->next.count
  addi a5, a3, 1         # Link the node at the end of the list
  amocas.q.aqrl a2, a4, (a6)
  bne  a2, t1, enqueue   # Retry if CAS failed
  bne  a3, t2, enqueue   # Retry if CAS failed
  addi a5, a7, 1         # Update Tail to the inserted node
  amocas.q.aqrl a6, a4, (a0)
  ret                    # Enqueue done
move_tail:               # Tail was not pointing to the last node
  addi a3, a7, 1         # Try to swing Tail to the next node
  amocas.q.aqrl a6, a2, (a0)
```

```
  j    enqueue           # Retry
```
