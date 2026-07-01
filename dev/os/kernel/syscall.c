/*
 * syscall.c — S-mode syscall implementations (Task 7)
 *
 * Syscall convention (RISC-V):
 *   a7 (x17) = syscall number
 *   a0 (x10) = arg0 / return value
 *   a1 (x11) = arg1
 *   a2 (x12) = arg2
 *
 * gpr[] indexing: gpr[N-1] = xN, so:
 *   a0 = x10 → gpr[9]
 *   a1 = x11 → gpr[10]
 *   a2 = x12 → gpr[11]
 *   a7 = x17 → gpr[16]
 *
 * VA conversion: user buffers are at VA 0x0+ (U page, S-mode cannot
 * access without SUM). The kernel identity-maps PA_USER_PROG (0x80008000)
 * without the U bit, so S-mode can access the same physical memory via
 * kernel_va = user_va + PA_USER_PROG.
 */

#include "syscall.h"
#include "trap.h"
#include "memlayout.h"
#include "uart.h"
#include "riscv.h"

/* Print an unsigned decimal value. */
static void uart_putdec(uint32_t val)
{
    char buf[11];
    int i = 10;
    buf[10] = '\0';

    if (val == 0) {
        uart_putc('0');
        return;
    }
    while (val > 0) {
        buf[--i] = (char)('0' + (val % 10U));
        val /= 10U;
    }
    uart_puts(&buf[i]);
}

void syscall_handle(trapframe_t *tf)
{
    uint32_t num = tf->gpr[16];   /* a7 = x17 → gpr[16] */

    switch (num) {

    case SYS_write: {
        uint32_t fd     = tf->gpr[9];   /* a0 = x10 → gpr[9]  */
        uint32_t buf_va = tf->gpr[10];  /* a1 = x11 → gpr[10] */
        uint32_t len    = tf->gpr[11];  /* a2 = x12 → gpr[11] */

        if (fd == 1) {  /* stdout */
            /* VA conversion: kernel_va = user_va + PA_USER_PROG */
            const char *kbuf = (const char *)(uintptr_t)(buf_va + PA_USER_PROG);
            uint32_t i;
            for (i = 0; i < len; i++) {
                uart_putc(kbuf[i]);
            }
            tf->gpr[9] = len;   /* return: bytes written */
        } else {
            tf->gpr[9] = (uint32_t)-1;  /* error: bad fd */
        }
        break;
    }

    case SYS_read: {
        uint32_t fd     = tf->gpr[9];
        uint32_t buf_va = tf->gpr[10];
        uint32_t len    = tf->gpr[11];

        if (fd == 0) {  /* stdin */
            char *kbuf = (char *)(uintptr_t)(buf_va + PA_USER_PROG);
            uint32_t count = 0;
            uint32_t i;
            for (i = 0; i < len; i++) {
                kbuf[i] = uart_getc();
                count++;
            }
            tf->gpr[9] = count;  /* return: bytes read */
        } else {
            tf->gpr[9] = (uint32_t)-1;
        }
        break;
    }

    case SYS_exit: {
        uint32_t pass_count    = tf->gpr[9];   /* a0 = x10 → gpr[9]  */
        uint32_t total_count   = tf->gpr[10];  /* a1 = x11 → gpr[10] */
        uint32_t first_fail_id = tf->gpr[11];  /* a2 = x12 → gpr[11] */

        /* Write self-check results to memory at PA_SELF_CHECK */
        volatile uint32_t *sc = (volatile uint32_t *)PA_SELF_CHECK;
        sc[0] = total_count;
        sc[1] = pass_count;
        sc[2] = first_fail_id;

        /* Print exit message */
        uart_puts("Calculator exited: ");
        uart_putdec(pass_count);
        uart_puts("/");
        uart_putdec(total_count);
        uart_puts(" tests passed\n");

        /* Halt — simulation ends here, TB checks memory/registers */
        while (1) {
            __asm__ volatile("wfi");
        }
        /* never reached */
    }

    case SYS_report: {
        uint32_t pass_count    = tf->gpr[9];   /* a0 = x10 → gpr[9]  */
        uint32_t total_count   = tf->gpr[10];  /* a1 = x11 → gpr[10] */
        uint32_t first_fail_id = tf->gpr[11];  /* a2 = x12 → gpr[11] */

        /* Write self-check results to memory at PA_SELF_CHECK */
        volatile uint32_t *sc = (volatile uint32_t *)PA_SELF_CHECK;
        sc[0] = total_count;
        sc[1] = pass_count;
        sc[2] = first_fail_id;

        /* Print report but do NOT halt — return to caller for interactive mode */
        break;
    }

    default:
        /* Unknown syscall */
        tf->gpr[9] = (uint32_t)-1;
        break;
    }
}
