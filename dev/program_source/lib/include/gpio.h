#ifndef GPIO_H
#define GPIO_H

#include "sys.h"

/* ------------------------------------------------------------------ */
/*  GPIO driver for APB GPIO peripheral                                */
/*  16-bit bidirectional IO, per-pin change interrupt                  */
/* ------------------------------------------------------------------ */

/* ---- Register map (byte offsets from GPIO_BASE) ----------------- */

#define GPIO_REG_CTRL       0x00U   /* Direction: 1=output, 0=input */
#define GPIO_REG_DATA       0x04U   /* Data register                */
#define GPIO_REG_IRQ_EN     0x08U   /* Per-pin interrupt enable     */
#define GPIO_REG_IRQ_STAT   0x0CU   /* Per-pin interrupt pending (W1C) */

/* ---- Register-struct view --------------------------------------- */

typedef struct {
    volatile uint32_t ctrl;       /* 0x00 */
    volatile uint32_t data;       /* 0x04 */
    volatile uint32_t irq_en;     /* 0x08 */
    volatile uint32_t irq_stat;   /* 0x0C */
} gpio_regs_t;

#define GPIO  ((volatile gpio_regs_t *)GPIO_BASE)

/* ---- Public API ------------------------------------------------- */

/* Initialise GPIO: all pins input, interrupts disabled. */
void gpio_init(void);

/* Set pin directions (1 = output, 0 = input, per-bit). */
void gpio_set_dir(uint16_t mask);

/* Write to output pins. */
void gpio_write(uint16_t val);

/* Read from input pins. */
uint16_t gpio_read(void);

/* Enable per-pin interrupts (1 = enable). */
void gpio_irq_enable(uint16_t mask);

/* Clear interrupt pending bits (W1C). */
void gpio_clear_irq(uint16_t mask);

#endif /* GPIO_H */
