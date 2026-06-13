/*
 * Diagnostic variant: C uart_echo using direct MMIO, no uart.c call chain.
 * Used to distinguish "C runtime / function-call path" from "UART RX/TX path".
 */

#include "sys.h"

#define UART_REG_CTRL       0x00U
#define UART_REG_STATUS     0x04U
#define UART_REG_TXDATA     0x08U
#define UART_REG_RXDATA     0x0CU
#define UART_REG_BAUD       0x10U

#define UART_STS_TX_BUSY    (1U << 0)
#define UART_STS_RX_VALID   (1U << 1)

static inline volatile uint32_t *uart_reg(uint32_t offset)
{
    return (volatile uint32_t *)(UART_BASE + offset);
}

int main(void)
{
    *uart_reg(UART_REG_BAUD) = 0;
    *uart_reg(UART_REG_CTRL) = 3;

    for (;;) {
        while (!(*uart_reg(UART_REG_STATUS) & UART_STS_RX_VALID))
            ;
        uint32_t c = *uart_reg(UART_REG_RXDATA);
        while (*uart_reg(UART_REG_STATUS) & UART_STS_TX_BUSY)
            ;
        *uart_reg(UART_REG_TXDATA) = c;
    }
}
