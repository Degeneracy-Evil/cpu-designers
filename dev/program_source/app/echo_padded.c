/*
 * echo_padded.c — Echo loop with padding to move main to a different address.
 *
 * Identical to uart_echo_c_lib.c but with a large padding function
 * linked BEFORE main, pushing main past 0x80000300.
 *
 * If this works → corruption is address-specific (0x80000294 is hit
 *   regardless of what code is there, but only if CPU fetches it).
 * If this crashes at new main's addi s0,sp,X → corruption follows
 *   the execution path (not a fixed address).
 */
#include "sys.h"
#include "uart.h"

/* Padding: 200 NOPs = 800 bytes, pushes main well past 0x80000300 */
__attribute__((noinline)) static void __padding(void)
{
    __asm__ volatile(
        ".rept 200\n\t"
        "nop\n\t"
        ".endr\n\t"
    );
}

int main(void)
{
    (void)__padding;  /* prevent optimizer removal */
    uart_init(UART_BAUD_115200);
    for (;;) {
        char c = uart_getc();
        uart_putc(c);
    }
}
