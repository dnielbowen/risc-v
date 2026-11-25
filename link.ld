OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
    . = 0x00000000;

    .text : {
        KEEP(*(.text.init))
        *(.text*)
    }

    .rodata : ALIGN(4) {
        *(.rodata*)
        *(.srodata*)
    }

    .data : ALIGN(4) {
        *(.data*)
        *(.sdata*)
    }

    .bss : ALIGN(4) {
        *(.bss*)
        *(.sbss*)
        *(COMMON)
    }
}
