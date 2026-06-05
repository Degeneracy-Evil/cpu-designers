#ifndef MATH_H
#define MATH_H

/* ------------------------------------------------------------------ */
/*  Minimal math functions for bare-metal RISC-V with FPU             */
/*  Uses FPU instructions (FSQRT.S, FMUL.S, etc.) via C float ops.   */
/* ------------------------------------------------------------------ */

#define PI 3.14159265358979323846f

float sqrtf(float x);
float fabsf(float x);
float powf(float base, int exp);
float sinf(float x);
float cosf(float x);

#endif /* MATH_H */
