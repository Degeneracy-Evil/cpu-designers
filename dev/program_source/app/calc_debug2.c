/*
 * Bare-minimum UART test — direct register writes, no C library.
 * Outputs "A" repeatedly, like uart_hello.s but in C.
 */

#define UART_BASE 0x10008000U

static inline void mmio_write32(volatile unsigned int *addr, unsigned int val)
{
    *addr = val;
}

static inline unsigned int mmio_read32(volatile const unsigned int *addr)
{
    return *addr;
}

int main(void)
{
    volatile unsigned int *uart_ctrl   = (volatile unsigned int *)(UART_BASE + 0x00);
    volatile unsigned int *uart_status = (volatile unsigned int *)(UART_BASE + 0x04);
    volatile unsigned int *uart_txdata = (volatile unsigned int *)(UART_BASE + 0x08);

    /* Enable TX */
    mmio_write32(uart_ctrl, 1);

    /* Send 'A' repeatedly */
    for (;;) {
        while (mmio_read32(uart_status) & 1)
            ;
        mmio_write32(uart_txdata, 'A');
    }

    return 0;
}
