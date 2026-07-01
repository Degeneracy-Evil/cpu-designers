/*
 * m_init.c — M-mode initialization
 *
 * Called from entry.S after stack setup. Builds three Sv32 page tables,
 * configures trap delegation, enables paging, and performs mret to enter
 * S-mode at s_mode_entry. Never returns.
 *
 * Page table layout (physical addresses from memlayout.h):
 *   0x80000000  L1 page table          (1024 entries, 4 KB)
 *   0x80001000  L0 kernel page table   (1024 entries, 4 KB)
 *   0x80002000  L0 user page table     (1024 entries, 4 KB)
 *
 * Virtual address mapping:
 *   VA 0x00000000-0x00007FFF → PA 0x80008000-0x8000FFFF  (user binary, 8 pages)
 *   VA 0x00008000-0x00008FFF → PA 0x80010000-0x80010FFF  (user stack, 1 page)
 *   VA 0x10000000-0x103FFFFF → PA same (megapage, UART device, kernel-only)
 *   VA 0x80000000-0x80010FFF → PA same (identity map, kernel + user regions)
 *
 * PTE bit patterns copied from dev/program_source/framework/page_table_utils.s
 * (WORKING reference). A/D bits are pre-set on all leaf PTEs because the
 * hardware does NOT auto-set them (ptw.sv checks A/D, traps as page fault
 * if either is 0 on a valid leaf PTE).
 *
 * CSR write sequence copied from dev/program_source/test/privilege/priv_transition.s
 * (WORKING M→S transition). medeleg/mideleg/mstatus/mepc/satp/sfence.vma/fence.i/mret.
 */

#include "riscv.h"
#include "memlayout.h"
#include "m_init.h"

/* ------------------------------------------------------------------ */
/*  Page table base pointers (physical, accessed via identity map     */
/*  before paging is enabled — at this point we're still in bare mode) */
/* ------------------------------------------------------------------ */

#define L1_PT_BASE      ((volatile uint32_t *)PA_L1_PT)
#define L0_KERN_PT_BASE ((volatile uint32_t *)PA_L0_KERNEL_PT)
#define L0_USER_PT_BASE ((volatile uint32_t *)PA_L0_USER_PT)

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

/* Freestanding memset-to-zero (no libc available). */
static void mem_zero(void *dst, size_t n)
{
    volatile uint8_t *p = (volatile uint8_t *)dst;
    while (n--) {
        *p++ = 0;
    }
}

/*
 * Fill L0 entries for an identity-mapped range [pa_start, pa_end).
 * VA == PA for each page. All pages must fall within the same L0 table
 * (i.e., share the same VPN[1]).
 */
static void pt_identity_fill(volatile uint32_t *l0_base,
                             uint32_t pa_start, uint32_t pa_end,
                             uint32_t flags)
{
    uint32_t pa;
    for (pa = pa_start; pa < pa_end; pa += PAGE_SIZE) {
        l0_base[VPN0(pa)] = pte_make(pa, flags);
    }
}

/*
 * Fill L0 entries mapping VA range [va_start, va_end) to PA range
 * starting at pa_start. All VAs must share the same VPN[1].
 */
static void pt_map_fill(volatile uint32_t *l0_base,
                        uint32_t va_start, uint32_t va_end,
                        uint32_t pa_start, uint32_t flags)
{
    uint32_t va, pa;
    for (va = va_start, pa = pa_start; va < va_end; va += PAGE_SIZE, pa += PAGE_SIZE) {
        l0_base[VPN0(va)] = pte_make(pa, flags);
    }
}

/* ------------------------------------------------------------------ */
/*  m_init — M-mode initialization (never returns)                     */
/* ------------------------------------------------------------------ */

