/*
 * U-mode startup code for SimpleOS user programs.
 *
 * 1. Set stack pointer to VA_USER_STACK_TOP (0x00009000).
 * 2. Zero the .bss section.
 * 3. Call main().
 * 4. On return, ecall SYS_exit with main's return value.
 *
 * Unlike bare-metal start.S, this does NOT:
 *   - write mtvec/stvec  (OS owns the trap vector)
 *   - execute fence.i    (OS handles icache coherence)
 *   - access M-mode CSRs (illegal in U-mode)
 */

    .section .text.start, "ax", @progbits
    .globl  _start
    .type   _start, @function

_start:
    /* ---- Set stack pointer to user stack top ---- */
    li      sp, 0x9000

    /* ---- Zero .bss section ---- */
    la      t0, __bss_start
    la      t1, __bss_end
    bge     t0, t1, .Lbss_done
.Lbss_loop:
    sw      zero, 0(t0)
    addi    t0, t0, 4
    blt     t0, t1, .Lbss_loop
.Lbss_done:

    /* ---- Call main ---- */
    call    main

    /* ---- On return: ecall SYS_exit(a0) ---- */
    /* a0 already holds main's return value */
    li      a7, 2           /* SYS_exit */
    ecall

    /* Should not return; spin as fallback */
.Lspin:
    j       .Lspin

    .size _start, . - _start
