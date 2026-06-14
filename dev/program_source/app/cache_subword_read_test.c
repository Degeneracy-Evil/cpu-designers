#include "sys.h"

#define UART_REG_CTRL     0x00U
#define UART_REG_STATUS   0x04U
#define UART_REG_TXDATA   0x08U
#define UART_REG_BAUD     0x10U

#define UART_STS_TX_BUSY  (1U << 0)

static volatile uint32_t g_words[2];

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

static void uart_puthex32(uint32_t value)
{
    static const char hex[] = "0123456789ABCDEF";
    for (int shift = 28; shift >= 0; shift -= 4)
        uart_putc_mmio(hex[(value >> shift) & 0xF]);
}

static int report_u32(const char *tag, uint32_t actual, uint32_t expected)
{
    int ok = (actual == expected);
    uart_puts_mmio(tag);
    uart_puts_mmio(ok ? " OK  actual=" : " FAIL actual=");
    uart_puthex32(actual);
    uart_puts_mmio(" expected=");
    uart_puthex32(expected);
    uart_putc_mmio('\n');
    return ok;
}

int main(void)
{
    volatile uint32_t local[2];
    int ok = 1;

    uart_init_mmio();
    uart_puts_mmio("cache_subword_read_test\n");

    local[0] = 0x11223344U;
    ok &= report_u32("stack_lbu_0", ((volatile uint8_t *)local)[0], 0x44U);
    ok &= report_u32("stack_lbu_1", ((volatile uint8_t *)local)[1], 0x33U);
    ok &= report_u32("stack_lbu_2", ((volatile uint8_t *)local)[2], 0x22U);
    ok &= report_u32("stack_lbu_3", ((volatile uint8_t *)local)[3], 0x11U);
    ok &= report_u32("stack_lhu_0", ((volatile uint16_t *)local)[0], 0x3344U);
    ok &= report_u32("stack_lhu_2", ((volatile uint16_t *)local)[1], 0x1122U);

    g_words[0] = 0xA1B2C3D4U;
    ok &= report_u32("global_lbu_0", ((volatile uint8_t *)g_words)[0], 0xD4U);
    ok &= report_u32("global_lbu_1", ((volatile uint8_t *)g_words)[1], 0xC3U);
    ok &= report_u32("global_lbu_2", ((volatile uint8_t *)g_words)[2], 0xB2U);
    ok &= report_u32("global_lbu_3", ((volatile uint8_t *)g_words)[3], 0xA1U);
    ok &= report_u32("global_lhu_0", ((volatile uint16_t *)g_words)[0], 0xC3D4U);
    ok &= report_u32("global_lhu_2", ((volatile uint16_t *)g_words)[1], 0xA1B2U);

    uart_puts_mmio(ok ? "RESULT PASS\n" : "RESULT FAIL\n");

    for (;;)
        __asm__ volatile("wfi");
}
