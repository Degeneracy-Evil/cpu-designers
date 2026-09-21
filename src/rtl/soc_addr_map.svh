// =============================================================================
// SoC physical address map
// =============================================================================

`ifndef SOC_ADDR_MAP_SVH
`define SOC_ADDR_MAP_SVH

`define SOC_DDR_BASE             32'h8000_0000
`define SOC_DDR_SIZE             32'h0800_0000
`define SOC_BOOTROM_BASE         32'hFC00_0000
`define SOC_BOOTROM_SIZE         32'h0000_8000
`define SOC_PLIC_BASE            32'h0C00_0000
`define SOC_CLINT_BASE           32'h0200_0000
`define SOC_SYSSTATUS_BASE       32'h0400_0000
`define SOC_APB_BASE             32'h1000_0000
`define SOC_APB_GPIO_BASE        32'h1000_0000
`define SOC_APB_RESERVED1_BASE   32'h1000_4000
`define SOC_APB_UART_BASE        32'h1000_8000
`define SOC_APB_SPI_BASE         32'h1000_C000

// Legacy interconnect windows are recorded separately from implemented ranges.
`define SOC_BOOTROM_LEGACY_MASK  32'hFF00_0000
`define SOC_BOOTROM_LEGACY_VALUE 32'hFC00_0000

`endif // SOC_ADDR_MAP_SVH
