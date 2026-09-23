`timescale 1ns / 1ps
`include "common/bus/axi.svh"
`include "core/interface/types.svh"
`include "common/address_map.svh"

// Fixed physical-memory attributes for the current SoC map.  An access is
// legal only when its complete byte range is contained in one implemented
// region and that region supports the requested operation.
module pma_checker(
    input      [31:0] paddr,
    input access_class_t access_type,
    input      [2:0]  access_size,
    input             is_atomic,
    input             is_ptw,
    output reg        allow
);
    reg [32:0] access_start;
    reg [32:0] access_end;
    reg [32:0] access_bytes;
    reg        valid_size;
    reg        in_ddr;
    reg        in_bootrom;
    reg        in_clint;
    reg        in_plic;
    reg        in_sysstatus;
    reg        in_gpio;
    reg        in_uart;
    reg        in_spi;

    function automatic range_inside(
        input [32:0] start_addr,
        input [32:0] end_addr,
        input [31:0] region_base,
        input [31:0] region_size
    );
        reg [32:0] region_start;
        reg [32:0] region_end;
        begin
            region_start = {1'b0, region_base};
            region_end = region_start + {1'b0, region_size};
            range_inside = (start_addr >= region_start) &&
                           (end_addr <= region_end);
        end
    endfunction

    always_comb begin
        valid_size = (access_size <= `AXI_SIZE_WORD);
        access_bytes = 33'd1 << access_size;
        access_start = {1'b0, paddr};
        access_end = access_start + access_bytes;

        in_ddr = valid_size && range_inside(access_start, access_end,
                                            `SOC_DDR_BASE, `SOC_DDR_SIZE);
        in_bootrom = valid_size && range_inside(access_start, access_end,
                                                `SOC_BOOTROM_BASE, `SOC_BOOTROM_SIZE);
        in_clint = valid_size && range_inside(access_start, access_end,
                                              `SOC_CLINT_BASE, `SOC_CLINT_SIZE);
        in_plic = valid_size && range_inside(access_start, access_end,
                                             `SOC_PLIC_BASE, `SOC_PLIC_SIZE);
        in_sysstatus = valid_size && range_inside(access_start, access_end,
                                                  `SOC_SYSSTATUS_BASE, `SOC_SYSSTATUS_SIZE);
        in_gpio = valid_size && range_inside(access_start, access_end,
                                             `SOC_APB_GPIO_BASE, `SOC_APB_GPIO_SIZE);
        in_uart = valid_size && range_inside(access_start, access_end,
                                             `SOC_APB_UART_BASE, `SOC_APB_UART_SIZE);
        in_spi = valid_size && range_inside(access_start, access_end,
                                            `SOC_APB_SPI_BASE, `SOC_APB_SPI_SIZE);

        allow = 1'b0;
        if (is_ptw) begin
            // Page tables are supported only in ordinary DDR memory.
            allow = in_ddr && (access_size == `AXI_SIZE_WORD) &&
                    (access_type != ACCESS_FETCH);
        end else if (is_atomic) begin
            allow = in_ddr && (access_size == `AXI_SIZE_WORD) &&
                    (access_type != ACCESS_FETCH);
        end else begin
            case (access_type)
                ACCESS_FETCH: allow = in_ddr || in_bootrom;
                ACCESS_LOAD:  allow = in_ddr || in_bootrom || in_clint ||
                                      in_plic || in_sysstatus || in_gpio ||
                                      in_uart || in_spi;
                ACCESS_STORE: allow = in_ddr || in_clint || in_plic ||
                                      in_gpio || in_uart || in_spi;
                default:      allow = 1'b0;
            endcase
        end
    end
endmodule
