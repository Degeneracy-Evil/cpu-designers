/*
 * Diagnostic: read the crash address as DATA before executing main.
 * 
 * This program's _start will (via inline asm before call main):
 *   1. Load word at 0x80000298 into t3 (x28) — visible as REG1C on LCD
 *   2. Load word at 0x80000294 into t4 (x29) — visible as REG1D on LCD
 *   3. Load word at 0x80000280 into t5 (x30) — visible as REG1E on LCD
 * 
 * Then call a minimal main that just loops.
 * If the crash still happens, we can see what DDR3/dcache has at those addresses.
 * If the crash doesn't happen (because main is tiny), we see the actual values.
 */
int main(void) {
    /* Minimal loop — no stack frame needed with -Os */
    volatile int *p = (volatile int *)0x80000298;
    (void)p;
    for (;;) {
        /* spin */
    }
    return 0;
}
