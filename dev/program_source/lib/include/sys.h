#ifndef SYS_H
#define SYS_H

/* ------------------------------------------------------------------ */
/*  System types and MMIO helpers for bare-metal RISC-V               */
/* ------------------------------------------------------------------ */

#include <stdint.h>

/* ---- MMIO access ------------------------------------------------ */

static inline void mmio_write32(volatile uint32_t *addr, uint32_t val)
{
    *addr = val;
}

static inline uint32_t mmio_read32(volatile const uint32_t *addr)
{
    return *addr;
}

static inline void mmio_write16(volatile uint16_t *addr, uint16_t val)
{
    *addr = val;
}

static inline uint16_t mmio_read16(volatile const uint16_t *addr)
{
    return *addr;
}

static inline void mmio_write8(volatile uint8_t *addr, uint8_t val)
{
    *addr = val;
}

static inline uint8_t mmio_read8(volatile const uint8_t *addr)
{
    return *addr;
}

/* ---- Memory barriers -------------------------------------------- */

static inline void mem_fence(void)
{
    __asm__ volatile("fence" ::: "memory");
}

static inline void mem_fence_i(void)
{
    __asm__ volatile("fence.i" ::: "memory");
}

/* ---- Halt ------------------------------------------------------- */

static inline void halt(void)
{
    while (1)
        __asm__ volatile("wfi");
}

/* ---- Address-space base constants ------------------------------- */

#define DDR3_BASE       0x80000000U
#define DDR3_SIZE       0x08000000U  /* 128 MB */
#define SRAM_BASE       DDR3_BASE    /* Legacy alias */
#define SRAM_SIZE       DDR3_SIZE    /* Legacy alias */
#define CLINT_BASE      0x02000000U
#define PLIC_BASE       0x0C000000U

/* CLINT register offsets — Standard SiFive CLINT layout */
#define CLINT_MSIP      0x0000U      /* msip: software interrupt pending (bit 0) */
#define CLINT_MTIMECMP  0x4000U      /* mtimecmp: 64-bit timer compare (lo at +0, hi at +4) */
#define CLINT_MTIME     0xBFF8U      /* mtime: 64-bit timer count (lo at +0, hi at +4) */

/* PLIC register offsets — Standard SiFive PLIC layout (dual-context) */
#define PLIC_PRIORITY   0x000000U    /* Priority[src]: base + src*4 */
#define PLIC_PENDING    0x001000U    /* Pending bits */
#define PLIC_ENABLE     0x002000U    /* Enable[ctx N]: base + N*0x80 */
#define PLIC_THRESHOLD  0x200000U    /* Threshold[ctx N]: base + N*0x1000 */
#define PLIC_CLAIM      0x200004U    /* Claim/Complete[ctx N]: base + N*0x1000 */
/* Context 0 = M-mode, Context 1 = S-mode */
#define PLIC_CTX_STRIDE_EN   0x80U   /* Enable context stride */
#define PLIC_CTX_STRIDE_TH   0x1000U /* Threshold/Claim context stride */

#define APB_BASE        0x10000000U
#define BOOTROM_BASE    0xFC000000U
#define SYS_STATUS_BASE 0x04000000U

/* System Status register (SYS_STATUS_BASE + 0x00) */
#define SYS_STATUS_INIT_CALIB  0x01U  /* [0] MIG init_calib_complete */
#define SYS_STATUS_MMCM_LOCKED 0x02U  /* [1] MIG MMCM locked */
#define SYS_STATUS_CLKWIZ_LOCK 0x04U  /* [2] Clocking Wizard locked */

/* APB peripheral offsets (PADDR[15:14] selects slave) */
#define GPIO_OFFSET     0x0000U      /* PSELx[0] */
#define TIMER_OFFSET   0x4000U      /* PSELx[1] */
#define UART_OFFSET    0x8000U      /* PSELx[2] */
#define SPI_OFFSET     0xC000U      /* PSELx[3] */

#define GPIO_BASE       (APB_BASE + GPIO_OFFSET)    /* 0x10000000 */
#define TIMER_BASE      (APB_BASE + TIMER_OFFSET)   /* 0x10004000 */
#define UART_BASE       (APB_BASE + UART_OFFSET)    /* 0x10008000 */
#define SPI_BASE        (APB_BASE + SPI_OFFSET)     /* 0x1000C000 */

/* ---- Linker-script symbols -------------------------------------- */

extern char __bss_start[];
extern char __bss_end[];
extern char _stack_top[];

#endif /* SYS_H */
