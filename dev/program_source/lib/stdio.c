#include "stdio.h"

/* ------------------------------------------------------------------ */
/*  Minimal printf / gets for bare-metal RISC-V                       */
/*  NOTE: printf does NOT support %f because float is promoted to     */
/*  double in variadic functions (C standard), but we lack D ext.     */
/*  Use print_float() instead for float output.                       */
/* ------------------------------------------------------------------ */

/* ---- Internal helpers -------------------------------------------- */

static void print_int(int n)
{
    char buf[12];
    int  i = 0;
    int  neg = 0;

    if (n < 0) {
        neg = 1;
        n = -n;
    }

    if (n == 0) {
        uart_putc('0');
        return;
    }

    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }

    if (neg)
        uart_putc('-');

    while (i > 0)
        uart_putc(buf[--i]);
}

/* ---- print_float ------------------------------------------------- */

void print_float(float f, int precision)
{
    char buf[16];
    ftoa(f, buf, precision);
    uart_puts(buf);
}

/* ---- printf ------------------------------------------------------ */

void printf(const char *fmt, ...)
{
    __builtin_va_list ap;
    __builtin_va_start(ap, fmt);

    while (*fmt) {
        if (*fmt != '%') {
            uart_putc(*fmt++);
            continue;
        }
        fmt++;  /* skip '%' */

        switch (*fmt) {
        case 'd': {
            int val = __builtin_va_arg(ap, int);
            print_int(val);
            break;
        }
        case 's': {
            const char *s = __builtin_va_arg(ap, const char *);
            if (s)
                uart_puts(s);
            else
                uart_puts("(null)");
            break;
        }
        case 'c': {
            int c = __builtin_va_arg(ap, int);
            uart_putc((char)c);
            break;
        }
        case '%':
            uart_putc('%');
            break;
        default:
            uart_putc('%');
            uart_putc(*fmt);
            break;
        }
        fmt++;
    }

    __builtin_va_end(ap);
}

/* ---- gets -------------------------------------------------------- */

char *gets(char *buf, int maxlen)
{
    int i = 0;
    while (i < maxlen - 1) {
        char c = uart_getc();
        if (c == '\r' || c == '\n') {
            uart_putc('\r');
            uart_putc('\n');
            break;
        }
        if (c == 0x7F || c == 0x08) {   /* backspace / delete */
            if (i > 0) {
                i--;
                uart_putc(0x08);
                uart_putc(' ');
                uart_putc(0x08);
            }
            continue;
        }
        buf[i++] = c;
        uart_putc(c);    /* echo */
    }
    buf[i] = '\0';
    return buf;
}
