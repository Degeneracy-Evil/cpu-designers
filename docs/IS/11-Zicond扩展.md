# 第11章 "Zicond" 整数条件操作扩展，版本 1.0.0

Zicond 扩展定义了两条 R-type 指令，支持无分支条件操作。

|RV32|RV64|Mnemonic|Instruction|
|---|---|---|---|
|✓|✓|czero.eqz_rd_,_rs1_,_rs2_|条件置零，若条件等于零|
|✓|✓|czero.nez_rd_,_rs1_,_rs2_|条件置零，若条件非零|

## 11.1. 指令（按字母顺序）

## 11.1.1. czero.eqz

## 概要

若条件 _rs2_ 等于零，则将零移至寄存器 _rd_，否则将 _rs1_ 移至 _rd_。

## 助记符

czero.eqz _rd_, _rs1_, _rs2_

## 编码

|31||||||25|24||20|19||15||14||12||11||7|6||||||0|
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
|0|0|0|0|1|1|1||rs2|||rs1|||1|0|1|||rd||0|1|1|0|0|1|1|
|||CZERO||||||condition|||value||CZERO.EQZ|||||||||||OP||||

## 描述

如果 _rs2_ 包含值零，此指令将值零写入 _rd_。否则，此指令将 _rs1_ 的内容复制到 _rd_。

此指令携带从 _rs1_ 和 _rs2_ 两者到 _rd_ 的句法依赖。

此外，如果实现了 Zkt 扩展，此指令的时序与 _rs1_ 和 _rs2_ 中的数据值无关。

## SAIL 代码

```
let condition = X(rs2);
  result : xlenbits = if (condition == zeros()) then zeros()
else X(rs1);
  X(rd) = result;
```

## 11.1.2. czero.nez

## 概要

若条件 _rs2_ 为非零，则将零移至寄存器 _rd_，否则将 _rs1_ 移至 _rd_。

## 助记符

czero.nez _rd_, _rs1_, _rs2_

## 编码

|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>31|
|---|---|---|---|---|---|
|1<br>1<br>1<br>0<br>0<br>0<br>0|rs2|rs1|1<br>1<br>1|rd|1<br>1<br>0<br>0<br>1<br>1<br>0|
|OP<br>CZERO.NEZ<br>value<br>condition<br>CZERO||||||

## 描述

如果 _rs2_ 包含一个非零值，此指令将值零写入 _rd_。否则，此指令将 _rs1_ 的内容复制到 _rd_。

此指令携带从 _rs1_ 和 _rs2_ 两者到 _rd_ 的句法依赖。

此外，如果实现了 Zkt 扩展，此指令的时序与 _rs1_ 和 _rs2_ 中的数据值无关。

## SAIL 代码

```
let condition = X(rs2);
  result : xlenbits = if (condition != zeros()) then zeros()
else X(rs1);
  X(rd) = result;
```

## 11.2. 用例

此扩展中的指令可用于构造执行条件算术、条件按位逻辑和条件选择操作的序列。

## 11.2.1. 指令序列

|11.2.1. 指令序列|||
|---|---|---|
|Operation|Instruction sequence|Length|
|条件加法，若为零<br>`rd = (rc == 0) ? (rs1 + rs2) : rs1`|`czero.nez  rd, rs2, rc`<br>`add        rd, rs1, rd`||
|条件加法，若非零<br>`rd = (rc != 0) ? (rs1 + rs2) : rs1`|`czero.eqz  rd, rs2, rc`<br>`add        rd, rs1, rd`||
|条件减法，若为零<br>`rd = (rc == 0) ? (rs1 - rs2) : rs1`|`czero.nez  rd, rs2, rc`<br>`sub        rd, rs1, rd`||
|条件减法，若非零<br>`rd = (rc != 0) ? (rs1 - rs2) : rs1`|`czero.eqz  rd, rs2, rc`<br>`sub        rd, rs1, rd`||
|条件按位或，若为零<br>`rd = (rc == 0) ? (rs1 | rs2) : rs1`|`czero.nez  rd, rs2, rc`<br>`or         rd, rs1, rd`|2 insns|
|条件按位或，若非零<br>`rd = (rc != 0) ? (rs1 | rs2) : rs1`|`czero.eqz  rd, rs2, rc`<br>`or         rd, rs1, rd`||
|条件按位异或，若为零<br>`rd = (rc == 0) ? (rs1 ^ rs2) : rs1`|`czero.nez  rd, rs2, rc`<br>`xor        rd, rs1, rd`||
|条件按位异或，若非零<br>`rd = (rc != 0) ? (rs1 ^ rs2) : rs1`|`czero.eqz  rd, rs2, rc`<br>`xor        rd, rs1, rd`||
|条件按位与，若为零<br>`rd = (rc == 0) ? (rs1 & rs2) : rs1`|`and        rd, rs1, rs2`<br>`czero.eqz  rtmp, rs1, rc`<br>`or         rd, rd, rtmp`||
|条件按位与，若非零<br>`rd = (rc != 0) ? (rs1 & rs2) : rs1`|`and        rd, rs1, rs2`<br>`czero.nez  rtmp, rs1, rc`<br>`or         rd, rd, rtmp`|3 insns|
|条件选择，若为零<br>`rd = (rc == 0) ? rs1 : rs2`|`czero.nez  rd, rs1, rc`<br>`czero.eqz  rtmp, rs2, rc`<br>`add        rd, rd, rtmp`|(需要1个临时寄存器)|
|条件选择，若非零<br>`rd = (rc != 0) ? rs1 : rs2`|`czero.eqz  rd, rs1, rc`<br>`czero.nez  rtmp, rs2, rc`<br>`add        rd, rd, rtmp`||
