## 附录C：向量汇编代码示例

以下是作为非规范性文本提供的，以帮助解释向量ISA。

## C.1. 向量-向量加法示例

```
    # 32位整数的向量-向量加法例程
    # void vvaddint32(size_t n, const int*x, const int*y, int*z)
    # { for (size_t i=0; i<n; i++) { z[i]=x[i]+y[i]; } }
    #
    # a0 = n, a1 = x, a2 = y, a3 = z
    # 非向量指令缩进
vvaddint32:
    vsetvli t0, a0, e32, m1, ta, ma  # 基于32位设置向量长度
                                      # 向量
    vle32.v v0, (a1)         # 获取第一个向量
      sub a0, a0, t0         # 递减已完成数量
      slli t0, t0, 2         # 将已完成数量乘以4字节
      add a1, a1, t0         # 增加指针
    vle32.v v1, (a2)         # 获取第二个向量
      add a2, a2, t0         # 增加指针
    vadd.vv v2, v0, v1       # 向量求和
    vse32.v v2, (a3)         # 存储结果
      add a3, a3, t0         # 增加指针
      bnez a0, vvaddint32    # 循环返回
      ret                    # 完成
```

## C.2. 混合宽度掩码和计算示例

```
# 使用一种宽度进行谓词计算和不同宽度进行掩码计算的代码。
#   int8_t a[]; int32_t b[], c[];
#   for (i=0;  i<n; i++) { b[i] =  (a[i] < 5) ? c[i] : 1; }
#
# 保持SEW/LMUL=8的混合宽度代码
  loop:
    vsetvli a4, a0, e8, m1, ta, ma   # 用于谓词计算的字节向量
    vle8.v v1, (a1)               # 加载 a[i]
      add a1, a1, a4              # 增加指针。
    vmslt.vi v0, v1, 5            # a[i] < 5?
    vsetvli x0, a0, e32, m4, ta, mu  # 32位值的向量。
      sub a0, a0, a4              # 递减计数
    vmv.v.i v4, 1                 # 将立即数展开到目的地
    vle32.v v4, (a3), v0.t        # 加载请求的C元素，其他不受干扰
      sll t1, a4, 2
      add a3, a3, t1              # 增加指针。
    vse32.v v4, (a2)              # 存储 b[i]。
      add a2, a2, t1              # 增加指针。
      bnez a0, loop               # 还有更多吗？
```

## C.3. Memcpy示例

```
    # void *memcpy(void* dest, const void* src, size_t n)
    # a0=dest, a1=src, a2=n
    #
  memcpy:
      mv a3, a0 # 复制目的地
  loop:
    vsetvli t0, a2, e8, m8, ta, ma   # 8b向量
    vle8.v v0, (a1)               # 加载字节
      add a1, a1, t0              # 增加指针
      sub a2, a2, t0              # 递减计数
    vse8.v v0, (a3)               # 存储字节
      add a3, a3, t0              # 增加指针
      bnez a2, loop               # 还有更多吗？
      ret                         # 返回
```

## C.4. 条件示例

```
# (int16) z[i] = ((int8) x[i] < 5) ? (int16) a[i] : (int16) b[i];
#
loop:
    vsetvli t0, a0, e8, m1, ta, ma # 使用8b元素。
    vle8.v v0, (a1)         # 获取 x[i]
      sub a0, a0, t0        # 递减元素计数
      add a1, a1, t0        # x[i] 增加指针
    vmslt.vi v0, v0, 5      # 在v0中设置掩码
    vsetvli x0, x0, e16, m2, ta, mu  # 使用16b元素。
      slli t0, t0, 1        # 乘以2字节
    vle16.v v2, (a2), v0.t  # z[i] = a[i] 情况
    vmnot.m v0, v0          # 反转v0
      add a2, a2, t0        # a[i] 增加指针
    vle16.v v2, (a3), v0.t  # z[i] = b[i] 情况
      add a3, a3, t0        # b[i] 增加指针
    vse16.v v2, (a4)        # 存储 z
      add a4, a4, t0        # z[i] 增加指针
      bnez a0, loop
```

