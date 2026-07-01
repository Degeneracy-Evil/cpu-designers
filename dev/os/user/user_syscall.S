/*
 * Syscall wrappers for U-mode user programs.
 *
 * Convention:
 *   a7 = syscall number
 *   a0-a5 = arguments (per RISC-V calling convention)
 *   a0 = return value
 *
 * All wrappers are leaf functions: they only use a0-a2 (caller-saved) and
 * a7, so no callee-saved registers are touched and no stack frame needed.
 */

    .section .text.syscall, "ax", @progbits

/* ------------------------------------------------------------------ */
/*  long syscall(long num, long a0, long a1, long a2)                 */
/*                                                                    */
/*  Generic syscall entry. Arguments arrive in a0-a2 per the C ABI;   */
/*  the syscall number arrives in a0 (first arg) and must be moved    */
/*  to a7, while the real a0/a1/a2 are shifted from a1/a2/a3.         */
/* ------------------------------------------------------------------ */

    .globl  syscall
    .type   syscall, @function
syscall:
    mv      a7, a0          /* a7 = syscall number (1st arg) */
    mv      a0, a1          /* a0 = real arg 0 (2nd C arg)    */
    mv      a1, a2          /* a1 = real arg 1 (3rd C arg)    */
    mv      a2, a3          /* a2 = real arg 2 (4th C arg)    */
    ecall
    ret
    .size   syscall, . - syscall

/* ------------------------------------------------------------------ */
/*  ssize_t sys_write(int fd, const void *buf, size_t len)           */
/*    a7 = SYS_write (8)                                             */
/*    a0 = fd, a1 = buf, a2 = len  (already in place from C ABI)     */
/* ------------------------------------------------------------------ */

    .globl  sys_write
    .type   sys_write, @function
sys_write:
    li      a7, 8           /* SYS_write */
    ecall
    ret
    .size   sys_write, . - sys_write

/* ------------------------------------------------------------------ */
/*  ssize_t sys_read(int fd, void *buf, size_t len)                  */
/*    a7 = SYS_read (7)                                              */
/*    a0 = fd, a1 = buf, a2 = len  (already in place from C ABI)     */
/* ------------------------------------------------------------------ */

    .globl  sys_read
    .type   sys_read, @function
sys_read:
    li      a7, 7           /* SYS_read */
    ecall
    ret
    .size   sys_read, . - sys_read

/* ------------------------------------------------------------------ */
/*  void sys_exit(int pass, int total, int first_fail)  __noreturn__   */
/*    a7 = SYS_exit (2)                                              */
/*    a0/a1/a2 already in place from C ABI                           */
/* ------------------------------------------------------------------ */

    .globl  sys_exit
    .type   sys_exit, @function
sys_exit:
    li      a7, 2           /* SYS_exit */
    ecall
    /* Should not return; spin as fallback */
1:  j       1b
    .size   sys_exit, . - sys_exit

/* ------------------------------------------------------------------ */
/*  void sys_report(int pass, int total, int first_fail)              */
/*    a7 = SYS_report (9)                                            */
/*    a0/a1/a2 already in place from C ABI                           */
/*    Unlike sys_exit, this returns to caller after writing results.  */
/* ------------------------------------------------------------------ */

    .globl  sys_report
    .type   sys_report, @function
sys_report:
    li      a7, 9           /* SYS_report */
    ecall
    ret
    .size   sys_report, . - sys_report
