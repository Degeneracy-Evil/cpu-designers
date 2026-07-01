/*
 * trap.c — S-mode trap dispatch (Task 7)
 *
 * Reads scause from the trap frame and dispatches:
 *   - ECALL_U (8)  → syscall handler (sepc += 4)
 *   - Page faults  → print diagnostics, halt
 *   - ebreak (3)   → skip instruction (sepc += 4)
 *   - other        → print scause, halt
 */

#include "trap.h"
#include "syscall.h"
#include "uart.h"
#include "riscv.h"

/* Forward declaration — defined in syscall.c */
void syscall_handle(trapframe_t *tf);

/* Print a 32-bit hex value (8 digits, uppercase). */
static void uart_puthex(uint32_t val)
{
    static const char hex[] = "0123456789ABCDEF";
    char buf[9];
    int i;
    for (i = 7; i >= 0; i--) {
        buf[i] = hex[val & 0xFU];
        val >>= 4;
    }
    buf[8] = '\0';
    uart_puts(buf);
}

/* Halt the CPU: infinite wfi loop. */
static void halt(void)
{
    while (1) {
        __asm__ volatile("wfi");
    }
}

void trap_dispatch(trapframe_t *tf)
{
    uint32_t cause = tf->scause;

    if (cause == CAUSE_ECALL_U) {
        /* ecall from U-mode: advance sepc by 4 (ecall is 4 bytes,
         * no C extension in -march=rv32imaf_zicsr_zifencei) */
        tf->sepc += 4;
        syscall_handle(tf);
        return;
    }

    if (cause == CAUSE_PAGE_FAULT_I ||
        cause == CAUSE_PAGE_FAULT_L ||
        cause == CAUSE_PAGE_FAULT_S) {
        uart_puts("Page fault! scause=0x");
        uart_puthex(cause);
        uart_puts(" stval=0x");
        uart_puthex(tf->stval);
        uart_puts("\n");
        halt();
        return;
    }

    if (cause == 3) {
        /* ebreak: skip the 4-byte instruction */
        tf->sepc += 4;
        return;
    }

    /* Unexpected trap */
    uart_puts("Unexpected trap: scause=0x");
    uart_puthex(cause);
    uart_puts(" stval=0x");
    uart_puthex(tf->stval);
    uart_puts("\n");
    halt();
}
