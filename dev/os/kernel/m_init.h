#ifndef _OS_KERNEL_M_INIT_H
#define _OS_KERNEL_M_INIT_H

/*
 * m_init.h — M-mode initialization interface
 *
 * m_init() is called from entry.S after setting up the stack. It builds the
 * Sv32 page tables, configures trap delegation, enables paging, and performs
 * mret to enter S-mode at s_mode_entry. It never returns.
 *
 * s_mode_entry is defined in s_main.c (Task 7) and is the S-mode kernel
 * entry point reached via mret.
 */

/* M-mode init: page tables + trap delegation + mret to S-mode. Never returns. */
void m_init(void);

/* S-mode entry point (defined in s_main.c, Task 7). */
extern void s_mode_entry(void);

#endif /* _OS_KERNEL_M_INIT_H */
