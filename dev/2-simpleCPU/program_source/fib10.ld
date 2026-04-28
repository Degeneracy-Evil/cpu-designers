ENTRY(_start)
SECTIONS {
    .text 0x0 : {
        *(.text.start)
        *(.text .text.*)
    }
}
