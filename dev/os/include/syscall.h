#ifndef _OS_SYSCALL_H
#define _OS_SYSCALL_H

#include "types.h"

/* ------------------------------------------------------------------ */
/*  Syscall numbers                                                   */
/* ------------------------------------------------------------------ */

#define SYS_exit        2
#define SYS_read        7
#define SYS_write       8
#define SYS_report      9

/* ------------------------------------------------------------------ */
/*  Syscall wrapper declarations                                      */
/*                                                                    */
/*  Convention:                                                       */
/*    a7 = syscall number                                             */
/*    a0-a5 = arguments                                               */
/*    a0 = return value                                               */
/* ------------------------------------------------------------------ */

void     sys_exit(int pass, int total, int first_fail) __attribute__((noreturn));
void     sys_report(int pass, int total, int first_fail);
ssize_t  sys_read(int fd, void *buf, size_t len);
ssize_t  sys_write(int fd, const void *buf, size_t len);

#endif /* _OS_SYSCALL_H */
