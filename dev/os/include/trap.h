#ifndef _OS_TRAP_H
#define _OS_TRAP_H

#include "types.h"

/* ------------------------------------------------------------------ */
/*  Trap frame saved on kernel stack by the trap entry stub.          */
/*                                                                    */
/*  gpr[0..30] hold x1..x31 (x0 is hardwired zero, not saved).        */
/*  sepc/sstatus/scause/stval are the S-mode trap context CSRs.       */
/* ------------------------------------------------------------------ */

typedef struct trapframe {
    uint32_t gpr[31];       /* x1 .. x31 */
    uint32_t sepc;
    uint32_t sstatus;
    uint32_t scause;
    uint32_t stval;
} trapframe_t;

/* ------------------------------------------------------------------ */
/*  Trap cause codes (scause values, RISC-V Privileged Spec 1.11)     */
/* ------------------------------------------------------------------ */

#define CAUSE_ECALL_U           8U
#define CAUSE_ECALL_S           9U
#define CAUSE_PAGE_FAULT_I      12U
#define CAUSE_PAGE_FAULT_L      13U
#define CAUSE_PAGE_FAULT_S      15U

/* Convenience: true if scause encodes an interrupt (MSB set). */
#define SCAUSE_IS_INTERRUPT(c)  (((c) & 0x80000000U) != 0)

#endif /* _OS_TRAP_H */
