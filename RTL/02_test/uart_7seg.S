# uart_7seg.S - GNU Assembly version
# Converted from uart_7seg.asm

.section .text
.globl _start

_start:
    # --- INIT ADDRESSES ---
    lui x20, 0x10020      # UART Base
    lui x21, 0x10002      # HEX Low
    lui x22, 0x10003      # HEX High

    # --- INIT BUFFER (CRITICAL!) ---
    addi x8,  x0, 0       # HEX0 (newest)
    addi x9,  x0, 0       # HEX1
    addi x10, x0, 0       # HEX2
    addi x11, x0, 0       # HEX3
    addi x12, x0, 0       # HEX4
    addi x13, x0, 0       # HEX5
    addi x14, x0, 0       # HEX6
    addi x15, x0, 0       # HEX7 (oldest)

    jal x1, update_display

main_loop:
    # --- READ UART ---
    lw   x5, 4(x20)
    srli x6, x5, 31
    beq  x6, x0, main_loop  # Wait for data

    andi x5, x5, 0xFF     # Get ASCII byte

    # =============================================================
    # ASCII -> HEX VALUE CONVERSION
    # =============================================================
    
    # Compare with 0x40 (char '@'). 
    addi x6, x0, 0x40     
    blt  x5, x6, is_digit 

is_letter:
    # Case: letter (A-F): Subtract 0x37 (55 decimal)
    addi x5, x5, -55      
    j    finish_conv

is_digit:
    # Case: digit (0-9): Subtract 0x30 (48 decimal)
    addi x5, x5, -48

finish_conv:
    # Ensure result is in range 0-15 (0x0-0xF)
    andi x5, x5, 0x0F     

    # =============================================================
    # SHIFT BUFFER (SCROLLING)
    # =============================================================
    addi x15, x14, 0
    addi x14, x13, 0
    addi x13, x12, 0
    addi x12, x11, 0
    addi x11, x10, 0
    addi x10, x9,  0
    addi x9,  x8,  0
    addi x8,  x5,  0      # Store actual HEX value into x8

    jal x1, update_display
    jal x0, main_loop

# =============================================================
# UPDATE DISPLAY (NIBBLE PACKING - 4 BIT SHIFT)
# =============================================================
update_display:
    # --- PACK LOW (HEX 0-3) ---
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

    # --- PACK HIGH (HEX 4-7) ---
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