## C.5. SAXPY示例

```
# void
# saxpy(size_t n, const float a, const float *x, float *y)
# {
#   size_t i;
#   for (i=0; i<n; i++)
#     y[i] = a * x[i] + y[i];
# }
#
# 寄存器参数：
#     a0      n
#     fa0     a
#     a1      x
#     a2      y
saxpy:
    vsetvli a4, a0, e32, m8, ta, ma
    vle32.v v0, (a1)
    sub a0, a0, a4
    slli a4, a4, 2
    add a1, a1, a4
    vle32.v v8, (a2)
    vfmacc.vf v8, fa0, v0
    vse32.v v8, (a2)
    add a2, a2, a4
    bnez a0, saxpy
    ret
```

## C.6. SGEMM示例

```
# RV64IDV系统
#
# void
# sgemm_nn(size_t n,
#          size_t m,
#          size_t k,
#          const float*a,   // m * k 矩阵
#          size_t lda,
#          const float*b,   // k * n 矩阵
#          size_t ldb,
#          float*c,         // m * n 矩阵
#          size_t ldc)
#
#  c += a*b (alpha=1, 输入矩阵不转置)
#  矩阵以C行优先顺序存储
```

```
#define n a0
#define m a1
#define k a2
#define ap a3
#define astride a4
#define bp a5
#define bstride a6
#define cp a7
#define cstride t0
#define kt t1
#define nt t2
#define bnp t3
#define cnp t4
#define akp t5
#define bkp s0
#define nvl s1
#define ccp s2
#define amp s3
# 使用args作为额外的临时变量
#define ft12 fa0
#define ft13 fa1
#define ft14 fa2
#define ft15 fa3
# 此版本在内循环中将C矩阵的16*VLMAX块保存在向量寄存器中，
# 但在其他方面不进行缓存或TLB分块。
sgemm_nn:
    addi sp, sp, -FRAMESIZE
    sd s0, OFFSET(sp)
    sd s1, OFFSET(sp)
    sd s2, OFFSET(sp)
    # 检查零大小矩阵
    beqz n, exit
    beqz m, exit
    beqz k, exit
    # 将元素步幅转换为字节步幅。
    ld cstride, OFFSET(sp)   # 从栈帧获取参数
    slli astride, astride, 2
    slli bstride, bstride, 2
    slli cstride, cstride, 2
    slti t6, m, 16
    bnez t6, end_rows
c_row_loop: # 跨越C块行的循环
```

```
    mv nt, n  # 为下一行C块初始化n计数器
```

```
    mv bnp, bp # 初始化B n循环指针到开始
    mv cnp, cp # 初始化C n循环指针
c_col_loop: # 跨越一行C块的循环
    vsetvli nvl, nt, e32, m1, ta, ma  # 32位向量，LMUL=1
    mv akp, ap   # 将A的指针重置到开始
    mv bkp, bnp # 步进到B矩阵的下一列
```

```
    # 从内存初始化当前C子矩阵块。
    vle32.v  v0, (cnp); add ccp, cnp, cstride;
    vle32.v  v1, (ccp); add ccp, ccp, cstride;
    vle32.v  v2, (ccp); add ccp, ccp, cstride;
    vle32.v  v3, (ccp); add ccp, ccp, cstride;
    vle32.v  v4, (ccp); add ccp, ccp, cstride;
    vle32.v  v5, (ccp); add ccp, ccp, cstride;
    vle32.v  v6, (ccp); add ccp, ccp, cstride;
    vle32.v  v7, (ccp); add ccp, ccp, cstride;
    vle32.v  v8, (ccp); add ccp, ccp, cstride;
    vle32.v  v9, (ccp); add ccp, ccp, cstride;
    vle32.v v10, (ccp); add ccp, ccp, cstride;
    vle32.v v11, (ccp); add ccp, ccp, cstride;
    vle32.v v12, (ccp); add ccp, ccp, cstride;
    vle32.v v13, (ccp); add ccp, ccp, cstride;
    vle32.v v14, (ccp); add ccp, ccp, cstride;
    vle32.v v15, (ccp)
```

