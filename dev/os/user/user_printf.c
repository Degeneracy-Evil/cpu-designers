/*
 * User-side console output for SimpleOS user programs.
 *
 * All output goes through sys_write (ecall) — NO direct MMIO access.
 *
 * Ported from dev/program_source/lib/stdio.c and lib/ftoa.c:
 *   - uart_putc  -> user_putc   (sys_write to fd 1)
 *   - uart_puts  -> user_puts   (sys_write to fd 1)
 *   - printf     -> user_printf (same format specifiers: %d %s %c %%)
 *   - print_float unchanged logic, uses user_puts
 *   - ftoa       inlined as static helper (ported from lib/ftoa.c)
 */

#include "user.h"

/* ------------------------------------------------------------------ */
/*  user_putc — write a single char to stdout (fd 1) via sys_write     */
/* ------------------------------------------------------------------ */

void user_putc(char c)
{
    sys_write(1, &c, 1);
}

/* ------------------------------------------------------------------ */
/*  user_puts — write a NUL-terminated string to stdout via sys_write  */
/*  Inline strlen keeps this freestanding (no <string.h>).             */
/* ------------------------------------------------------------------ */

void user_puts(const char *s)
{
    const char *p = s;
    while (*p)
        p++;
    sys_write(1, s, (size_t)(p - s));
}

/* ------------------------------------------------------------------ */
/*  Internal: print integer (ported from lib/stdio.c print_int)        */
/* ------------------------------------------------------------------ */

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
        user_putc('0');
        return;
    }

    while (n > 0) {
        buf[i++] = (char)('0' + (n % 10));
        n /= 10;
    }

    if (neg)
        user_putc('-');

    while (i > 0)
        user_putc(buf[--i]);
}

/* ------------------------------------------------------------------ */
/*  Internal: ftoa (ported from lib/ftoa.c)                            */
/*  Uses FMV.X.W to extract IEEE 754 bit pattern for special values.  */
/* ------------------------------------------------------------------ */

/* Extract IEEE 754 bit pattern via FMV.X.W */
static inline unsigned int float_to_bits(float f)
{
    unsigned int bits;
    __asm__ volatile("fmv.x.w %0, %1" : "=r"(bits) : "f"(f));
    return bits;
}

/* Check if float is NaN */
static inline int is_nan(float f)
{
    unsigned int bits = float_to_bits(f);
    unsigned int exp  = (bits >> 23) & 0xFF;
    unsigned int frac = bits & 0x7FFFFF;
    return (exp == 0xFF) && (frac != 0);
}

/* Check if float is Inf */
static inline int is_inf(float f)
{
    unsigned int bits = float_to_bits(f);
    unsigned int exp  = (bits >> 23) & 0xFF;
    unsigned int frac = bits & 0x7FFFFF;
    return (exp == 0xFF) && (frac == 0);
}

static int ftoa(float f, char *buf, int precision)
{
    int pos = 0;

    /* Handle special values */
    if (is_nan(f)) {
        buf[0] = 'n'; buf[1] = 'a'; buf[2] = 'n'; buf[3] = '\0';
        return 3;
    }

    if (is_inf(f)) {
        if (f < 0.0f)
            buf[pos++] = '-';
        buf[pos++] = 'i'; buf[pos++] = 'n'; buf[pos++] = 'f'; buf[pos++] = '\0';
        return pos;
    }

    /* Handle sign */
    if (f < 0.0f) {
        buf[pos++] = '-';
        f = -f;
    }

    /* Handle zero */
    if (f == 0.0f) {
        buf[pos++] = '0';
        if (precision > 0) {
            buf[pos++] = '.';
            for (int i = 0; i < precision; i++)
                buf[pos++] = '0';
        }
        buf[pos] = '\0';
        return pos;
    }

    /* Integer part: extract digits by repeated divide-by-10 */
    char int_buf[12];
    int  int_len = 0;

    if (f >= 1.0f) {
        /* Build integer digits in reverse */
        float fi = f;
        while (fi >= 1.0f) {
            int digit = (int)fi % 10;
            int_buf[int_len++] = (char)('0' + digit);
            fi = fi / 10.0f;
            /* Safety: break if fi isn't decreasing (shouldn't happen) */
            if (int_len >= 11) break;
        }
        /* Copy reversed digits to output */
        for (int i = int_len - 1; i >= 0; i--)
            buf[pos++] = int_buf[i];
    } else {
        buf[pos++] = '0';
    }

    /* Fractional part */
    if (precision > 0) {
        buf[pos++] = '.';

        /* Subtract integer part to get fractional part */
        float frac = f;
        if (f >= 1.0f) {
            /* Reconstruct integer part and subtract */
            float int_val = 0.0f;
            float place = 1.0f;
            for (int i = 0; i < int_len; i++) {
                int_val = int_val + (float)(int_buf[i] - '0') * place;
                place = place * 10.0f;
            }
            frac = f - int_val;
        }

        /* Generate fractional digits */
        for (int i = 0; i < precision; i++) {
            frac = frac * 10.0f;
            int digit = (int)frac;
            if (digit > 9) digit = 9;
            if (digit < 0) digit = 0;
            buf[pos++] = (char)('0' + digit);
            frac = frac - (float)digit;
        }
    }

    buf[pos] = '\0';
    return pos;
}

/* ------------------------------------------------------------------ */
/*  print_float — print a float with given decimal precision           */
/*  (ported from lib/stdio.c, uart_puts -> user_puts)                  */
/* ------------------------------------------------------------------ */

void print_float(float f, int precision)
{
    char buf[16];
    ftoa(f, buf, precision);
    user_puts(buf);
}

/* ------------------------------------------------------------------ */
/*  user_printf — minimal printf via sys_write                         */
/*  Supports %d, %s, %c, %% (NO %f — float promotes to double in      */
/*  variadic, but we lack D extension; use print_float instead).       */
/*  Ported from lib/stdio.c printf, uart_putc -> user_putc,           */
/*  uart_puts -> user_puts.                                            */
/* ------------------------------------------------------------------ */

void user_printf(const char *fmt, ...)
{
    __builtin_va_list ap;
    __builtin_va_start(ap, fmt);

    while (*fmt) {
        if (*fmt != '%') {
            user_putc(*fmt++);
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
                user_puts(s);
            else
                user_puts("(null)");
            break;
        }
        case 'c': {
            int c = __builtin_va_arg(ap, int);
            user_putc((char)c);
            break;
        }
        case '%':
            user_putc('%');
            break;
        default:
            user_putc('%');
            user_putc(*fmt);
            break;
        }
        fmt++;
    }

    __builtin_va_end(ap);
}
