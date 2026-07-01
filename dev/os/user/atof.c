#include "user.h"

/* ------------------------------------------------------------------ */
/*  atof — ASCII to float conversion for bare-metal RISC-V            */
/*  Uses FCVT.S.W (via C cast) for integer→float conversion.          */
/* ------------------------------------------------------------------ */

float atof(const char *s)
{
    float result = 0.0f;
    int   neg    = 0;

    /* Skip leading whitespace */
    while (*s == ' ' || *s == '\t')
        s++;

    /* Sign */
    if (*s == '-') {
        neg = 1;
        s++;
    } else if (*s == '+') {
        s++;
    }

    /* Integer part */
    while (*s >= '0' && *s <= '9') {
        result = result * 10.0f + (float)(*s - '0');
        s++;
    }

    /* Fractional part */
    if (*s == '.') {
        s++;
        float frac_place = 0.1f;
        while (*s >= '0' && *s <= '9') {
            result = result + (float)(*s - '0') * frac_place;
            frac_place = frac_place * 0.1f;
            s++;
        }
    }

    /* Exponent part (e.g. 1.5e2 = 150.0) */
    if (*s == 'e' || *s == 'E') {
        s++;
        int exp_neg = 0;
        if (*s == '-') {
            exp_neg = 1;
            s++;
        } else if (*s == '+') {
            s++;
        }
        int exp_val = 0;
        while (*s >= '0' && *s <= '9') {
            exp_val = exp_val * 10 + (*s - '0');
            s++;
        }
        float exp_mult = 1.0f;
        float exp_base = exp_neg ? 0.1f : 10.0f;
        for (int i = 0; i < exp_val; i++)
            exp_mult = exp_mult * exp_base;
        result = result * exp_mult;
    }

    if (neg)
        result = -result;

    return result;
}
