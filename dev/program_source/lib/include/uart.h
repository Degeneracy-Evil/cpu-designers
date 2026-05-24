#ifndef UART_H
#define UART_H

#include "sys.h"

/* ------------------------------------------------------------------ */
/*  UART driver for APB UART peripheral                                */
/*  TX/RX FIFO (16 bytes), configurable baud rate, interrupt support  */
/* ------------------------------------------------------------------ */

/* ---- Register map (byte offsets from UART_BASE) ----------------- */

#define UART_REG_CTRL       0x00U
#define UART_REG_STATUS     0x04U
#define UART_REG_TXDATA    0x08U
#define UART_REG_RXDATA    0x0CU
#define UART_REG_BAUD      0x10U
#define UART_REG_IRQ_STAT  0x14U

/* ---- CTRL register bits ----------------------------------------- */

#define UART_CTRL_TX_EN     (1U << 0)   /* TX enable              */
#define UART_CTRL_RX_EN     (1U << 1)   /* RX enable              */
#define UART_CTRL_TX_IE     (1U << 2)   /* TX-done interrupt en   */
#define UART_CTRL_RX_IE     (1U << 3)   /* RX-valid interrupt en  */

/* ---- STATUS register bits --------------------------------------- */

#define UART_STS_TX_BUSY       (1U << 0)   /* TX engine busy or FIFO non-empty */
#define UART_STS_RX_VALID      (1U << 1)   /* RX FIFO has data (!empty)        */
#define UART_STS_TX_FIFO_FULL  (1U << 2)   /* TX FIFO full                     */
#define UART_STS_RX_FIFO_EMPTY (1U << 3)   /* RX FIFO empty                    */
#define UART_STS_TX_FIFO_EMPTY (1U << 4)   /* TX FIFO empty                    */
#define UART_STS_RX_FIFO_FULL  (1U << 5)   /* RX FIFO full                     */

/* ---- IRQ_STAT register bits ------------------------------------- */

#define UART_IRQ_TX_DONE   (1U << 0)   /* TX FIFO drained (W1C) */
#define UART_IRQ_RX_VALID  (1U << 1)   /* RX data available (W1C) */

/* ---- Baud rate presets (for FREQ = 100 MHz) --------------------- */

#define UART_BAUD_115200   0U   /* 0 = default 115200 */

/* ---- Register-struct view --------------------------------------- */

typedef struct {
    volatile uint32_t ctrl;       /* 0x00 */
    volatile uint32_t status;     /* 0x04 */
    volatile uint32_t txdata;     /* 0x08 */
    volatile uint32_t rxdata;     /* 0x0C */
    volatile uint32_t baud;       /* 0x10 */
    volatile uint32_t irq_stat;   /* 0x14 */
} uart_regs_t;

#define UART  ((volatile uart_regs_t *)UART_BASE)

/* ---- Public API ------------------------------------------------- */

/* Initialise UART: set baud divider and enable TX + RX. */
void uart_init(uint16_t baud_div);

/* Blocking put: waits until TX is not busy, then writes one byte. */
void uart_putc(char c);

/* Blocking get: waits until RX data is valid, then reads one byte. */
char uart_getc(void);

/* Non-blocking RX check: returns non-zero if a byte is available. */
int  uart_rx_valid(void);

/* Non-blocking TX check: returns non-zero if TX is busy. */
int  uart_tx_busy(void);

/* Non-blocking TX FIFO check: returns non-zero if TX FIFO is full. */
int  uart_tx_fifo_full(void);

/* Write a buffer of len bytes (blocking per byte). */
void uart_write(const char *buf, int len);

/* Write a NUL-terminated string (blocking per byte). */
void uart_puts(const char *s);

/* Clear interrupt pending bits (mask of UART_IRQ_*). */
void uart_clear_irq(uint32_t mask);

#endif /* UART_H */