```
    mv kt, k # 初始化内循环计数器
```

```
    # 内循环，假设vfmacc指令4个时钟占用和单发射流水线
    # 软件流水线加载
    flw ft0, (akp); add amp, akp, astride;
    flw ft1, (amp); add amp, amp, astride;
    flw ft2, (amp); add amp, amp, astride;
    flw ft3, (amp); add amp, amp, astride;
    # 从B矩阵获取向量
    vle32.v v16, (bkp)
```

```
    # 在当前C块的内维上的循环
 k_loop:
    vfmacc.vf v0, ft0, v16
    add bkp, bkp, bstride
    flw ft4, (amp)
    add amp, amp, astride
    vfmacc.vf v1, ft1, v16
    addi kt, kt, -1    # 递减k计数器
```

```
    flw ft5, (amp)
    add amp, amp, astride
    vfmacc.vf v2, ft2, v16
    flw ft6, (amp)
    add amp, amp, astride
    flw ft7, (amp)
    vfmacc.vf v3, ft3, v16
    add amp, amp, astride
    flw ft8, (amp)
    add amp, amp, astride
    vfmacc.vf v4, ft4, v16
    flw ft9, (amp)
    add amp, amp, astride
    vfmacc.vf v5, ft5, v16
    flw ft10, (amp)
    add amp, amp, astride
    vfmacc.vf v6, ft6, v16
    flw ft11, (amp)
    add amp, amp, astride
    vfmacc.vf v7, ft7, v16
    flw ft12, (amp)
    add amp, amp, astride
    vfmacc.vf v8, ft8, v16
    flw ft13, (amp)
    add amp, amp, astride
    vfmacc.vf v9, ft9, v16
    flw ft14, (amp)
    add amp, amp, astride
    vfmacc.vf v10, ft10, v16
    flw ft15, (amp)
    add amp, amp, astride
    addi akp, akp, 4            # 移动到a的下一列
    vfmacc.vf v11, ft11, v16
    beqz kt, 1f                 # 不要加载超过矩阵末尾
    flw ft0, (akp)
    add amp, akp, astride
1:  vfmacc.vf v12, ft12, v16
    beqz kt, 1f
    flw ft1, (amp)
    add amp, amp, astride
1:  vfmacc.vf v13, ft13, v16
    beqz kt, 1f
    flw ft2, (amp)
    add amp, amp, astride
1:  vfmacc.vf v14, ft14, v16
    beqz kt, 1f                 # 退出循环
    flw ft3, (amp)
    add amp, amp, astride
    vfmacc.vf v15, ft15, v16
    vle32.v v16, (bkp)            # 从B矩阵获取下一个向量，加载与跳转停顿重叠
    j k_loop
```

```
1:  vfmacc.vf v15, ft15, v16
    # 将C矩阵块保存回内存
    vse32.v  v0, (cnp); add ccp, cnp, cstride;
    vse32.v  v1, (ccp); add ccp, ccp, cstride;
    vse32.v  v2, (ccp); add ccp, ccp, cstride;
    vse32.v  v3, (ccp); add ccp, ccp, cstride;
    vse32.v  v4, (ccp); add ccp, ccp, cstride;
    vse32.v  v5, (ccp); add ccp, ccp, cstride;
    vse32.v  v6, (ccp); add ccp, ccp, cstride;
    vse32.v  v7, (ccp); add ccp, ccp, cstride;
    vse32.v  v8, (ccp); add ccp, ccp, cstride;
    vse32.v  v9, (ccp); add ccp, ccp, cstride;
    vse32.v v10, (ccp); add ccp, ccp, cstride;
    vse32.v v11, (ccp); add ccp, ccp, cstride;
    vse32.v v12, (ccp); add ccp, ccp, cstride;
    vse32.v v13, (ccp); add ccp, ccp, cstride;
    vse32.v v14, (ccp); add ccp, ccp, cstride;
    vse32.v v15, (ccp)
```

