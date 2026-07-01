#include "user.h"

/* ------------------------------------------------------------------ */
/*  ftoa — float to ASCII conversion for bare-metal RISC-V            */
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

int ftoa(float f, char *buf, int precision)
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
            int_buf[int_len++] = '0' + digit;
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
                int_val = int_val + (int_buf[i] - '0') * place;
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
            buf[pos++] = '0' + digit;
            frac = frac - (float)digit;
        }
    }

    buf[pos] = '\0';
    return pos;
}
