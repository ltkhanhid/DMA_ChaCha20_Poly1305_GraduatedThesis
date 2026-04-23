# uart_7seg_v2.S - Matching RARS ver3.hex (no jump after is_letter)
# The RARS version uses fall-through instead of explicit jump

.section .text
.globl _start

_start:
    # --- INIT ADDRESSES ---
    lui x20, 0x10020      # UART Base
    lui x21, 0x10002      # HEX Low
    lui x22, 0x10003      # HEX High

    # --- INIT BUFFER ---
    addi x8,  x0, 0
    addi x9,  x0, 0
    addi x10, x0, 0
    addi x11, x0, 0
    addi x12, x0, 0
    addi x13, x0, 0
    addi x14, x0, 0
    addi x15, x0, 0

    jal x1, update_display

main_loop:
    lw   x5, 4(x20)
    srli x6, x5, 31
    beq  x6, x0, main_loop

    andi x5, x5, 0xFF

    # ASCII -> HEX conversion
    addi x6, x0, 0x40     
    blt  x5, x6, is_digit 

is_letter:
    addi x5, x5, -55      
    # NO JUMP HERE - fall through to is_digit!
    # This means is_digit also executes: x5 = x5 - 55 - 48 = x5 - 103

is_digit:
    addi x5, x5, -48

finish_conv:
    andi x5, x5, 0x0F     

    # SHIFT BUFFER
    addi x15, x14, 0
    addi x14, x13, 0
    addi x13, x12, 0
    addi x12, x11, 0
    addi x11, x10, 0
    addi x10, x9,  0
    addi x9,  x8,  0
    addi x8,  x5,  0

    jal x1, update_display
    jal x0, main_loop

update_display:
    andi x16, x8, 0x0F
    
    andi x17, x9, 0x0F
    slli x17, x17, 4
    or   x16, x16, x17
    
    andi x17, x10, 0x0F
    slli x17, x17, 8
    or   x16, x16, x17
    
    andi x17, x11, 0x0F
    slli x17, x17, 12
    or   x16, x16, x17
    
    sw   x16, 0(x21)

    andi x16, x12, 0x0F
    
    andi x17, x13, 0x0F
    slli x17, x17, 4
    or   x16, x16, x17
    
    andi x17, x14, 0x0F
    slli x17, x17, 8
    or   x16, x16, x17
    
    andi x17, x15, 0x0F
    slli x17, x17, 12
    or   x16, x16, x17
    
    sw   x16, 0(x22)

    jalr x0, 0(x1)
