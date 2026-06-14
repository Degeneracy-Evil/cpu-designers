#include "sys.h"
#include "uart.h"

#define UART_REG_CTRL     0x00U
#define UART_REG_BAUD     0x10U

static inline volatile uint32_t *uart_reg(uint32_t offset)
{
    return (volatile uint32_t *)(UART_BASE + offset);
}

static void uart_init_mmio(void)
{
    *uart_reg(UART_REG_BAUD) = 0;
    *uart_reg(UART_REG_CTRL) = 3;
}

int main(void)
{
    uart_init_mmio();
    uart_putc('O');
    uart_putc('K');
    uart_putc('\n');

    for (;;)
        __asm__ volatile("wfi");
}