```
    # 以下尾部指令应在C块保存期间的空闲槽中更早调度。
    # 留在这里以保持清晰。
```

```
    # 为跨越一行中块的循环增加指针
    slli t6, nvl, 2
    add cnp, cnp, t6                         # 移动C块指针
    add bnp, bnp, t6                         # 移动B块指针
    sub nt, nt, nvl                          # 递减n维中的元素计数
    bnez nt, c_col_loop                      # 还有更多要做的吗？
    # 移动到下一组行
    addi m, m, -16  # 上面做了16行
    slli t6, astride, 4  # 将astride乘以16
    add ap, ap, t6         # 将A矩阵指针向下移动16行
    slli t6, cstride, 4  # 将cstride乘以16
    add cp, cp, t6         # 将C矩阵指针向下移动16行
    slti t6, m, 16
    beqz t6, c_row_loop
    # 处理少于16行的矩阵末尾。
    # 可以使用上述的较小版本，根据代码大小关注按2的幂递减。
end_rows:
    # 未完成。
```

```
exit:
    ld s0, OFFSET(sp)
    ld s1, OFFSET(sp)
    ld s2, OFFSET(sp)
    addi sp, sp, FRAMESIZE
    ret
```

## C.7. 除法近似示例

```
# v1 = v1 / v2 精度接近23位。
vfrec7.v v3, v2             # 估计 1/v2
  li t0, 0x3f800000
vmv.v.x v4, t0              # 展开 1.0
vfnmsac.vv v4, v2, v3       # 1.0 - v2 * est(1/v2)
vfmadd.vv v3, v4, v3        # 更好的1/v2估计
vmv.v.x v4, t0              # 展开 1.0
vfnmsac.vv v4, v2, v3       # 1.0 - v2 * est(1/v2)
vfmadd.vv v3, v4, v3        # 更好的1/v2估计
vfmul.vv v1, v1, v3         # v1/v2的估计
```

## C.8. 平方根近似示例

```
# v1 = sqrt(v1) 精度超过23位。
  fmv.w.x ft0, x0           # 屏蔽零输入
vmfne.vf v0, v1, ft0        #   以避免DZ异常
vfrsqrt7.v v2, v1, v0.t     # 估计 r ~= 1/sqrt(v1)
vmfne.vf v0, v2, ft0, v0.t  # 屏蔽+inf以避免NV
  li t0, 0x3f800000
  fli.s ft0, 0.5
vmv.v.x v5, t0              # 展开 1.0
vfmul.vv v3, v1, v2, v0.t   # t = v1 r
vfmul.vf v4, v2, ft0, v0.t  # 0.5 r
vfmsub.vv v3, v2, v5, v0.t  # t r - 1
vfnmsac.vv v2, v3, v4, v0.t # r - (0.5 r) (t r - 1)
                             # 更好的1/sqrt(v1)估计
vfmul.vv v1, v1, v2, v0.t   # t = v1 r
vfmsub.vv v2, v1, v5, v0.t  # t r - 1
vfmul.vf v3, v1, ft0, v0.t  # 0.5 t
vfnmsac.vv v1, v2, v3, v0.t # t - (0.5 t) (t r - 1)
                             # ~ sqrt(v1) 精度约23.3位
```

## C.9. C标准库strcmp示例

