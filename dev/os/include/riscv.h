#ifndef _OS_RISCV_H
#define _OS_RISCV_H

#include "types.h"

/* ------------------------------------------------------------------ */
/*  RISC-V CSR addresses (match dev/rtl/core/cpu_csr.sv)              */
/* ------------------------------------------------------------------ */

#define CSR_SSTATUS     0x100
#define CSR_SIE         0x104
#define CSR_STVEC       0x105
#define CSR_SSCRATCH    0x140
#define CSR_SEPC        0x141
#define CSR_SCAUSE      0x142
#define CSR_STVAL       0x143
#define CSR_SIP         0x144
#define CSR_SATP        0x180

#define CSR_MSTATUS     0x300
#define CSR_MISA        0x301
#define CSR_MEDELEG     0x302
#define CSR_MIDELEG     0x303
#define CSR_MIE         0x304
#define CSR_MTVEC       0x305
#define CSR_MSCRATCH    0x340
#define CSR_MEPC        0x341
#define CSR_MCAUSE      0x342
#define CSR_MTVAL       0x343
#define CSR_MIP         0x344

/* ------------------------------------------------------------------ */
/*  mstatus / sstatus bit fields                                      */
/* ------------------------------------------------------------------ */

#define MSTATUS_MIE     (1U << 3)
#define MSTATUS_SIE     (1U << 1)
#define MSTATUS_MPIE    (1U << 7)
#define MSTATUS_SPIE    (1U << 5)
#define MSTATUS_MPP_M   (3U << 11)
#define MSTATUS_MPP_S   (1U << 11)
#define MSTATUS_MPP_U   (0U << 11)
#define MSTATUS_SPP_S   (1U << 8)
#define MSTATUS_SPP_U   (0U << 8)

#define SSTATUS_SIE     MSTATUS_SIE
#define SSTATUS_SPIE    MSTATUS_SPIE
#define SSTATUS_SPP     (1U << 8)
#define SSTATUS_SUM     (1U << 18)
#define SSTATUS_MXR     (1U << 19)

/* ------------------------------------------------------------------ */
/*  Privilege modes (match dev/rtl/core/MMU.sv PRIV_M = 2'b11)        */
/* ------------------------------------------------------------------ */

#define PRIV_U          0U
#define PRIV_S          1U
#define PRIV_M          3U

/* ------------------------------------------------------------------ */
/*  satp register layout (Sv32)                                       */
/*    [31]    MODE   (0=bare, 1=Sv32)                                 */
/*    [30:22] ASID                                          */
/*    [21:0]  PPN                                           */
/* ------------------------------------------------------------------ */

#define SATP_MODE_BARE  0U
#define SATP_MODE_SV32  1U
#define SATP_ASID_SHIFT 22
#define SATP_PPN_SHIFT  12
#define SATP_PPN_MASK   0x003FFFFFU
#define SATP_ASID_MASK  0x1FFU

/* Build satp value from mode, ASID, and physical page-table base. */
static inline uint32_t satp_make(uint32_t mode, uint32_t asid, uint32_t pa_pt_base)
{
    return ((mode & 1U) << 31) | ((asid & SATP_ASID_MASK) << SATP_ASID_SHIFT) |
           ((pa_pt_base >> SATP_PPN_SHIFT) & SATP_PPN_MASK);
}

static inline uint32_t satp_mode(uint32_t satp)  { return (satp >> 31) & 1U; }
static inline uint32_t satp_asid(uint32_t satp)  { return (satp >> SATP_ASID_SHIFT) & SATP_ASID_MASK; }
static inline uint32_t satp_ppn(uint32_t satp)   { return satp & SATP_PPN_MASK; }

/* ------------------------------------------------------------------ */
/*  Sv32 page table entry (PTE) bit definitions                       */
/*  MUST match dev/rtl/core/ptw.sv lines 129-137:                     */
/*    pte_v=pte[0] pte_r=pte[1] pte_w=pte[2] pte_x=pte[3]             */
/*    pte_u=pte[4] pte_g=pte[5] pte_a=pte[6] pte_d=pte[7]             */
/*    PPN = {pte[31:20], pte[19:10]}                                  */
/* ------------------------------------------------------------------ */

