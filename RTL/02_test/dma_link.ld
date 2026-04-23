OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    . = 0x00000000;
    .text : { *(.text .text.*) }
    . = ALIGN(4);
    /DISCARD/ : { *(*) }
}
