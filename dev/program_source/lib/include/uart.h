#ifndef UART_H
#define UART_H

#include "sys.h"

/* ------------------------------------------------------------------ */
/*  NS16550A UART driver                                               */
/*  Compatible with standard 16550A register map                       */
/*  TX/RX FIFO (16 bytes), configurable baud divisor, interrupt support */
/*                                                                     */
/*  Register map: byte offsets mapped to word-aligned APB4 addresses    */
/*  (reg N at byte offset N → APB4 offset N*4)                        */
/* ------------------------------------------------------------------ */

/* ---- Register map (word offsets from UART_BASE) ----------------- */
/*  NS16550A byte offset → APB4 word offset (×4)                     */

#define UART_REG_THR_RBR_DLL  0x00U   /* DLAB=0: THR(write)/RBR(read), DLAB=1: DLL */
#define UART_REG_IER_DLM      0x04U   /* DLAB=0: IER, DLAB=1: DLM */
#define UART_REG_IIR_FCR      0x08U   /* read: IIR, write: FCR */
#define UART_REG_LCR          0x0CU   /* Line Control Register */
#define UART_REG_MCR          0x10U   /* Modem Control Register */
#define UART_REG_LSR          0x14U   /* Line Status Register */
#define UART_REG_MSR          0x18U   /* Modem Status Register */
#define UART_REG_SCR          0x1CU   /* Scratch Register */

/* ---- IER (Interrupt Enable Register) bits ----------------------- */

#define UART_IER_RDA          (1U << 0)   /* Received Data Available */
#define UART_IER_THRE         (1U << 1)   /* TX Holding Register Empty */
#define UART_IER_RLS          (1U << 2)   /* Receiver Line Status */
#define UART_IER_MS           (1U << 3)   /* Modem Status */

/* ---- IIR (Interrupt Identification Register) ------------------- */

#define UART_IIR_IP           (1U << 0)   /* 0 = interrupt pending */
#define UART_IIR_ID_SHIFT     1
#define UART_IIR_ID_RLS       0x06U       /* Receiver Line Status */
#define UART_IIR_ID_RDA       0x04U       /* Received Data Available */
#define UART_IIR_ID_TI        0x0CU       /* Timeout Indication */
#define UART_IIR_ID_THRE      0x02U       /* TX Holding Register Empty */
#define UART_IIR_ID_MS        0x00U       /* Modem Status */

/* ---- FCR (FIFO Control Register) bits -------------------------- */

#define UART_FCR_FIFO_EN      (1U << 0)   /* FIFO enable (always 1 in 16550A) */
#define UART_FCR_RXSR         (1U << 1)   /* RX FIFO reset */
#define UART_FCR_TXSR         (1U << 2)   /* TX FIFO reset */
#define UART_FCR_DMA          (1U << 3)   /* DMA mode */
#define UART_FCR_TL_SHIFT     6           /* Trigger level shift */
#define UART_FCR_TL_1         (0U << 6)   /* Trigger at 1 byte */
#define UART_FCR_TL_4         (1U << 6)   /* Trigger at 4 bytes */
#define UART_FCR_TL_8         (2U << 6)   /* Trigger at 8 bytes */
#define UART_FCR_TL_14        (3U << 6)   /* Trigger at 14 bytes */

/* ---- LCR (Line Control Register) bits -------------------------- */

#define UART_LCR_WL5          0x00U       /* 5-bit word length */
#define UART_LCR_WL6          0x01U       /* 6-bit word length */
#define UART_LCR_WL7          0x02U       /* 7-bit word length */
#define UART_LCR_WL8          0x03U       /* 8-bit word length */
#define UART_LCR_STB          (1U << 2)   /* 1.5/2 stop bits */
#define UART_LCR_PEN          (1U << 3)   /* Parity enable */
#define UART_LCR_EPS          (1U << 4)   /* Even parity */
#define UART_LCR_SP           (1U << 5)   /* Stick parity */
#define UART_LCR_BC           (1U << 6)   /* Break control */
#define UART_LCR_DLAB         (1U << 7)   /* Divisor Latch Access Bit */

/* ---- MCR (Modem Control Register) bits ------------------------- */

#define UART_MCR_DTR          (1U << 0)   /* Data Terminal Ready */
#define UART_MCR_RTS          (1U << 1)   /* Request To Send */
#define UART_MCR_OUT1         (1U << 2)   /* Output 1 */
#define UART_MCR_OUT2         (1U << 3)   /* Output 2 (IRQ enable on PC) */
#define UART_MCR_LB           (1U << 4)   /* Loopback */

/* ---- LSR (Line Status Register) bits --------------------------- */

#define UART_LSR_DR           (1U << 0)   /* Data Ready */
#define UART_LSR_OE           (1U << 1)   /* Overrun Error */
#define UART_LSR_PE           (1U << 2)   /* Parity Error */
#define UART_LSR_FE           (1U << 3)   /* Framing Error */
#define UART_LSR_BI           (1U << 4)   /* Break Interrupt */
#define UART_LSR_THRE         (1U << 5)   /* TX Holding Register Empty */
#define UART_LSR_TE           (1U << 6)   /* Transmitter Empty */
#define UART_LSR_EI           (1U << 7)   /* Error Indicator */

/* ---- Baud rate presets (for FREQ = 100 MHz) --------------------- */
/*  divisor = FREQ_MHz * 1e6 / (16 * baud_rate)                     */

#define UART_DIV_115200       54U   /* 100e6 / (16 * 115200) ≈ 54.25 → 54 */

/* Backward compatibility alias */
#define UART_BAUD_115200     UART_DIV_115200

/* ---- Register-struct view (word-aligned) ------------------------ */

typedef struct {
    volatile uint32_t thr_rbr_dll;  /* 0x00 */
    volatile uint32_t ier_dlm;      /* 0x04 */
    volatile uint32_t iir_fcr;      /* 0x08 */
    volatile uint32_t lcr;          /* 0x0C */
    volatile uint32_t mcr;          /* 0x10 */
    volatile uint32_t lsr;          /* 0x14 */
    volatile uint32_t msr;          /* 0x18 */
    volatile uint32_t scr;          /* 0x1C */
} uart_regs_t;

#define UART  ((volatile uart_regs_t *)UART_BASE)

/* ---- Public API ------------------------------------------------- */

/* Initialise NS16550A: set baud divisor, 8N1, enable FIFOs. */
void uart_init(uint16_t baud_div);

/* Blocking put: waits until THR empty, then writes one byte. */
void uart_putc(char c);

/* Blocking get: waits until data ready, then reads one byte. */
char uart_getc(void);

/* Non-blocking RX check: returns non-zero if a byte is available. */
int  uart_rx_valid(void);

/* Non-blocking TX check: returns non-zero if THR is empty (ready). */
int  uart_tx_ready(void);

/* Write a buffer of len bytes (blocking per byte). */
void uart_write(const char *buf, int len);

/* Write a NUL-terminated string (blocking per byte). */
void uart_puts(const char *s);

#endif /* UART_H */
