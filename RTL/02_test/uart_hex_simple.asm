# Simple UART to HEX Display Test
# Memory Map:
#   UART RX: 0x10020004 (read: {valid[31], data[7:0]})
#   HEX 0-3: 0x10002000 (write: {hex3[15:12], hex2[11:8], hex1[7:4], hex0[3:0]})

    # Setup base addresses
    lui x20, 0x10020      # x20 = UART Base (0x10020000)
    lui x21, 0x10002      # x21 = HEX Low Base (0x10002000)

    # Initialize display to 0
    sw x0, 0(x21)

main_loop:
    # Poll UART RX (offset 0x4)
    lw   x5, 4(x20)
    
    # Check valid bit [31]
    srli x6, x5, 31
    beq  x6, x0, main_loop    # If not valid, keep polling

    # Extract data byte [7:0]
    andi x5, x5, 0xFF

    # Convert ASCII to hex value
    # '0'-'9' (0x30-0x39) -> 0-9
    # 'A'-'F' (0x41-0x46) -> 10-15
    # 'a'-'f' (0x61-0x66) -> 10-15
    
    andi x6, x5, 0x0F         # Get low nibble
    
    # Check if letter (>= 0x40)
    addi x7, x0, 0x40
    blt  x5, x7, write_hex    # If < 0x40 (digit), use as-is
    addi x6, x6, 9            # If letter, add 9

write_hex:
    # Write to HEX display immediately
    sw x6, 0(x21)
    
    # Jump back to main loop
    jal x0, main_loop