#define PTE_V           0x001U
#define PTE_R           0x002U
#define PTE_W           0x004U
#define PTE_X           0x008U
#define PTE_U           0x010U
#define PTE_G           0x020U
#define PTE_A           0x040U
#define PTE_D           0x080U

/* Permission shorthand combinations. */
#define PTE_RW          (PTE_R | PTE_W)
#define PTE_RX          (PTE_R | PTE_X)
#define PTE_RWX         (PTE_R | PTE_W | PTE_X)
#define PTE_RWXAD       (PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
#define PTE_RWXUAD      (PTE_R | PTE_W | PTE_X | PTE_U | PTE_A | PTE_D)
#define PTE_RWUAD       (PTE_R | PTE_W | PTE_U | PTE_A | PTE_D)
#define PTE_RXUAD       (PTE_R | PTE_X | PTE_U | PTE_A | PTE_D)

/* PTE field extraction. */
#define PTE_PPN_SHIFT   10
#define PTE_PPN_MASK    0xFFFFFC00U
#define PTE_FLAGS_MASK  0x3FFU

/* Build a leaf PTE from physical address and flag bits.
 *
 * Sv32 PTE format: [31:10] = PPN (22 bits), [9:0] = flags.
 * PPN = PA >> 12 (the physical page number).
 * The RTL (ptw.sv) reconstructs PA as {pte[31:20], pte[19:10], 12'b0}
 * which equals (pte >> 10) << 12 = (pte[31:10]) << 12.
 *
 * Therefore: PTE = (PA >> 12) << 10 | flags
 * This matches the working reference in page_table_utils.s:
 *   srli x17, x16, 12 ; slli x17, x17, 10 ; ori x17, x17, flags
 */
static inline uint32_t pte_make(uint32_t pa, uint32_t flags)
{
    return ((pa >> 12) << 10) | (flags & PTE_FLAGS_MASK);
}

static inline uint32_t pte_ppn(uint32_t pte)  { return (pte >> PTE_PPN_SHIFT); }
static inline uint32_t pte_pa(uint32_t pte)   { return (pte >> PTE_PPN_SHIFT) << 12; }
static inline uint32_t pte_flags(uint32_t pte){ return pte & PTE_FLAGS_MASK; }
static inline int      pte_valid(uint32_t pte){ return (pte & PTE_V) != 0; }
static inline int      pte_leaf(uint32_t pte) { return (pte & (PTE_R | PTE_X)) != 0; }
static inline int      pte_user(uint32_t pte) { return (pte & PTE_U) != 0; }

/* Sv32 VPN indexing. */
#define VPN1(va)        (((va) >> 22) & 0x3FFU)
#define VPN0(va)        (((va) >> 12) & 0x3FFU)
#define PAGE_SHIFT      12
#define PAGE_SIZE       (1U << PAGE_SHIFT)
#define PAGE_MASK       (PAGE_SIZE - 1U)

/* ------------------------------------------------------------------ */
/*  Inline assembly helpers                                           */
/* ------------------------------------------------------------------ */

/* csrr/csrw: read/write a CSR by symbolic name, e.g. csrr(sstatus, v). */
#define csrr(reg, val) \
    __asm__ volatile("csrr %0, " #reg : "=r"(val))

#define csrw(reg, val) \
    __asm__ volatile("csrw " #reg ", %0" :: "r"(val) : "memory")

static inline void sfence_vma(void)
{
    __asm__ volatile("sfence.vma zero, zero" ::: "memory");
}

static inline void sfence_vma_addr(uint32_t va)
{
    __asm__ volatile("sfence.vma %0, zero" :: "r"(va) : "memory");
}

static inline void fence_i(void)
{
    __asm__ volatile("fence.i" ::: "memory");
}

static inline void mem_fence(void)
{
    __asm__ volatile("fence" ::: "memory");
}

#endif /* _OS_RISCV_H */
