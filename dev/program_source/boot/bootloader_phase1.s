/**
 * bootloader_phase1.s — Phase-1 Bootloader: jump to SRAM
 *
 * Runs from Boot ROM at 0xFC00_0000. Simply jumps to 0x8000_0000
 * where the main program is pre-loaded via $readmemh (simulation)
 * or UART download (phase-2).
 *
 * This is the minimal bootloader for phase-1 testing:
 *   1. Jump to 0x8000_0000
 */

.section .text
.globl _start

_start:
    lui  t0, 0x80000          # t0 = 0x80000000
    jr   t0                   # Jump to main program in SRAM
