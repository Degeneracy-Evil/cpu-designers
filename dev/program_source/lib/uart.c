#include "uart.h"

/* ------------------------------------------------------------------ */
/*  UART driver implementation                                         */
/* ------------------------------------------------------------------ */

void uart_init(uint16_t baud_div)
{
    UART->baud = (uint32_t)baud_div;
    UART->ctrl = UART_CTRL_TX_EN | UART_CTRL_RX_EN;
}

void uart_putc(char c)
{
    while (UART->status & UART_STS_TX_BUSY)
        ;
    UART->txdata = (uint32_t)(uint8_t)c;
}

char uart_getc(void)
{
    while (!(UART->status & UART_STS_RX_VALID))
        ;
    return (char)(uint8_t)UART->rxdata;
}

int uart_rx_valid(void)
{
    return (UART->status & UART_STS_RX_VALID) != 0;
}

int uart_tx_busy(void)
{
    return (UART->status & UART_STS_TX_BUSY) != 0;
}

int uart_tx_fifo_full(void)
{
    return (UART->status & UART_STS_TX_FIFO_FULL) != 0;
}

void uart_write(const char *buf, int len)
{
    for (int i = 0; i < len; i++)
        uart_putc(buf[i]);
}

void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

void uart_clear_irq(uint32_t mask)
{
    UART->irq_stat = mask;
}
