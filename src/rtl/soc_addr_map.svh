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
`define SOC_PLIC_SIZE            32'h0100_0000
`define SOC_CLINT_BASE           32'h0200_0000
`define SOC_CLINT_SIZE           32'h0001_0000
`define SOC_SYSSTATUS_BASE       32'h0400_0000
`define SOC_SYSSTATUS_SIZE       32'h0000_1000
`define SOC_APB_GPIO_BASE        32'h1000_0000
`define SOC_APB_GPIO_SIZE        32'h0000_1000
`define SOC_APB_UART_BASE        32'h1000_8000
`define SOC_APB_UART_SIZE        32'h0000_1000
`define SOC_APB_SPI_BASE         32'h1000_C000
`define SOC_APB_SPI_SIZE         32'h0000_1000

`endif // SOC_ADDR_MAP_SVH
