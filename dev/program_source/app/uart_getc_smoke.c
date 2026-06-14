#include "sys.h"
#include "uart.h"

#define UART_REG_CTRL     0x00U
#define UART_REG_STATUS   0x04U
#define UART_REG_TXDATA   0x08U
#define UART_REG_BAUD     0x10U

#define UART_STS_TX_BUSY  (1U << 0)

static inline volatile uint32_t *uart_reg(uint32_t offset)
{
    return (volatile uint32_t *)(UART_BASE + offset);
}

static void uart_init_mmio(void)
{
    *uart_reg(UART_REG_BAUD) = 0;
    *uart_reg(UART_REG_CTRL) = 3;
}

static void uart_putc_mmio(char c)
{
    while (*uart_reg(UART_REG_STATUS) & UART_STS_TX_BUSY)
        ;
    *uart_reg(UART_REG_TXDATA) = (uint32_t)(uint8_t)c;
}

static void uart_puts_mmio(const char *s)
{
    while (*s)
        uart_putc_mmio(*s++);
}

static void uart_puthex8(uint32_t value)
{
    static const char hex[] = "0123456789ABCDEF";
    uart_putc_mmio(hex[(value >> 4) & 0xF]);
    uart_putc_mmio(hex[value & 0xF]);
}

int main(void)
{
    uint32_t c;

    uart_init_mmio();
    uart_puts_mmio("uart_getc_smoke\n");

    c = (uint8_t)uart_getc();

    uart_puts_mmio("RX=");
    uart_puthex8(c);
    uart_putc_mmio(' ');
    uart_putc_mmio('[');
    uart_putc_mmio((char)c);
    uart_putc_mmio(']');
    uart_putc_mmio('\n');

    for (;;)
        __asm__ volatile("wfi");
}
