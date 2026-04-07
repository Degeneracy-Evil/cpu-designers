/*
!!! 本程序没有考虑以下问题
+ 特殊情形修正
  - *同号相除且能整除*（如 $(-8) / (-8)$）：若余数等于除数，则余数减去除数，商加 1。  
  - *异号相除且能整除*（如 $(-8) / 2$）：若余数加上除数为 0，则商减 1，余数置 0。
*/

#include <stdint.h>
#include <stdio.h>

#define N 5                     // 操作数位数
#define MASK ((1 << N) - 1)     // 低N位掩码
#define SIGN_BIT (1 << (N - 1)) // 符号位掩码

// 将N位补码转换为有符号整数（用于显示）
int to_signed(uint8_t val) {
  if (val & SIGN_BIT)
    return (int)(val | ~MASK); // 符号扩展为int
  else
    return (int)val;
}

// 判断两个N位补码数是否同号
int same_sign(uint8_t a, uint8_t b) {
  return ((a & SIGN_BIT) == (b & SIGN_BIT));
}

int main() {

  printf("输入[-16,15]之间的x,y:");
  int ai, bi;
  scanf("%d%d", &ai, &bi);

  // 原始数据（5位补码）
  // uint8_t x = 0b10010;   // -14
  // uint8_t y = 0b00100;   // 4
  uint8_t x = (uint8_t)ai;             // -14
  uint8_t y = (uint8_t)bi;             // 4
  uint8_t y_neg = (~y + 1) & MASK; // -4 的补码 11100

  // 符号扩展被除数到 2N 位（这里用 10 位寄存器 reg 表示，高5位R，低5位Q）
  uint16_t reg = (uint16_t)((x & SIGN_BIT ? 0b11111 : 0) << N) | x;

  printf("计算: %d / %d  (5位补码)\n", to_signed(x), to_signed(y));
  printf("除数 Y = 0x%02X (%d)\n", y, to_signed(y));
  printf("初始化 reg = 0x%04X (R=0x%02X, Q=0x%02X)\n\n", reg, (reg >> N) & MASK,
         reg & MASK);

  uint8_t R = (reg >> N) & MASK;
  uint8_t Q = reg & MASK;

  // 迭代 N 次
  for (int i = 1; i <= N; i++) {
    // 1. 左移 (R,Q) 组合
    reg <<= 1;
    R = (reg >> N) & MASK;
    Q = reg & MASK;
    printf("第 %d 次左移后: R=0x%02X (%d), Q=0x%02X (%d)\n", i, R, to_signed(R),
           Q, to_signed(Q));

    // 2. 根据 R 与 Y 的符号决定加减
    uint8_t new_R;
    if (same_sign(R, y)) {
      printf("   R与Y同号，执行 R = R - Y = ");
      new_R = (R - y) & MASK;
      printf("0x%02X - 0x%02X = 0x%02X\n", R, y, new_R);
    } else {
      printf("   R与Y异号，执行 R = R + Y = ");
      new_R = (R + y) & MASK;
      printf("0x%02X + 0x%02X = 0x%02X\n", R, y, new_R);
    }
    R = new_R;

    // 3. 确定商位
    int q_bit = same_sign(R, y) ? 1 : 0;
    printf("   新R与Y%s，上商 %d\n", same_sign(R, y) ? "同号" : "异号", q_bit);

    // 4. 将商位放入 Q 的最低位
    Q = (Q & ~1) | q_bit;

    // 5. 更新 reg
    reg = ((uint16_t)R << N) | Q;
    printf("   更新后: R=0x%02X (%d), Q=0x%02X (%d)\n\n", R, to_signed(R), Q,
           to_signed(Q));
  }

  // 未修正的商和余数
  uint8_t raw_Q = Q;
  uint8_t raw_R = R;

  // 修正商
  if (same_sign(x, y) == 0) { // 被除数与除数异号
    raw_Q = (raw_Q + 1) & MASK;
    printf("被除数与除数异号，商加1: 0x%02X -> 0x%02X\n", Q, raw_Q);
  } else {
    printf("被除数与除数同号，商不变\n");
  }

  // 修正余数
  if (same_sign(raw_R, x) == 0) { // 余数与最终被除数异号
    if (same_sign(x, y)) {
      raw_R = (raw_R + y) & MASK;
      printf("余数与被除数异号且除数同号，余数加除数: 0x%02X -> 0x%02X\n", R,
             raw_R);
    } else {
      raw_R = (raw_R - y) & MASK;
      printf("余数与被除数异号且除数异号，余数减除数: 0x%02X -> 0x%02X\n", R,
             raw_R);
    }
  } else {
    printf("余数与被除数同号，无需修正\n");
  }

  // 特殊处理：整除且不同符号的情况（如 -8/2 的 bug）
  if (same_sign(x, y) == 0 && raw_R == 0 && raw_Q == (x / y)) {
    // 实际上 -13/4 不整除，此条件不触发，但为通用保留
    raw_Q = (raw_Q - 1) & MASK;
    raw_R = 0;
    printf("检测到整除且异号，修正商减1，余数置0\n");
  }

  // 输出最终结果
  printf("\n最终结果:\n");
  printf("  商 = 0x%02X (%d)\n", raw_Q, to_signed(raw_Q));
  printf("  余数 = 0x%02X (%d)\n", raw_R, to_signed(raw_R));
  printf("验证: %d = %d * %d + %d\n", to_signed(x), to_signed(y),
         to_signed(raw_Q), to_signed(raw_R));

  return 0;
}