#ifndef _OS_TYPES_H
#define _OS_TYPES_H

/* Basic scalar types for the freestanding OS kernel (RV32). */

typedef signed char         int8_t;
typedef unsigned char       uint8_t;
typedef signed short        int16_t;
typedef unsigned short      uint16_t;
typedef signed int          int32_t;
typedef unsigned int        uint32_t;
typedef signed long long    int64_t;
typedef unsigned long long  uint64_t;

typedef uint32_t            uintptr_t;
typedef int32_t             intptr_t;
typedef uint32_t            size_t;
typedef int32_t             ssize_t;
typedef int32_t             bool_t;

typedef enum { false = 0, true = 1 } bool;

#ifndef NULL
#define NULL ((void *)0)
#endif

#endif /* _OS_TYPES_H */
