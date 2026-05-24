OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    SRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 32K
}

SECTIONS {
    /* Startup code first, then rest of .text */
    .text : {
        *(.text.start)
        *(.text .text.*)
    } > SRAM

    /* Read-only data */
    .rodata : {
        *(.rodata .rodata.*)
    } > SRAM

    /* Initialised data */
    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > SRAM

    /* Zero-initialised data */
    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        . = ALIGN(4);
        __bss_end = .;
    } > SRAM

    /* Stack at top of SRAM, growing downward */
    _stack_top = ORIGIN(SRAM) + LENGTH(SRAM);

    /* Discard unwanted sections */
    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
    }
}
