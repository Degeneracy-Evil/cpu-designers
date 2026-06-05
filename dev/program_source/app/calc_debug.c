/*
 * Minimal UART test for SimpleCPU (RV32IMF).
 * Just outputs "Hello" and halts. Used to debug calculator UART issues.
 */

#include "uart.h"

int main(void)
{
    uart_init(UART_BAUD_115200);
    uart_puts("Hello\r\n");
    while (1)
        __asm__ volatile("wfi");
    return 0;
}
