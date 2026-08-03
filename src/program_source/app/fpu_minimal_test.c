/*
 * Minimal FPU test: verify float arithmetic + ftoa work in the full CPU.
 * If this hangs, the problem is in FPU/ftoa software path.
 * If this passes, the problem is in calculator's parser or gets().
 */
#include "stdio.h"

/* Print 32-bit hex */
static void print_hex(unsigned int v)
{
    char hex_buf[9];
    for (int i = 7; i >= 0; i--) {
        int nibble = (v >> (i * 4)) & 0xF;
        hex_buf[7 - i] = nibble < 10 ? '0' + nibble : 'a' + nibble - 10;
    }
    hex_buf[8] = '\0';
    uart_puts(hex_buf);
}

/* Extract IEEE 754 bits via FMV.X.W */
static inline unsigned int float_to_bits(float f)
{
    unsigned int bits;
    __asm__ volatile("fmv.x.w %0, %1" : "=r"(bits) : "f"(f));
    return bits;
}

int main(void)
{
    uart_init(UART_BAUD_230400);

    uart_puts("\r\n--- FPU minimal test ---\r\n");

    /* Test 0: verify FLW loads correct bit pattern for 1.0f */
    float a = 1.0f;
    unsigned int bits_a = float_to_bits(a);
    uart_puts("FLW 1.0f bits = 0x");
    print_hex(bits_a);
    uart_puts(" (expect 0x3f800000)\r\n");

    float b = 2.0f;
    unsigned int bits_b = float_to_bits(b);
    uart_puts("FLW 2.0f bits = 0x");
    print_hex(bits_b);
    uart_puts(" (expect 0x40000000)\r\n");

    float c = a + b;
    unsigned int bits_c = float_to_bits(c);
    uart_puts("1.0 + 2.0 bits = 0x");
    print_hex(bits_c);
    uart_puts(" (expect 0x40400000)\r\n");

    /* Test 1: ftoa */
    uart_puts("ftoa(1.0+2.0) = ");
    print_float(c, 1);
    uart_puts("\r\n");

    /* Test 2: FCVT.W.S (int cast) */
    int ic = (int)c;
    uart_puts("(int)(1.0+2.0) = ");
    if (ic == 3) uart_puts("3 OK"); else { uart_puts("FAIL got="); print_hex((unsigned int)ic); }
    uart_puts("\r\n");

    uart_puts("\r\n--- Done ---\r\n");

    volatile int *check = (volatile int *)0x80000004;
    *check = 1;

    while (1) {}
    return 0;
}
