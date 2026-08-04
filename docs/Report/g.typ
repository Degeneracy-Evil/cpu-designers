#import "@local/cetz:0.5.0"

// 总体架构图 — SimpleCPU (RV32AIMFSU)
// 展示: 系统总体结构、时钟域、部件包含结构

#cetz.canvas({
  import cetz.draw: *

  // ============================================================
  //  颜色定义 — 按时钟域 / 功能分类
  // ============================================================
  let C-cpu   = rgb("#dbeafe")   // cpu_clk 域背景 (浅蓝)
  let C-sys   = rgb("#dcfce7")   // sys_clk 域背景 (浅绿)
  let C-ddr   = rgb("#ffedd5")   // ddr_clk_ref 域背景 (浅橙)
  let C-cdc   = rgb("#fef9c3")   // CDC 跨域桥 (浅黄)
  let C-pipe  = rgb("#f3e8ff")   // 流水线级 (浅紫)
  let C-cache = rgb("#ccfbf1")   // 缓存 (浅青)
  let C-mmu   = rgb("#e0e7ff")   // MMU (浅靛)
  let C-bus   = rgb("#ffe4e6")   // 总线桥 (浅红)
  let C-perip = rgb("#f5f5f4")   // 外设 (浅灰棕)
  let C-ctrl  = rgb("#fce7f3")   // 控制器 (浅粉)
  let C-reg   = rgb("#e8eaf6")   // 寄存器堆 (浅靛蓝)
  let C-clk   = rgb("#f1f5f9")   // 时钟/复位 (浅灰蓝)

  // ============================================================
  //  辅助函数
  // ============================================================
  // 模块方块 (带填充色、边框、居中标签)
  let blk(x1, y1, x2, y2, lab, fc: none, sc: black, sw: 0.7pt, sz: 7pt) = {
    rect((x1, y1), (x2, y2),
      fill: fc,
      stroke: (paint: sc, thickness: sw),
      radius: 0.06,
    )
    content(((x1 + x2) / 2, (y1 + y2) / 2),
      text(size: sz, weight: "bold", lab),
    )
  }

  // 子模块方块 (较小字体、细边框)
  let sub(x1, y1, x2, y2, lab, fc: none) = {
    rect((x1, y1), (x2, y2),
      fill: fc,
      stroke: (paint: black, thickness: 0.35pt),
      radius: 0.03,
    )
    content(((x1 + x2) / 2, (y1 + y2) / 2),
      text(size: 5.5pt, lab),
    )
  }

  // 带箭头的连接线
  let arr(a, b, c: black, w: 0.5pt) = {
    line(a, b,
      stroke: (paint: c, thickness: w),
      mark: (end: ">"),
    )
  }

  // ============================================================
  //  1. system_top 外边界
  // ============================================================
  rect((-0.3, -0.3), (17.3, 17.3),
    stroke: (paint: black, thickness: 1.5pt),
    radius: 0.12,
  )
  content((8.5, 17),
    text(size: 10pt, weight: "bold", "system\_top"),
  )

  // ============================================================
  //  2. Clock / Reset Architecture (顶部横条)
  // ============================================================
  rect((0.2, 15.5), (16.8, 16.7),
    fill: C-clk,
    stroke: (paint: black, thickness: 0.5pt),
    radius: 0.06,
  )
  content((8.5, 16.5),
    text(size: 7pt, weight: "bold", "Clock / Reset Architecture"),
  )

  sub(0.5, 15.65, 5.2, 16.35,
    [clk\_wiz\_0 (100→50/100/200 MHz)],
    fc: rgb("#e2e8f0"),
  )
  sub(5.4, 15.65, 10.8, 16.35,
    [reset\_sync ×2 (Async assert, Sync deassert)],
    fc: rgb("#e2e8f0"),
  )
  sub(11, 15.65, 16.5, 16.35,
    [ddr\_data\_init / ddr\_aresetn],
    fc: rgb("#e2e8f0"),
  )

  // ============================================================
  //  3. cpu_clk 域 (50 MHz) — core_top
  // ============================================================
  // 域背景 (虚线边框标识时钟域)
  rect((0.2, 0.0), (8.9, 15.3),
    fill: C-cpu,
    stroke: (paint: rgb("#2563eb"), thickness: 0.7pt, dash: "dashed"),
    radius: 0.08,
  )
  content((1.5, 15),
    text(size: 5.5pt, fill: rgb("#2563eb"), weight: "bold", "cpu\_clk  50 MHz"),
  )

  // core_top 边框
  rect((0.5, 0.1), (8.6, 14.6),
    stroke: (paint: black, thickness: 1pt),
    radius: 0.08,
  )
  content((1.8, 14.3),
    text(size: 8.5pt, weight: "bold", "core\_top"),
  )

  // ---- 3.1 cpu_controller (FSM) ----
  blk(0.8, 13, 8.3, 14.1,
    [cpu\_controller (FSM 11态)],
    fc: C-ctrl, sz: 6.5pt,
  )

  // ---- 3.2 五级流水线 ----
  blk(0.8, 9.2, 2.2, 12.7,
    [cpu\_fetch\
    (取指)],
    fc: C-pipe, sz: 6pt,
  )
  blk(2.4, 9.2, 3.8, 12.7,
    [cpu\_decode\
    (译码)],
    fc: C-pipe, sz: 6pt,
  )
  blk(4.0, 9.2, 6.4, 12.7,
    [cpu\_execute\
    (执行)],
    fc: C-pipe, sz: 6pt,
  )
  blk(6.6, 9.2, 7.3, 12.7,
    [cpu\_mem\
    (访存)],
    fc: C-pipe, sz: 5.5pt,
  )
  blk(7.5, 9.2, 8.3, 12.7,
    [cpu\_wb\
    (回写)],
    fc: C-pipe, sz: 5.5pt,
  )

  // execute 内子模块 (ALU / MU / FPU)
  sub(4.2, 9.4, 5.0, 10.7,
    [ALU\ (CLA)],
    fc: rgb("#fce7f3"),
  )
  sub(5.1, 9.4, 5.7, 10.7,
    [MU],
    fc: rgb("#fce7f3"),
  )
  sub(5.8, 9.4, 6.2, 10.7,
    [F\ P\ U],
    fc: rgb("#fce7f3"),
  )

  // 流水级间箭头
  arr((2.2, 11), (2.4, 11), c: gray, w: 0.4pt)
  arr((3.8, 11), (4.0, 11), c: gray, w: 0.4pt)
  arr((6.4, 11), (6.6, 11), c: gray, w: 0.4pt)
  arr((7.3, 11), (7.5, 11), c: gray, w: 0.4pt)

  // ---- 3.3 寄存器堆 & CSR ----
  blk(0.8, 6.3, 3.0, 8.9,
    [cpu\_regfile\
    32×32bit],
    fc: C-reg, sz: 6pt,
  )
  blk(3.2, 6.3, 5.4, 8.9,
    [fpu\_regfile\
    32×32bit],
    fc: C-reg, sz: 6pt,
  )
  blk(5.6, 6.3, 8.3, 8.9,
    [cpu\_trap\_csr\
    Trap + CSR],
    fc: rgb("#fce4ec"), sz: 6pt,
  )

  // ---- 3.4 缓存控制器 ----
  blk(0.8, 3.3, 4.3, 6,
    [icache\_ctrl\
    4路 VIPT 1KB],
    fc: C-cache, sz: 6pt,
  )
  blk(4.5, 3.3, 8.3, 6,
    [dcache\_ctrl\
    4路 VIPT 1KB],
    fc: C-cache, sz: 6pt,
  )

  // ---- 3.5 MMU & 总线桥 ----
  blk(0.8, 0.3, 4.3, 3,
    [MMU\
    Sv32 TLB+PTW],
    fc: C-mmu, sz: 6pt,
  )
  blk(4.5, 0.3, 8.3, 3,
    [cpu\_bus\_bridge\
    AXI4 5通道],
    fc: C-bus, sz: 6pt,
  )

  // core_top 内部连接
  // cache → MMU
  arr((2.5, 3.3), (2.5, 3), c: gray, w: 0.3pt)
  arr((6.4, 3.3), (6.4, 3), c: gray, w: 0.3pt)
  // MMU → bus_bridge
  arr((4.3, 1.6), (4.5, 1.6), c: gray, w: 0.3pt)

  // ============================================================
  //  4. Axi_CDC 跨域桥接
  // ============================================================
  rect((9.1, 1.2), (10.1, 12.5),
    fill: C-cdc,
    stroke: (paint: rgb("#d97706"), thickness: 0.8pt),
    radius: 0.06,
  )
  content((9.6, 7.5),
    text(size: 6.5pt, weight: "bold", [Axi\_CDC]),
  )
  content((9.6, 6.6),
    text(size: 5pt, [cpu\_clk\ →\ sys\_clk]),
  )

  // CDC 连接箭头
  arr((8.6, 6.8), (9.1, 6.8), c: rgb("#d97706"), w: 0.6pt)
  arr((10.1, 6.8), (10.5, 6.8), c: rgb("#d97706"), w: 0.6pt)

  // ============================================================
  //  5. sys_clk 域 (100 MHz) — 地址译码 + 从设备
  // ============================================================
  // 域背景
  rect((10.3, 0.0), (16.8, 15.3),
    fill: C-sys,
    stroke: (paint: rgb("#16a34a"), thickness: 0.7pt, dash: "dashed"),
    radius: 0.08,
  )
  content((11.6, 15),
    text(size: 5.5pt, fill: rgb("#16a34a"), weight: "bold", "sys\_clk  100 MHz"),
  )

  // 地址译码器边框
  rect((10.6, 0.1), (16.5, 14.6),
    stroke: (paint: black, thickness: 1pt),
    radius: 0.08,
  )
  content((13.1, 14.3),
    text(size: 7.5pt, weight: "bold", "Addr Decoder + Slave Mux"),
  )

  // ---- 从设备 ----
  blk(11, 12.5, 16.2, 14,
    [DDR3 / RAM\
    0x8000\_0000],
    fc: C-ddr, sz: 5.5pt,
  )
  blk(11, 10.8, 16.2, 12.3,
    [Boot ROM (32KB)\
    0xFC00\_0000],
    fc: rgb("#d1fae5"), sz: 5.5pt,
  )
  blk(11, 9.1, 13.5, 10.6,
    [PLIC (8源)\
    0x0C00\_0000],
    fc: C-perip, sz: 5.5pt,
  )
  blk(13.7, 9.1, 16.2, 10.6,
    [Sys Status\
    0x0400\_0000],
    fc: C-perip, sz: 5.5pt,
  )
  blk(11, 7.4, 13.5, 8.9,
    [CLINT\
    0x0200\_0000],
    fc: C-perip, sz: 5.5pt,
  )
  blk(13.7, 7.4, 16.2, 8.9,
    [Default Slave\
    DECERR],
    fc: rgb("#e5e5e5"), sz: 5.5pt,
  )

  // ---- APB Bridge ----
  rect((11, 0.3), (16.2, 7),
    fill: rgb("#fafaf9"),
    stroke: (paint: black, thickness: 0.6pt),
    radius: 0.05,
  )
  content((12.8, 6.5),
    text(size: 6.5pt, weight: "bold", "APB Bridge (0x1000_0000)"),
  )
  content((12.1, 6),
    text(size: 5pt, "AXI4-Lite → APB4"),
  )

  // APB 外设
  sub(11.3, 3.5, 13.6, 5.8,
    [GPIO\
    16-bit 双向 IO],
    fc: C-perip,
  )
  sub(13.8, 3.5, 15.9, 5.8,
    [Timer\
    32-bit],
    fc: C-perip,
  )
  sub(11.3, 0.5, 13.6, 3.2,
    [UART (ns16550a)\
    16-byte TX/RX FIFO],
    fc: C-perip,
  )
  sub(13.8, 0.5, 15.9, 3.2,
    [SPI\
    Master 模式],
    fc: C-perip,
  )

  // ============================================================
  //  6. ddr_clk_ref 域 (200 MHz) — 底部条
  // ============================================================
  rect((10.3, -0.1), (16.8, 0.2),
    fill: C-ddr,
    stroke: (paint: rgb("#ea580c"), thickness: 0.5pt, dash: "dashed"),
    radius: 0.03,
  )
  content((13.5, 0.05),
    text(size: 5pt, fill: rgb("#ea580c"), weight: "bold", "ddr\_clk\_ref  200 MHz"),
  )

  // ============================================================
  //  7. 关键数据通路箭头
  // ============================================================
  // bus_bridge → CDC (斜线表示跨模块连接)
  arr((8.3, 1.6), (9.1, 6.8), c: rgb("#d97706"), w: 0.5pt)

  // CDC → 地址译码器 (已在上方绘制)

  // icache → bus_bridge (缓存缺失走总线)
  line((4.3, 4.6), (4.5, 4.6),
    stroke: (paint: gray, thickness: 0.3pt),
    mark: (end: ">"),
  )

  // ============================================================
  //  8. 时钟域图例
  // ============================================================
  let lg-x = 0.5
  let lg-y = -0.05
  let lg-sz = 5pt

  rect((lg-x, lg-y - 0.15), (lg-x + 0.3, lg-y + 0.15),
    fill: C-cpu, stroke: (paint: rgb("#2563eb"), thickness: 0.3pt, dash: "dashed"), radius: 0.02,
  )
  content((lg-x + 0.7, lg-y), text(size: lg-sz, "cpu\_clk"))

  rect((lg-x + 2, lg-y - 0.15), (lg-x + 2.3, lg-y + 0.15),
    fill: C-sys, stroke: (paint: rgb("#16a34a"), thickness: 0.3pt, dash: "dashed"), radius: 0.02,
  )
  content((lg-x + 2.7, lg-y), text(size: lg-sz, "sys\_clk"))

  rect((lg-x + 4, lg-y - 0.15), (lg-x + 4.3, lg-y + 0.15),
    fill: C-ddr, stroke: (paint: rgb("#ea580c"), thickness: 0.3pt, dash: "dashed"), radius: 0.02,
  )
  content((lg-x + 4.8, lg-y), text(size: lg-sz, "ddr\_clk\_ref"))

  rect((lg-x + 6.5, lg-y - 0.15), (lg-x + 6.8, lg-y + 0.15),
    fill: C-cdc, stroke: (paint: rgb("#d97706"), thickness: 0.3pt, dash: "dashed"), radius: 0.02,
  )
  content((lg-x + 7, lg-y), text(size: lg-sz, "CDC"))

})
