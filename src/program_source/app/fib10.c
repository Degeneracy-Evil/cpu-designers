__attribute__((noinline))
static unsigned int fib10(void)
{
    unsigned int a = 0;
    unsigned int b = 1;

    for (unsigned int i = 0; i < 10; i++) {
        unsigned int t = a + b;
        a = b;
        b = t;
    }

    return a;
}

__attribute__((naked, noreturn, section(".text.start")))
void _start(void)
{
    __asm__ volatile(
        "addi sp, x0, 1024\n"
        "jal ra, fib10\n"
        "addi x1, a0, 0\n"
        "1:\n"
        "jal x0, 1b\n"
    );
}
