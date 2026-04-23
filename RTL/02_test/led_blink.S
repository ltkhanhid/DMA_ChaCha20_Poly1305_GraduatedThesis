# ============================================================
# LED Blink Example - RV32I
# ============================================================
# Memory Map:
#   LEDR: 0x10000000
#   LEDG: 0x10001000
# ============================================================

.equ LEDR_BASE, 0x10000000
.equ LEDG_BASE, 0x10001000
.equ DELAY_COUNT, 0x200000      # Khoảng 2 triệu cycles

.section .text
.globl _start

_start:
    # Load base addresses
    lui  x10, %hi(LEDR_BASE)    # x10 = LEDR base
    lui  x11, %hi(LEDG_BASE)    # x11 = LEDG base

main_loop:
    # LED ON
    li   x5, 0x3FF              # All 10 LEDs on
    sw   x5, 0(x10)             # Write to LEDR
    
    jal  x1, delay              # Call delay
    
    # LED OFF
    sw   x0, 0(x10)             # All LEDs off
    
    jal  x1, delay              # Call delay
    
    j    main_loop              # Repeat

# ============================================================
# DELAY Subroutine
# ============================================================
delay:
    lui  x6, %hi(DELAY_COUNT)
    addi x6, x6, %lo(DELAY_COUNT)
delay_loop:
    addi x6, x6, -1
    bne  x6, x0, delay_loop
    ret                         # jalr x0, x1, 0