```
  # int strcmp(const char *src1, const char* src2)
strcmp:
    ##  使用LMUL=2，但相同的寄存器名称适用于更大的LMUL
    li t1, 0                # 初始指针增量
loop:
    vsetvli t0, x0, e8, m2, ta, ma  # 最大长度字节向量
    add a0, a0, t1          # 增加src1指针
    vle8ff.v v8, (a0)       # 获取src1字节
    add a1, a1, t1          # 增加src2指针
    vle8ff.v v16, (a1)      # 获取src2字节
    vmseq.vi v0, v8, 0      # 标记src1中的零字节
    vmsne.vv v1, v8, v16    # 标记 src1 != src2
    vmor.mm v0, v0, v1      # 组合退出条件
    vfirst.m a2, v0         # ==0 或 != ?
    csrr t1, vl             # 获取获取的字节数
    bltz a2, loop           # 如果全部相同且无零字节则循环
    add a0, a0, a2          # 获取src1元素地址
    lbu a3, (a0)            # 从内存获取src1字节
    add a1, a1, a2          # 获取src2元素地址
    lbu a4, (a1)            # 从内存获取src2字节
    sub a0, a3, a4          # 返回值。
    ret
```

## C.10. 分数LMUL示例

本附录提供一个非规范性示例，帮助解释编译器在哪些情况下可以良好利用分数LMUL特性。

考虑以下用C编写的（公认是人为构造的）循环：

```
voidadd_ref(long N,
```

```
signedchar *restrict c_c, signedchar *restrict c_a, signedchar *restrict
c_b,
long *restrict l_c, long *restrict l_a, long *restrict l_b,
long *restrict l_d, long *restrict l_e, long *restrict l_f,
long *restrict l_g, long *restrict l_h, long *restrict l_i,
long *restrict l_j, long *restrict l_k, long *restrict l_l,
long *restrict l_m) {
long i;
```

```
for (i = 0; i < N; i++) {
    c_c[i] = c_a[i] + c_b[i]; // 注意这个'char'加法创建了一个混合类型情况
    l_c[i] = l_a[i] + l_b[i];
    l_f[i] = l_d[i] + l_e[i];
    l_i[i] = l_g[i] + l_h[i];
    l_l[i] = l_k[i] + l_j[i];
    l_m[i] += l_m[i] + l_c[i] + l_f[i] + l_i[i] + l_l[i];
  }
}
```

示例循环由于所需的许多输入变量和临时变量而具有高寄存器压力。编译器意识到循环内有两种数据类型：8位'char'和64位'long *'。没有分数LMUL，编译器将被迫对8位计算使用LMUL=1，对64位计算使用LMUL=8，以在同一循环迭代中的所有计算上具有相等的元素数量。在LMUL=8下，只有4个寄存器可用于寄存器分配器。考虑到此循环中需要的大量64位变量和临时变量，编译器最终会生成大量溢出代码。下面的代码演示了这种效果：

```
.LBB0_4:                                # %vector.body
                                        # =>This Inner Loop Header: Depth=1
    add     s9, a2, s6
    vsetvli s1, zero, e8,m1,ta,mu
    vle8.v  v25, (s9)
    add     s1, a3, s6
    vle8.v  v26, (s1)
    vadd.vv v25, v26, v25
    add     s1, a1, s6
    vse8.v  v25, (s1)
    add     s9, a5, s10
    vsetvli s1, zero, e64,m8,ta,mu
    vle64.v v8, (s9)
    add s1, a6, s10
    vle64.v v16, (s1)
    add     s1, a7, s10
    vle64.v v24, (s1)
    add     s1, s3, s10
    vle64.v v0, (s1)
    sd      a0, -112(s0)
    ld      a0, -128(s0)
    vs8r.v  v0, (a0) # 溢出LMUL=8
    add     s9, t6, s10
    add     s11, t5, s10
    add     ra, t2, s10
    add     s1, t3, s10
    vle64.v v0, (s9)
    ld      s9, -136(s0)
    vs8r.v  v0, (s9) # 溢出LMUL=8
    vle64.v v0, (s11)
```

