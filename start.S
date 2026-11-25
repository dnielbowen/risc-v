.section .text.init
.global _start

_start:
    /* Initialize stack pointer to top of 64 KB RAM (0x00010000) */
    lui  sp, 0x10

    /* Call C main() */
    jal  ra, main

    /* When main() returns (return value in a0/x10), halt the processor */
    ebreak

1:
    j 1b
