#include "math.h"

/* ------------------------------------------------------------------ */
/*  Minimal math functions for bare-metal RISC-V with FPU             */
/*  - sqrtf:  uses FSQRT.S instruction directly                       */
/*  - fabsf:  uses FSGNJ.S (sign injection) via -x if negative       */
/*  - powf:   integer exponent only (multiply loop)                   */
/*  - sinf/cosf: Taylor series (7 terms, |x|<=pi)                    */
/* ------------------------------------------------------------------ */

float sqrtf(float x)
{
    /* Use FSQRT.S instruction directly via inline asm */
    float result;
    __asm__ volatile("fsqrt.s %0, %1" : "=f"(result) : "f"(x));
    return result;
}

float fabsf(float x)
{
    return x < 0.0f ? -x : x;
}

float powf(float base, int exp)
{
    if (exp == 0)
        return 1.0f;

    float result = 1.0f;
    int   abs_exp = exp < 0 ? -exp : exp;

    for (int i = 0; i < abs_exp; i++)
        result = result * base;

    if (exp < 0)
        result = 1.0f / result;

    return result;
}

/* Reduce angle to [-pi, pi] for Taylor series convergence */
static float reduce_angle(float x)
{
    /* Normalize to [0, 2*pi) */
    float twopi = 2.0f * PI;
    if (x < 0.0f)
        x = x + twopi * (float)(-(int)(x / twopi) + 1);
    else
        x = x - twopi * (float)((int)(x / twopi));

    /* Shift to [-pi, pi] */
    if (x > PI)
        x = x - twopi;

    return x;
}

float sinf(float x)
{
    x = reduce_angle(x);

    /* Taylor series: sin(x) = x - x^3/3! + x^5/5! - x^7/7! + ... */
    float x2  = x * x;
    float x3  = x2 * x;
    float x5  = x3 * x2;
    float x7  = x5 * x2;
    float x9  = x7 * x2;
    float x11 = x9 * x2;
    float x13 = x11 * x2;

    return x
         - x3  * (1.0f / 6.0f)
         + x5  * (1.0f / 120.0f)
         - x7  * (1.0f / 5040.0f)
         + x9  * (1.0f / 362880.0f)
         - x11 * (1.0f / 39916800.0f)
         + x13 * (1.0f / 6227020800.0f);
}

float cosf(float x)
{
    x = reduce_angle(x);

    /* Taylor series: cos(x) = 1 - x^2/2! + x^4/4! - x^6/6! + ... */
    float x2  = x * x;
    float x4  = x2 * x2;
    float x6  = x4 * x2;
    float x8  = x6 * x2;
    float x10 = x8 * x2;
    float x12 = x10 * x2;

    return 1.0f
         - x2  * (1.0f / 2.0f)
         + x4  * (1.0f / 24.0f)
         - x6  * (1.0f / 720.0f)
         + x8  * (1.0f / 40320.0f)
         - x10 * (1.0f / 3628800.0f)
         + x12 * (1.0f / 479001600.0f);
}
