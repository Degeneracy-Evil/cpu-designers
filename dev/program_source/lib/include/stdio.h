#ifndef STDIO_H
#define STDIO_H

/* ------------------------------------------------------------------ */
/*  Minimal stdio for bare-metal RISC-V with UART                     */
/*  - printf: supports %d, %s, %c, %% (NO %f — float promotes to     */
/*    double in variadic, but we lack D extension)                     */
/*  - print_float: direct float output (no variadic promotion)         */
/*  - gets:  read a line from UART (echoes characters)                */
/* ------------------------------------------------------------------ */

#include "uart.h"

/* Write a formatted string to UART. Supports %d, %s, %c, %%. */
void printf(const char *fmt, ...);

/* Print a float value with given decimal precision (no variadic). */
void print_float(float f, int precision);

/* Read a line from UART into buf (max maxlen-1 chars + NUL).
 * Echoes characters back. Returns buf on success. */
char *gets(char *buf, int maxlen);

/* Convert float to ASCII string. Returns number of chars written. */
int ftoa(float f, char *buf, int precision);

/* Convert ASCII string to float. */
float atof(const char *s);

#endif /* STDIO_H */
