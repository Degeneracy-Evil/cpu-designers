/*
 * os.ld — SimpleOS kernel linker script
 *
 * Physical memory layout (DDR3 @ 0x80000000):
 *   0x80000000  L1 page table          (4 KB)
 *   0x80001000  L0 kernel page table   (4 KB)
 *   0x80002000  L0 user page table     (4 KB)
 *   0x80003000  kernel stack           (16 KB, grows down to 0x80003000)
 *   0x80007000  self-check area        (4 KB)
 *   0x80008000  user program image     (embedded via .incbin)
 *   0x80004000  kernel image load addr (this script)
 *
 * The kernel is loaded at 0x80004000, immediately above the page-table /
 * stack region. The kernel stack grows DOWN from 0x80004000 (top of the
 * 0x80003000..0x80004000 region reserved in memlayout.h as PA_KERNEL_STACK).
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    /* Kernel image lives in DDR3 starting at 0x80004000.
     * Length covers 0x80004000..0x80010000 (48 KB): 16 KB for the
     * kernel proper (0x80004000..0x80008000) plus 32 KB for the
     * embedded user binary at 0x80008000 (PA_USER_PROG). */
    KERNEL (rwx) : ORIGIN = 0x80004000, LENGTH = 48K
}

SECTIONS {
    /* ---- Kernel code ---- */
    .text : {
        *(.text.start)          /* _start first */
        *(.text .text.*)
    } > KERNEL

    /* ---- Read-only data ---- */
    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > KERNEL

    /* ---- Initialised data ---- */
    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > KERNEL

    /* ---- Zero-initialised data (NOLOAD — cleared at runtime) ---- */
    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > KERNEL

    /* ---- Embedded user program image ----
     * Placed at PA_USER_PROG (0x80008000). The .incbin directive pulls in
     * the pre-built user.bin produced by the build system (Task 8 Makefile
     * guarantees user.bin exists before the kernel link step). */
    .user_bin 0x80008000 : {
        . = ALIGN(4);
        _user_bin_start = .;
        KEEP(*(.user_bin))
        /* Inline-include the user binary. Using BYTE() trick: ld does not
         * support .incbin inside SECTIONS, so the build system emits a
         * tiny .user_bin.o wrapper containing the .incbin. We just keep
         * whatever the wrapper places here. */
        . = ALIGN(4);
        _user_bin_end = .;
    } > KERNEL

    /* ---- Provided symbols (not backed by sections) ---- */
    /* Kernel stack top: grows DOWN from 0x80004000 (PA_KERNEL_STACK region
     * is 0x80003000..0x80004000). _start sets sp = _kernel_stack_top. */
    _kernel_stack_top = 0x80004000;

    /* Self-check result area used by the test harness. */
    __self_check = 0x80007000;

    /* ---- Discard unwanted sections ---- */
    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}
