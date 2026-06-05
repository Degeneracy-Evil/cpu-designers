/*
 * UART library test — uses uart.c driver.
 * Outputs "Hello" repeatedly.
 */
#include "uart.h"

int main(void)
{
    uart_init(UART_BAUD_115200);
    for (;;)
        uart_puts("Hello\r\n");
    return 0;
}