void m_init(void)
{
    uint32_t val;
    uint32_t entry_addr;

    /* ════════════════════════════════════════════════════════════════
     *  Step 1: Zero page table memory (3 × 4 KB)
     * ════════════════════════════════════════════════════════════════ */
    mem_zero((void *)PA_L1_PT,        PAGE_SIZE);
    mem_zero((void *)PA_L0_KERNEL_PT, PAGE_SIZE);
    mem_zero((void *)PA_L0_USER_PT,   PAGE_SIZE);

    /* ════════════════════════════════════════════════════════════════
     *  Step 2: Build L1 page table (1024 entries at 0x80000000)
     * ════════════════════════════════════════════════════════════════ */

    /* L1[0] → L0 user PT: maps VA 0x00000000-0x003FFFFF */
    L1_PT_BASE[VPN1(0x00000000)] = pte_make(PA_L0_USER_PT, PTE_V);

    /* L1[512] → L0 kernel PT: maps VA 0x80000000-0x803FFFFF
     * (VPN1(0x80000000) = 0x200 = 512, matching page_table_utils.s) */
    L1_PT_BASE[VPN1(0x80000000)] = pte_make(PA_L0_KERNEL_PT, PTE_V);

    /* L1[64] → megapage for UART: VA 0x10000000-0x103FFFFF → PA same
     * Device mapping: kernel-only (no U, no X), RW + A/D.
     * (VPN1(0x10000000) = 0x40 = 64) */
    L1_PT_BASE[VPN1(0x10000000)] = pte_make(0x10000000U,
                                            PTE_V | PTE_R | PTE_W | PTE_A | PTE_D);

    /* ════════════════════════════════════════════════════════════════
     *  Step 3: Build L0 kernel page table (identity map, 1024 entries
     *          at 0x80001000)
     * ════════════════════════════════════════════════════════════════ */

    /* 0x80000000-0x80002FFF: page tables (3 pages) — RW AD, no X, no U */
    pt_identity_fill(L0_KERN_PT_BASE, 0x80000000U, 0x80003000U,
                     PTE_V | PTE_R | PTE_W | PTE_A | PTE_D);

    /* 0x80003000-0x80003FFF: kernel stack (1 page) — RW AD, no X, no U */
    pt_identity_fill(L0_KERN_PT_BASE, 0x80003000U, 0x80004000U,
                     PTE_V | PTE_R | PTE_W | PTE_A | PTE_D);

    /* 0x80004000-0x80006FFF: kernel code (3 pages) — RWX AD, no U */
    pt_identity_fill(L0_KERN_PT_BASE, 0x80004000U, 0x80007000U,
                     PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D);

    /* 0x80007000-0x80007FFF: self-check area (1 page) — RW AD, no X, no U */
    pt_identity_fill(L0_KERN_PT_BASE, 0x80007000U, 0x80008000U,
                     PTE_V | PTE_R | PTE_W | PTE_A | PTE_D);

    /* 0x80008000-0x8000FFFF: user binary (8 pages) — RWX AD, no U.
     * Kernel accesses user memory via identity map (VA==PA) for syscall
     * VA conversion. S-mode cannot access U-tagged pages without SUM=1,
     * so the kernel PT must NOT set PTE_U. The user PT maps the same
     * physical pages WITH PTE_U for user-mode access. */
    pt_identity_fill(L0_KERN_PT_BASE, 0x80008000U, 0x80010000U,
                     PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D);

    /* 0x80010000-0x80010FFF: user stack (1 page) — RW AD, no U (same reason). */
    pt_identity_fill(L0_KERN_PT_BASE, 0x80010000U, 0x80011000U,
                     PTE_V | PTE_R | PTE_W | PTE_A | PTE_D);

    /* ════════════════════════════════════════════════════════════════
     *  Step 4: Build L0 user page table (1024 entries at 0x80002000)
     * ════════════════════════════════════════════════════════════════ */

    /* VA 0x00000000-0x00007FFF → PA 0x80008000-0x8000FFFF
     * User binary (8 pages) — RWXU AD */
    pt_map_fill(L0_USER_PT_BASE, 0x00000000U, 0x00008000U, 0x80008000U,
                PTE_V | PTE_R | PTE_W | PTE_X | PTE_U | PTE_A | PTE_D);

    /* VA 0x00008000-0x00008FFF → PA 0x80010000-0x80010FFF
     * User stack (1 page) — RWU AD, no X */
    pt_map_fill(L0_USER_PT_BASE, 0x00008000U, 0x00009000U, 0x80010000U,
                PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D);

    /* ════════════════════════════════════════════════════════════════
     *  Step 5: Configure trap delegation
     * ════════════════════════════════════════════════════════════════ */

    /* medeleg: delegate U-ecall(8) + instr PF(12) + load PF(13) + store PF(15)
     * RTL mask is 0xB1FF — bit 9 (S-ecall) is hardwired 0, bit 8 (U-ecall)
     * is writable. Our value 0xB100 fits within the mask. */
    val = (1U << 8) | (1U << 12) | (1U << 13) | (1U << 15);
    csrw(medeleg, val);

    /* mideleg: delegate SEI(9) / STI(5) / SSI(1) to S-mode.
     * RTL mask is 0x0888 (only bits 3/7/11 writable); bits 1/5/9 are
     * hardwired 0 (S→U delegation requires deprecated N extension).
     * The write is harmless — hardware masks it to 0. */
    val = (1U << 9) | (1U << 5) | (1U << 1);
    csrw(mideleg, val);

    /* ════════════════════════════════════════════════════════════════
     *  Step 6: Set mstatus — MPP=S (for mret), FS=01 (enable FPU)
     * ════════════════════════════════════════════════════════════════ */
    csrr(mstatus, val);
    val = (val & ~MSTATUS_MPP_M) | MSTATUS_MPP_S | (1U << 13);  /* FS=01 */
    csrw(mstatus, val);

    /* ════════════════════════════════════════════════════════════════
     *  Step 7: Set mepc = s_mode_entry (S-mode entry point)
     * ════════════════════════════════════════════════════════════════ */
    entry_addr = (uint32_t)(uintptr_t)s_mode_entry;
    csrw(mepc, entry_addr);

    /* ════════════════════════════════════════════════════════════════
     *  Step 8: Set satp — enable Sv32 mode, ASID=0, L1 PT base
     * ════════════════════════════════════════════════════════════════ */
    val = satp_make(SATP_MODE_SV32, 0, PA_L1_PT);
    csrw(satp, val);

    /* ════════════════════════════════════════════════════════════════
     *  Step 9: sfence.vma — flush TLB after satp write (CRITICAL!)
     *
     *  Per RISC-V spec and MMU.sv: writing satp does NOT flush TLB.
     *  Without sfence.vma, stale TLB entries could be used.
     * ════════════════════════════════════════════════════════════════ */
    sfence_vma();

    /* ════════════════════════════════════════════════════════════════
     *  Step 10: fence.i — ensure instruction cache sees page table writes
     *
     *  dcache is write-back; page table writes may still be in dcache.
     *  PTW reads directly from SRAM (bypassing dcache), so fence.i
     *  flushes dcache dirty lines to SRAM before the first PTW walk
     *  triggered by mret's instruction fetch.
     * ════════════════════════════════════════════════════════════════ */
    fence_i();

    /* ════════════════════════════════════════════════════════════════
     *  Step 11: mret → enter S-mode at s_mode_entry
     * ════════════════════════════════════════════════════════════════ */
    __asm__ volatile("mret" ::: "memory");

    /* Should never reach here — mret does not return */
    for (;;) {
        __asm__ volatile("wfi");
    }
}
