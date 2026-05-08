OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
    inst (rx) : ORIGIN = 0x00000000, LENGTH = 32K
    data (rw) : ORIGIN = 0x00000000, LENGTH = 32K
}
SECTIONS {
    .text : { 
        *(.text*) 
    } > inst

    .data : { 
        *(.data*) 
        *(.rodata*)
        *(.sdata*)
    } > data
}