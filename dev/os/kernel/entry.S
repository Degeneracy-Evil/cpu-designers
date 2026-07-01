/*
 * entry.S — M-mode entry point
 *
 * This is the very first code executed after reset. The linker script
 * (os.ld) places .text.start first at 0x80004000, so _start is the
 * hardware entry point.
 *
 * Responsibilities:
 *   1. Set up the stack (sp = _kernel_stack_top = 0x80004000)
 *   2. Call m_init() which builds page tables, enables paging, and
 *      performs mret to enter S-mode at s_mode_entry.
 *   3. If m_init ever returns (it should not), spin in a wfi loop.
 */

    .section .text.start
    .globl  _start
_start:
    la      sp, _kernel_stack_top      /* sp = 0x80004000 (stack grows down) */
    call    m_init                     /* never returns (ends with mret) */
    /* Fallback: should never reach here */
1:
    wfi
    j       1b
