/*
 * trap.S — S-mode trap handler (Task 7)
 *
 * stvec target (DIRECT mode). Saves all user registers + trap CSRs
 * into a trapframe_t on the kernel stack, calls trap_dispatch(tf),
 * then restores everything and sret's back to U-mode.
 *
 * trapframe_t layout (140 bytes, frame padded to 144 for 16-byte align):
 *   gpr[0]  = x1   (ra)    offset   0
 *   gpr[1]  = x2   (sp)    offset   4
 *   gpr[2]  = x3   (gp)    offset   8
 *   ...
 *   gpr[30] = x31  (t6)    offset 120
 *   sepc                    offset 124
 *   sstatus                 offset 128
 *   scause                  offset 132
 *   stval                   offset 136
 *
 * Register-saving strategy:
 *   On entry sp holds the USER sp (no hardware sp-switching on RISC-V).
 *   We save user sp to sscratch, load the kernel sp, then save all
 *   registers. x5 (t0) is used as a scratch to move sscratch→frame;
 *   x5's original value is saved first.
 */

    .section .text
    .globl trap_handler
    .type  trap_handler, @function

trap_handler:
    /* --- Save user sp to sscratch, switch to kernel sp --- */
    csrw  sscratch, sp              /* sscratch ← user sp */
    la    sp, _kernel_stack_top     /* sp ← kernel stack top */

    /* --- Allocate trap frame (144 bytes, 16-byte aligned) --- */
    addi  sp, sp, -144

    /* --- Save x1 (ra) --- */
    sw    x1, 0(sp)                 /* gpr[0] = x1 */

    /* --- Save x5 (t0) before using it as scratch --- */
    sw    x5, 16(sp)                /* gpr[4] = x5 */

    /* --- Save x2 (sp) from sscratch --- */
    csrr  x5, sscratch              /* x5 ← user sp */
    sw    x5, 4(sp)                 /* gpr[1] = x2 (user sp) */

    /* --- Save x3, x4 --- */
    sw    x3, 8(sp)                 /* gpr[2] = x3 */
    sw    x4, 12(sp)                /* gpr[3] = x4 */

    /* --- Save x6..x31 --- */
    sw    x6,  20(sp)               /* gpr[5]  = x6  */
    sw    x7,  24(sp)               /* gpr[6]  = x7  */
    sw    x8,  28(sp)               /* gpr[7]  = x8  */
    sw    x9,  32(sp)               /* gpr[8]  = x9  */
    sw    x10, 36(sp)               /* gpr[9]  = x10 (a0) */
    sw    x11, 40(sp)               /* gpr[10] = x11 (a1) */
    sw    x12, 44(sp)               /* gpr[11] = x12 (a2) */
    sw    x13, 48(sp)               /* gpr[12] = x13 (a3) */
    sw    x14, 52(sp)               /* gpr[13] = x14 (a4) */
    sw    x15, 56(sp)               /* gpr[14] = x15 (a5) */
    sw    x16, 60(sp)               /* gpr[15] = x16 (a6) */
    sw    x17, 64(sp)               /* gpr[16] = x17 (a7) */
    sw    x18, 68(sp)               /* gpr[17] = x18 */
    sw    x19, 72(sp)               /* gpr[18] = x19 */
    sw    x20, 76(sp)               /* gpr[19] = x20 */
    sw    x21, 80(sp)               /* gpr[20] = x21 */
    sw    x22, 84(sp)               /* gpr[21] = x22 */
    sw    x23, 88(sp)               /* gpr[22] = x23 */
    sw    x24, 92(sp)               /* gpr[23] = x24 */
    sw    x25, 96(sp)               /* gpr[24] = x25 */
    sw    x26, 100(sp)              /* gpr[25] = x26 */
    sw    x27, 104(sp)              /* gpr[26] = x27 */
    sw    x28, 108(sp)              /* gpr[27] = x28 */
    sw    x29, 112(sp)              /* gpr[28] = x29 */
    sw    x30, 116(sp)              /* gpr[29] = x30 */
    sw    x31, 120(sp)              /* gpr[30] = x31 */

    /* --- Save trap CSRs --- */
    csrr  t0, sepc
    sw    t0, 124(sp)
    csrr  t0, sstatus
    sw    t0, 128(sp)
    csrr  t0, scause
    sw    t0, 132(sp)
    csrr  t0, stval
    sw    t0, 136(sp)

    /* --- Call trap_dispatch(tf) — tf pointer in a0 --- */
    mv    a0, sp
    call  trap_dispatch

    /* --- Restore trap CSRs (sepc, sstatus) --- */
    lw    t0, 124(sp)
    csrw  sepc, t0
    lw    t0, 128(sp)
    csrw  sstatus, t0
    /* scause/stval are read-only — no restore needed */

    /* --- Restore x1, x3..x31 (NOT x2 yet) --- */
    lw    x1,  0(sp)
    lw    x3,  8(sp)
    lw    x4,  12(sp)
    lw    x5,  16(sp)
    lw    x6,  20(sp)
    lw    x7,  24(sp)
    lw    x8,  28(sp)
    lw    x9,  32(sp)
    lw    x10, 36(sp)
    lw    x11, 40(sp)
    lw    x12, 44(sp)
    lw    x13, 48(sp)
    lw    x14, 52(sp)
    lw    x15, 56(sp)
    lw    x16, 60(sp)
    lw    x17, 64(sp)
    lw    x18, 68(sp)
    lw    x19, 72(sp)
    lw    x20, 76(sp)
    lw    x21, 80(sp)
    lw    x22, 84(sp)
    lw    x23, 88(sp)
    lw    x24, 92(sp)
    lw    x25, 96(sp)
    lw    x26, 100(sp)
    lw    x27, 104(sp)
    lw    x28, 108(sp)
    lw    x29, 112(sp)
    lw    x30, 116(sp)
    lw    x31, 120(sp)

    /* --- Restore user sp (x2) last --- */
    lw    sp, 4(sp)                 /* sp ← user sp (frame abandoned) */

    /* --- Return to U-mode --- */
    sret

    .size trap_handler, . - trap_handler
