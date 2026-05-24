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

#define SRAM_BASE       0x80000000U
#define SRAM_SIZE       0x00008000U  /* 32 KB */
#define CLINT_BASE      0x02000000U
#define PLIC_BASE       0x0C000000U
#define APB_BASE        0x10000000U

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
