/*
 * User-side console input for SimpleOS user programs.
 *
 * All input comes through sys_read (ecall) — NO direct MMIO access.
 *
 * Ported from dev/program_source/lib/stdio.c gets():
 *   - uart_getc -> user_getc (sys_read from fd 0)
 *   - echo via user_putc (sys_write to fd 1)
 */

#include "user.h"

/* ------------------------------------------------------------------ */
/*  user_getc — read a single char from stdin (fd 0) via sys_read      */
/*  Returns the character read (as int).                               */
/* ------------------------------------------------------------------ */

int user_getc(void)
{
    char c = 0;
    sys_read(0, &c, 1);
    return (int)c;
}

/* ------------------------------------------------------------------ */
/*  user_gets — read a line from stdin into buf                        */
/*                                                                    */
/*  Reads at most maxlen-1 characters, NUL-terminates the buffer.      */
/*  Echoes each character back via user_putc.                          */
/*  Stops on '\r' or '\n' (echoes CRLF).                               */
/*  Handles backspace (0x7F) / delete (0x08).                          */
/*  Ported from lib/stdio.c gets(), uart_getc -> user_getc,           */
/*  uart_putc -> user_putc.                                            */
/* ------------------------------------------------------------------ */

char *user_gets(char *buf, int maxlen)
{
    int i = 0;
    while (i < maxlen - 1) {
        char c = (char)user_getc();
        if (c == '\r' || c == '\n') {
            user_putc('\r');
            user_putc('\n');
            break;
        }
        if (c == 0x7F || c == 0x08) {   /* backspace / delete */
            if (i > 0) {
                i--;
                user_putc(0x08);
                user_putc(' ');
                user_putc(0x08);
            }
            continue;
        }
        buf[i++] = c;
        user_putc(c);    /* echo */
    }
    buf[i] = '\0';
    return buf;
}
