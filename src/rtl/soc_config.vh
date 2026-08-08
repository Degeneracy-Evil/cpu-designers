// =============================================================================
// SoC Configuration Macros — 参照 chiplab soc_config.vh
// =============================================================================
// 这些宏控制仿真/上板行为，通过 `include "soc_config.vh" 使用
// 在 Vivado 中也可通过 verilog defines 覆盖

// PLL 控制用于仿真
// 0 = 仿真直产时钟（最快，推荐日常开发）
// 1 = 仿真用 PLL IP（慢但更接近真实时钟关系）
`ifndef SIMU_USE_PLL
`define SIMU_USE_PLL 0
`endif

// DDR 控制用于仿真
// 0 = 使用 axi_wrap_ram（SRAM 行为模型，极快）
// 1 = 使用 axi_wrap_ddr（真实 DDR3 + MIG，验证 DDR3 通路）
`ifndef SIMU_USE_DDR
`define SIMU_USE_DDR 0
`endif
