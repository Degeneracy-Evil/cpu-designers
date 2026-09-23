OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    DDR3 (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS {
    /* Startup code first, then rest of .text */
    .text : {
        *(.text.start)
        *(.text .text.*)
    } > DDR3

    /* Read-only data */
    .rodata : {
        *(.rodata .rodata.*)
    } > DDR3

    /* Initialised data */
    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > DDR3

    /* Zero-initialised data */
    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        . = ALIGN(4);
        __bss_end = .;
    } > DDR3

    /* Stack at top of DDR3, growing downward */
    _stack_top = ORIGIN(DDR3) + LENGTH(DDR3);

    /* Discard unwanted sections */
    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
    }
}
