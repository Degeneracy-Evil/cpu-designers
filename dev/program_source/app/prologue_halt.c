/*
 * prologue_halt.c — Minimal test for BUG-96 residual RTL bug.
 *
 * Only does main prologue (stack frame setup) then halts.
 * No UART calls at all. Linked with start.S + uart.c to keep
 * main at the same address (0x80000288) as uart_echo_c_lib.
 *
 * If this crashes at 0x80000294 → bug is in prologue/stack ops
 *   or DDR3 was corrupted BEFORE main started.
 * If this works → bug requires UART calls to trigger.
 */
#include "sys.h"
#include "uart.h"  /* linked but unused — keeps main at same address */

int main(void)
{
    volatile int x = 0;  /* force frame pointer with -O0 */
    (void)x;
    halt();
}
