/*
 * Bare-metal startup code for SimpleCPU.
 *
 * 1. Set stack pointer to top of SRAM (32 KB).
 * 2. Zero the .bss section.
 * 3. Call main().
 * 4. On return, loop with WFI.
 */

    .section .text.start, "ax", @progbits
    .globl _start
    .type  _start, @function

_start:
    /* ---- Set stack pointer ---- */
    lui     sp, %hi(_stack_top)
    addi    sp, sp, %lo(_stack_top)

    /* ---- Install default trap handler for C apps ---- */
    la      t0, .Ltrap
    csrw    mtvec, t0

    /* ---- Zero .bss section ---- */
    la      t0, __bss_start
    la      t1, __bss_end
    bge     t0, t1, .Lbss_done
.Lbss_loop:
    sw      zero, 0(t0)
    addi    t0, t0, 4
    blt     t0, t1, .Lbss_loop
.Lbss_done:

    /* ---- Establish an instruction-fetch coherence boundary ---- */
    /* Data stores are write-through. fence.i only needs to invalidate stale
       instruction lines before main executes newly installed code. */
    fence.i

    /* ---- Call main ---- */
    call    main

    /* ---- Halt on return ---- */
.Lhalt:
    wfi
    j       .Lhalt

.Ltrap:
    csrr    x5, mcause
    csrr    x6, mepc
    csrr    x7, mtval
.Ltrap_halt:
    wfi
    j       .Ltrap_halt

    .size _start, . - _start
