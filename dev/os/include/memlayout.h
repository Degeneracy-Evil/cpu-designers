#ifndef _OS_MEMLAYOUT_H
#define _OS_MEMLAYOUT_H

#include "types.h"

/* ------------------------------------------------------------------ */
/*  Physical memory layout (DDR3 @ 0x80000000)                        */
/*                                                                    */
/*  All physical addresses are in the 128 MB DDR3 window.             */
/*  Page tables and kernel data share the low 32 KB.                  */
/* ------------------------------------------------------------------ */

#define PA_KERNEL_BASE      0x80000000U
#define PA_USER_PROG        0x80008000U
#define PA_USER_STACK       0x80010000U

#define PA_L1_PT            0x80000000U
#define PA_L0_KERNEL_PT     0x80001000U
#define PA_L0_USER_PT       0x80002000U
#define PA_KERNEL_STACK     0x80003000U
#define PA_SELF_CHECK       0x80007000U

/* ------------------------------------------------------------------ */
/*  Virtual memory layout (Sv32, user space)                          */
/* ------------------------------------------------------------------ */

#define VA_USER_BASE        0x00000000U
#define VA_USER_STACK_TOP   0x00009000U

/* ------------------------------------------------------------------ */
/*  MMIO base addresses (match dev/program_source/lib/include/sys.h)  */
/* ------------------------------------------------------------------ */

#define UART_BASE           0x10008000U
#define DDR3_BASE           0x80000000U

#endif /* _OS_MEMLAYOUT_H */
