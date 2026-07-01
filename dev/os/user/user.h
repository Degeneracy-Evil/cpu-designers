#ifndef _OS_USER_H
#define _OS_USER_H

/*
 * User-side library for SimpleOS user programs (U-mode).
 *
 * All console I/O is performed via ecall-based syscalls — NO direct
 * MMIO access. This header is the single include a user program needs.
 */

#include "types.h"
#include "syscall.h"

/* ------------------------------------------------------------------ */
/*  Syscall wrappers (defined in user_syscall.S)                       */
/*  Re-declared here for user convenience; also in syscall.h.          */
/* ------------------------------------------------------------------ */

void     sys_exit(int pass, int total, int first_fail) __attribute__((noreturn));
void     sys_report(int pass, int total, int first_fail);
ssize_t  sys_read(int fd, void *buf, size_t len);
ssize_t  sys_write(int fd, const void *buf, size_t len);

/* ------------------------------------------------------------------ */
/*  Console output (defined in user_printf.c)                          */
/* ------------------------------------------------------------------ */

/* Write a single character to stdout (fd 1). */
void user_putc(char c);

/* Write a NUL-terminated string to stdout (fd 1). */
void user_puts(const char *s);

/*
 * Minimal printf to stdout. Supports %d, %s, %c, %%.
 * Does NOT support %f (float promotes to double in variadic, but we
 * lack the D extension). Use print_float() for float output.
 */
void user_printf(const char *fmt, ...);

/* Print a float value with given decimal precision. */
void print_float(float f, int precision);

/* ------------------------------------------------------------------ */
/*  Console input (defined in user_gets.c)                             */
/* ------------------------------------------------------------------ */

/* Read a single character from stdin (fd 0). Returns the char as int. */
int user_getc(void);

/*
 * Read a line from stdin into buf (at most maxlen-1 chars + NUL).
 * Echoes characters back. Handles backspace/delete.
 * Returns buf on success.
 */
char *user_gets(char *buf, int maxlen);

#endif /* _OS_USER_H */