```
    ld      s9, -144(s0)
    vs8r.v  v0, (s9) # 溢出LMUL=8
    vle64.v v0, (ra)
    ld      s9, -160(s0)
    vs8r.v  v0, (s9) # 溢出LMUL=8
    vle64.v v0, (s1)
    ld      s1, -152(s0)
    vs8r.v  v0, (s1) # 溢出LMUL=8
    vadd.vv v16, v16, v8
    ld      s1, -128(s0)
    vl8r.v  v8, (s1) # 重新加载LMUL=8
    vadd.vv v8, v8, v24
    ld      s1, -136(s0)
    vl8r.v  v24, (s1) # 重新加载LMUL=8
    ld      s1, -144(s0)
    vl8r.v  v0, (s1) # 重新加载LMUL=8
    vadd.vv v24, v0, v24
    ld      s1, -128(s0)
    vs8r.v  v24, (s1) # 溢出LMUL=8
    ld      s1, -152(s0)
    vl8r.v  v0, (s1) # 重新加载LMUL=8
    ld      s1, -160(s0)
    vl8r.v  v24, (s1) # 重新加载LMUL=8
    vadd.vv v0, v0, v24
    add     s1, a4, s10
    vse64.v v16, (s1)
    add     s1, s2, s10
    vse64.v v8, (s1)
    vadd.vv v8, v8, v16
    add     s1, t4, s10
    ld      s9, -128(s0)
    vl8r.v  v16, (s9) # 重新加载LMUL=8
    vse64.v v16, (s1)
    add     s9, t0, s10
    vadd.vv v8, v8, v16
    vle64.v v16, (s9)
    add     s1, t1, s10
    vse64.v v0, (s1)
    vadd.vv v8, v8, v0
    vsll.vi v16, v16, 1
    vadd.vv v8, v8, v16
    vse64.v v8, (s9)
    add     s6, s6, s7
    add     s10, s10, s8
    bne     s6, s4, .LBB0_4
```

如果编译器不使用LMUL=1进行8位计算，而是允许使用分数LMUL=1/2，那么64位计算可以使用LMUL=4执行（注意，64位元素和8位元素的比例与前一示例中相同）。现在编译器有8个可用寄存器来执行寄存器分配，结果是没有溢出代码，如下面的循环所示：

```
.LBB0_4:                                # %vector.body
                                        # =>This Inner Loop Header: Depth=1
    add     s9, a2, s6
    vsetvli s1, zero, e8,mf2,ta,mu // LMUL=1/2 !
    vle8.v  v25, (s9)
    add     s1, a3, s6
    vle8.v  v26, (s1)
    vadd.vv v25, v26, v25
    add     s1, a1, s6
    vse8.v  v25, (s1)
    add     s9, a5, s10
    vsetvli s1, zero, e64,m4,ta,mu // LMUL=4
    vle64.v v28, (s9)
    add     s1, a6, s10
    vle64.v v8, (s1)
    vadd.vv v28, v8, v28
    add     s1, a7, s10
    vle64.v v8, (s1)
    add s1, s3, s10
    vle64.v v12, (s1)
    add     s1, t6, s10
    vle64.v v16, (s1)
    add     s1, t5, s10
    vle64.v v20, (s1)
    add     s1, a4, s10
    vse64.v v28, (s1)
    vadd.vv v8, v12, v8
    vadd.vv v12, v20, v16
    add     s1, t2, s10
    vle64.v v16, (s1)
    add     s1, t3, s10
    vle64.v v20, (s1)
    add     s1, s2, s10
    vse64.v v8, (s1)
    add     s9, t4, s10
    vadd.vv v16, v20, v16
    add     s11, t0, s10
    vle64.v v20, (s11)
    vse64.v v12, (s9)
    add     s1, t1, s10
    vse64.v v16, (s1)
    vsll.vi v20, v20, 1
    vadd.vv v28, v8, v28
    vadd.vv v28, v28, v12
    vadd.vv v28, v28, v16
    vadd.vv v28, v28, v20
    vse64.v v28, (s11)
```

```
    add     s6, s6, s7
    add     s10, s10, s8
    bne     s6, s4, .LBB0_4
```
