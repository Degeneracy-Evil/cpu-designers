/*
 * user.ld — SimpleOS user-program linker script
 *
 * User programs are linked at VA 0x00000000 (VA_USER_BASE). At runtime the
 * OS maps VA [0, len) → PA [0x80008000, 0x80008000+len) via an Sv32 L0
 * page table, then jumps to VA 0 in U-mode.
 *
 * The resulting ELF is converted to a flat binary (user.bin) by objcopy;
 * the kernel embeds that binary at PA_USER_PROG (0x80008000) via os.ld.
 *
 * No MEMORY command is used: the binary has no fixed physical placement
 * at link time — the kernel decides where to load it.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS {
    /* ---- Startup code FIRST ---- */
    .text.start : {
        *(.text.start)
    }

    /* ---- Remaining code ---- */
    .text : {
        *(.text .text.*)
    }

    /* ---- Read-only data ---- */
    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    }

    /* ---- Initialised data ---- */
    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    }

    /* ---- Zero-initialised data (NOLOAD — cleared by user_start.S) ---- */
    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    }

    /* ---- Provided symbols ---- */
    /* User stack top: VA_USER_STACK_TOP (0x00009000). user_start.S does
     * `li sp, 0x9000`; this symbol is provided for completeness / any
     * code that wants to reference it symbolically. */
    _stack_top = 0x00009000;

    /* ---- Discard unwanted sections ---- */
    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}
