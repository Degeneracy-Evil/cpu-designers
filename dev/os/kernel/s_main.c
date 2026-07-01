/*
 * s_main.c — S-mode kernel entry point (Task 7)
 *
 * Reached via mret from m_init(). Sets up the S-mode trap vector,
 * enables the FPU, prints a banner, then sret's to U-mode at the
 * user program entry (VA 0x0).
 */

#include "riscv.h"
#include "memlayout.h"
#include "uart.h"
#include "m_init.h"

/* trap_handler is defined in trap.S (S-mode trap vector target). */
extern void trap_handler(void);

/*
 * s_mode_entry — S-mode entry point.
 *
 * Called via mret from m_init(). At entry:
 *   - Privilege = S-mode
 *   - sp        = kernel stack (set by entry.S, preserved through m_init)
 *   - Paging    = enabled (satp set by m_init)
 *   - stvec     = unset (installed here)
 */
void s_mode_entry(void)
{
    uint32_t val;
    uint32_t trap_addr = (uint32_t)(uintptr_t)trap_handler;

    /* 1. Install S-mode trap vector (DIRECT mode: stvec[1:0] = 00) */
    csrw(stvec, trap_addr);

    /* 2. Enable FPU: set sstatus.FS = 01 (Initial)
     *    FS occupies bits [14:13]; setting bit 13 gives FS = 01.
     *    CRITICAL for calculator's fsqrt.s / fmv.x.w instructions. */
    csrr(sstatus, val);
    val |= (1U << 13);
    csrw(sstatus, val);

    /* 3. sscratch = 0 (trap.S uses it as a temp for saving user sp) */
    val = 0;
    csrw(sscratch, val);

    /* 4. Initialize UART to 230400 baud (8N1, FIFO enabled) */
    uart_init(UART_BAUD_230400);

    /* 5. Print boot banner via kernel UART (direct MMIO) */
    uart_puts("SimpleOS booted\n");

    /* 5. Prepare sret to U-mode:
     *    - SPP = 0  → sret returns to U-mode
     *    - sepc = VA_USER_BASE (0x00000000) → user _start
     *    - sp remains kernel stack; user_start.S sets its own sp */

    /* SPP = 0 (bit 8 cleared → U-mode) */
    csrr(sstatus, val);
    val &= ~(1U << 8);
    csrw(sstatus, val);

    /* sepc = user entry point */
    val = VA_USER_BASE;
    csrw(sepc, val);

    /* 6. sret → enter U-mode at VA 0x0 (user _start) */
    __asm__ volatile("sret");
    __builtin_unreachable();
}
