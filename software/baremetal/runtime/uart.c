#include "uart.h"

/* ------------------------------------------------------------------ */
/*  NS16550A UART driver implementation                                 */
/* ------------------------------------------------------------------ */

void uart_init(uint16_t baud_div)
{
    /* Disable all interrupts */
    UART->ier_dlm = 0;

    /* Set DLAB=1 to access divisor latch */
    UART->lcr = UART_LCR_DLAB;

    /* Set divisor: DLL = low byte, DLM = high byte */
    UART->thr_rbr_dll = (uint32_t)(baud_div & 0xFF);
    UART->ier_dlm    = (uint32_t)((baud_div >> 8) & 0xFF);

    /* 8N1, DLAB=0 (must clear DLAB to access THR/IER) */
    UART->lcr = UART_LCR_WL8;

    /* Enable FIFOs, trigger level 14, reset both FIFOs */
    UART->iir_fcr = UART_FCR_FIFO_EN | UART_FCR_RXSR | UART_FCR_TXSR | UART_FCR_TL_14;

    /* MCR: DTR + RTS, OUT2 (IRQ enable) */
    UART->mcr = UART_MCR_DTR | UART_MCR_RTS | UART_MCR_OUT2;

    /* Enable RX data available interrupt */
    UART->ier_dlm = UART_IER_RDA;
}

void uart_putc(char c)
{
    /* Wait until THR empty (THRE bit in LSR) */
    while (!(UART->lsr & UART_LSR_THRE))
        ;
    UART->thr_rbr_dll = (uint32_t)(uint8_t)c;
}

char uart_getc(void)
{
    /* Wait until data ready (DR bit in LSR) */
    while (!(UART->lsr & UART_LSR_DR))
        ;
    return (char)(uint8_t)UART->thr_rbr_dll;
}

int uart_rx_valid(void)
{
    return (UART->lsr & UART_LSR_DR) != 0;
}

int uart_tx_ready(void)
{
    return (UART->lsr & UART_LSR_THRE) != 0;
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
