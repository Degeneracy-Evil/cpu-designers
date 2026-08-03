#include "gpio.h"

/* ------------------------------------------------------------------ */
/*  GPIO driver implementation                                         */
/* ------------------------------------------------------------------ */

void gpio_init(void)
{
    GPIO->ctrl     = 0x00000000U;   /* all pins input */
    GPIO->irq_en  = 0x00000000U;   /* interrupts disabled */
    GPIO->irq_stat = 0x0000FFFFU;  /* clear all pending */
}

void gpio_set_dir(uint16_t mask)
{
    GPIO->ctrl = (uint32_t)mask;
}

void gpio_write(uint16_t val)
{
    GPIO->data = (uint32_t)val;
}

uint16_t gpio_read(void)
{
    return (uint16_t)GPIO->data;
}

void gpio_irq_enable(uint16_t mask)
{
    GPIO->irq_en = (uint32_t)mask;
}

void gpio_clear_irq(uint16_t mask)
{
    GPIO->irq_stat = (uint32_t)mask;
}
