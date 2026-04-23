# =============================================================================
# corner_test.S — SoC Corner Case Test Firmware
#
# Tests ChaCha20, DMA, and cross-module corner cases through LEDR phases.
# Each test writes a unique phase code to LEDR. Final result:
#   LEDR = 0xAA → ALL PASS,  LEDR = 0xFF → FAIL
#
# Memory Map:
#   0x1000_0000 : GPIO (LEDR @+0, LEDG @+4, HEX_LO @+8, HEX_HI @+C, SW @+10)
#   0x1005_0000 : DMA
#       CH0_CONTROL  @+0x00   [0]=enable [1]=src_inc [2]=dst_inc
#       CH0_STATUS   @+0x04   [0]=busy [1]=done [2]=error [31:16]=remaining
#       CH0_SRC_ADDR @+0x08
#       CH0_DST_ADDR @+0x0C
#       CH0_XFER_CNT @+0x10
#       CH1_CONTROL  @+0x20
#       CH1_STATUS   @+0x24
#       CH1_SRC_ADDR @+0x28
#       CH1_DST_ADDR @+0x2C
#       CH1_XFER_CNT @+0x30
#       IRQ_STATUS   @+0x40   [0]=ch0_irq [1]=ch1_irq (W1C)
#   0x1006_0000 : ChaCha20
#       KEY[0..7]    @+0x00..+0x1C
#       NONCE[0..2]  @+0x20..+0x28
#       COUNTER      @+0x2C
#       CONTROL      @+0x30   [0]=start
#       STATUS       @+0x34   [0]=ready
#       IRQ_STATUS   @+0x38   [0]=done (W1C)
#       PTEXT[0..15] @+0x40..+0x7C
#       CTEXT[0..15] @+0x80..+0xBC (read-only)
#
# Test list:
#   T01: ChaCha20 basic encryption (RFC 8439 TV#1: all-zero key/nonce/counter)
#   T02: ChaCha20 back-to-back (counter auto-incremented to 1)
#   T03: ChaCha20 IRQ W1C (clear and re-check)
#   T04: ChaCha20 write to read-only CTEXT (should be ignored)
#   T05: DMA CH0 basic 4-word transfer MEM to MEM
#   T06: DMA CH1 basic 4-word transfer (first CH1 exercise)
#   T07: DMA fixed-destination (FIFO mode, dst_inc=0)
#   T08: DMA zero-count transfer (should complete immediately)
#   T09: DMA CH0+CH1 concurrent transfers
#   T10: DMA to ChaCha20 MMIO (DMA writes plaintext regs, CPU encrypts)
# =============================================================================

.section .text
.globl _start
_start:
    # ===================== Setup base addresses =====================
    lui   x1,  0x10000     # x1  = 0x1000_0000  (GPIO)
    lui   x6,  0x10050     # x6  = 0x1005_0000  (DMA)
    lui   x3,  0x10060     # x3  = 0x1006_0000  (ChaCha20)
    li    x4,  0           # x4  = pass counter
    li    x5,  10          # x5  = total tests
    # li    sp,  0x7FF0      # stack pointer (unused, removed to avoid x2 conflict)

# =====================================================================
# T01: ChaCha20 basic encryption — all-zero key/nonce, counter=0
# RFC 8439 A.1 TV#1: keystream[0] = 0xade0b876
# With plaintext=0, ciphertext = keystream
# =====================================================================
t01:
    li    x10, 0x01
    sw    x10, 0(x1)       # LEDR = 0x01

    # Clear key (8 words)
    sw    zero, 0x00(x3)
    sw    zero, 0x04(x3)
    sw    zero, 0x08(x3)
    sw    zero, 0x0C(x3)
    sw    zero, 0x10(x3)
    sw    zero, 0x14(x3)
    sw    zero, 0x18(x3)
    sw    zero, 0x1C(x3)

    # Clear nonce (3 words)
    sw    zero, 0x20(x3)
    sw    zero, 0x24(x3)
    sw    zero, 0x28(x3)

    # Counter = 0
    sw    zero, 0x2C(x3)

    # Clear plaintext (16 words)
    sw    zero, 0x40(x3)
    sw    zero, 0x44(x3)
    sw    zero, 0x48(x3)
    sw    zero, 0x4C(x3)
    sw    zero, 0x50(x3)
    sw    zero, 0x54(x3)
    sw    zero, 0x58(x3)
    sw    zero, 0x5C(x3)
    sw    zero, 0x60(x3)
    sw    zero, 0x64(x3)
    sw    zero, 0x68(x3)
    sw    zero, 0x6C(x3)
    sw    zero, 0x70(x3)
    sw    zero, 0x74(x3)
    sw    zero, 0x78(x3)
    sw    zero, 0x7C(x3)

    # Start encryption
    li    x10, 1
    sw    x10, 0x30(x3)

    # Fixed delay (~500 iterations for 22-cycle core)
    li    x11, 500
t01_wait:
    addi  x11, x11, -1
    bne   x11, zero, t01_wait

    # Read ciphertext[0] — expect 0xade0b876
    lw    x12, 0x80(x3)
    # Build 0xADE0B876: 0x876 >= 0x800, sign-extends
    # lui 0xADE0C, addi -0x78A (-1930) → 0xADE0C000 - 0x78A = 0xADE0B876
    lui   x13, 0xADE0C
    addi  x13, x13, -1930
    bne   x12, x13, fail

    addi  x4, x4, 1        # pass++

# =====================================================================
# T02: ChaCha20 back-to-back — counter auto-incremented to 1
# RFC 8439 A.1 TV#2: key=0, nonce=0, counter=1 → keystream[0] = 0xbee7079f
# =====================================================================
t02:
    li    x10, 0x02
    sw    x10, 0(x1)       # LEDR = 0x02

    # Key/nonce/plaintext still 0. Counter auto-incremented to 1 by T01.
    # Just start again
    li    x10, 1
    sw    x10, 0x30(x3)

    li    x11, 500
t02_wait:
    addi  x11, x11, -1
    bne   x11, zero, t02_wait

    # Check ciphertext[0] = 0xBEE7079F
    # 0x79F < 0x800, no sign issue
    # lui 0xBEE70, addi 0x79F (1951)
    lw    x12, 0x80(x3)
    lui   x13, 0xBEE70
    addi  x13, x13, 1951
    bne   x12, x13, fail

    addi  x4, x4, 1        # pass++

# =====================================================================
# T03: ChaCha20 IRQ W1C test
# After T02, IRQ_STATUS[0] should be 1. Clear it and verify.
# =====================================================================
t03:
    li    x10, 0x03
    sw    x10, 0(x1)       # LEDR = 0x03

    # Read IRQ_STATUS (0x38) — should have bit[0]=1
    lw    x12, 0x38(x3)
    andi  x12, x12, 1
    beq   x12, zero, fail  # IRQ should be set!

    # W1C: write 1 to bit[0] to clear
    li    x10, 1
    sw    x10, 0x38(x3)

    # Small delay
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    # Read IRQ_STATUS again — should be 0
    lw    x12, 0x38(x3)
    andi  x12, x12, 1
    bne   x12, zero, fail  # IRQ should be clear now!

    addi  x4, x4, 1        # pass++

# =====================================================================
# T04: Write to read-only CIPHERTEXT (should be ignored)
# =====================================================================
t04:
    li    x10, 0x04
    sw    x10, 0(x1)       # LEDR = 0x04

    lw    x12, 0x80(x3)    # Read current CTEXT[0]

    # Write different value to CTEXT[0]
    lui   x13, 0xDEADC
    addi  x13, x13, -273   # 0xDEADBEEF
    sw    x13, 0x80(x3)    # Try to write (should be ignored)

    nop
    nop
    nop
    nop

    lw    x14, 0x80(x3)    # Read CTEXT[0] again
    bne   x12, x14, fail   # Should be unchanged!

    addi  x4, x4, 1        # pass++

# =====================================================================
# T05: DMA CH0 basic — copy 4 words from 0x2000 to 0x3000
# =====================================================================
t05:
    li    x10, 0x05
    sw    x10, 0(x1)       # LEDR = 0x05

    # Init source data at 0x2000
    li    x10, 0x2000
    li    x11, 0x11111111
    sw    x11, 0(x10)
    li    x11, 0x22222222
    sw    x11, 4(x10)
    li    x11, 0x33333333
    sw    x11, 8(x10)
    li    x11, 0x44444444
    sw    x11, 12(x10)

    # Clear destination at 0x3000
    li    x10, 0x3000
    sw    zero, 0(x10)
    sw    zero, 4(x10)
    sw    zero, 8(x10)
    sw    zero, 12(x10)

    # Configure DMA CH0
    li    x10, 0x2000
    sw    x10, 0x08(x6)    # CH0_SRC_ADDR = 0x2000
    li    x10, 0x3000
    sw    x10, 0x0C(x6)    # CH0_DST_ADDR = 0x3000
    li    x10, 4
    sw    x10, 0x10(x6)    # CH0_XFER_CNT = 4
    li    x10, 7            # enable=1, src_inc=1, dst_inc=1
    sw    x10, 0x00(x6)    # CH0_CONTROL

    # Wait for completion
    li    x11, 2000
t05_wait:
    addi  x11, x11, -1
    bne   x11, zero, t05_wait

    # Verify destination
    li    x10, 0x3000
    lw    x11, 0(x10)
    li    x12, 0x11111111
    bne   x11, x12, fail
    lw    x11, 4(x10)
    li    x12, 0x22222222
    bne   x11, x12, fail
    lw    x11, 8(x10)
    li    x12, 0x33333333
    bne   x11, x12, fail
    lw    x11, 12(x10)
    li    x12, 0x44444444
    bne   x11, x12, fail

    addi  x4, x4, 1        # pass++

# =====================================================================
# T06: DMA CH1 basic — copy 4 words from 0x2000 to 0x4000
# First-ever exercise of Channel 1
# =====================================================================
t06:
    li    x10, 0x06
    sw    x10, 0(x1)       # LEDR = 0x06

    # Clear destination at 0x4000
    li    x10, 0x4000
    sw    zero, 0(x10)
    sw    zero, 4(x10)
    sw    zero, 8(x10)
    sw    zero, 12(x10)

    # Configure DMA CH1
    li    x10, 0x2000
    sw    x10, 0x28(x6)    # CH1_SRC_ADDR = 0x2000
    li    x10, 0x4000
    sw    x10, 0x2C(x6)    # CH1_DST_ADDR = 0x4000
    li    x10, 4
    sw    x10, 0x30(x6)    # CH1_XFER_CNT = 4
    li    x10, 7            # enable=1, src_inc=1, dst_inc=1
    sw    x10, 0x20(x6)    # CH1_CONTROL

    li    x11, 2000
t06_wait:
    addi  x11, x11, -1
    bne   x11, zero, t06_wait

    # Verify
    li    x10, 0x4000
    lw    x11, 0(x10)
    li    x12, 0x11111111
    bne   x11, x12, fail
    lw    x11, 4(x10)
    li    x12, 0x22222222
    bne   x11, x12, fail
    lw    x11, 8(x10)
    li    x12, 0x33333333
    bne   x11, x12, fail
    lw    x11, 12(x10)
    li    x12, 0x44444444
    bne   x11, x12, fail

    addi  x4, x4, 1        # pass++

# =====================================================================
# T07: DMA FIFO mode — dst_inc=0 (fixed destination)
# Copy 4 words from 0x2000 to fixed address 0x5000
# CTRL = enable(1) | src_inc(1) | dst_inc(0) = 0x03
# =====================================================================
t07:
    li    x10, 0x07
    sw    x10, 0(x1)       # LEDR = 0x07

    # Clear destination
    li    x10, 0x5000
    sw    zero, 0(x10)

    # Configure CH0: src=0x2000, dst=0x5000, count=4, src_inc=1, dst_inc=0
    li    x10, 0x2000
    sw    x10, 0x08(x6)    # CH0_SRC_ADDR
    li    x10, 0x5000
    sw    x10, 0x0C(x6)    # CH0_DST_ADDR
    li    x10, 4
    sw    x10, 0x10(x6)    # CH0_XFER_CNT = 4
    li    x10, 3            # enable=1, src_inc=1, dst_inc=0
    sw    x10, 0x00(x6)    # CH0_CONTROL

    li    x11, 2000
t07_wait:
    addi  x11, x11, -1
    bne   x11, zero, t07_wait

    # Only last word should be at 0x5000
    li    x10, 0x5000
    lw    x11, 0(x10)
    li    x12, 0x44444444   # Last of {0x1111, 0x2222, 0x3333, 0x4444}
    bne   x11, x12, fail

    addi  x4, x4, 1        # pass++

# =====================================================================
# T08: DMA zero-count transfer
# Configure count=0, should complete without moving data.
# =====================================================================
t08:
    li    x10, 0x08
    sw    x10, 0(x1)       # LEDR = 0x08

    # Write sentinel to 0x6000
    li    x10, 0x6000
    li    x11, 0x12345678
    sw    x11, 0(x10)

    # Configure: src=0x2000, dst=0x6000, count=0
    li    x10, 0x2000
    sw    x10, 0x08(x6)    # CH0_SRC_ADDR
    li    x10, 0x6000
    sw    x10, 0x0C(x6)    # CH0_DST_ADDR
    sw    zero, 0x10(x6)   # CH0_XFER_CNT = 0
    li    x10, 7            # enable=1, src_inc=1, dst_inc=1
    sw    x10, 0x00(x6)    # CH0_CONTROL

    li    x11, 500
t08_wait:
    addi  x11, x11, -1
    bne   x11, zero, t08_wait

    # Sentinel should be unchanged
    li    x10, 0x6000
    lw    x11, 0(x10)
    li    x12, 0x12345678
    bne   x11, x12, fail

    addi  x4, x4, 1        # pass++

# =====================================================================
# T09: DMA CH0+CH1 concurrent transfers
# CH0: 0x2000 to 0x7000 (4 words), CH1: 0x2800 to 0x7800 (4 words)
# =====================================================================
t09:
    li    x10, 0x09
    sw    x10, 0(x1)       # LEDR = 0x09

    # Init source for CH1 at 0x2800
    li    x10, 0x2800
    li    x11, 0xAAAA0001
    sw    x11, 0(x10)
    li    x11, 0xAAAA0002
    sw    x11, 4(x10)
    li    x11, 0xAAAA0003
    sw    x11, 8(x10)
    li    x11, 0xAAAA0004
    sw    x11, 12(x10)

    # Explicitly disable both channels first (T08 zero-count leaves CH0 enabled)
    sw    zero, 0x00(x6)    # CH0_CONTROL = 0 (disable)
    sw    zero, 0x20(x6)    # CH1_CONTROL = 0 (disable)

    # Clear both destinations
    li    x10, 0x7000
    sw    zero, 0(x10)
    sw    zero, 4(x10)
    sw    zero, 8(x10)
    sw    zero, 12(x10)
    li    x10, 0x7800
    sw    zero, 0(x10)
    sw    zero, 4(x10)
    sw    zero, 8(x10)
    sw    zero, 12(x10)

    # Configure CH0: 0x2000 to 0x7000, count=4
    li    x10, 0x2000
    sw    x10, 0x08(x6)    # CH0_SRC
    li    x10, 0x7000
    sw    x10, 0x0C(x6)    # CH0_DST
    li    x10, 4
    sw    x10, 0x10(x6)    # CH0_CNT

    # Configure CH1: 0x2800 to 0x7800, count=4
    li    x10, 0x2800
    sw    x10, 0x28(x6)    # CH1_SRC
    li    x10, 0x7800
    sw    x10, 0x2C(x6)    # CH1_DST
    li    x10, 4
    sw    x10, 0x30(x6)    # CH1_CNT

    # Enable BOTH channels back-to-back
    li    x10, 7            # enable + both increments
    sw    x10, 0x00(x6)    # CH0
    sw    x10, 0x20(x6)    # CH1

    li    x11, 4000
t09_wait:
    addi  x11, x11, -1
    bne   x11, zero, t09_wait

    # Verify CH0 destination
    li    x10, 0x7000
    lw    x11, 0(x10)
    li    x12, 0x11111111
    bne   x11, x12, fail
    lw    x11, 12(x10)
    li    x12, 0x44444444
    bne   x11, x12, fail

    # Verify CH1 destination
    li    x10, 0x7800
    lw    x11, 0(x10)
    li    x12, 0xAAAA0001
    bne   x11, x12, fail
    lw    x11, 12(x10)
    li    x12, 0xAAAA0004
    bne   x11, x12, fail

    addi  x4, x4, 1        # pass++

# =====================================================================
# T10: DMA to ChaCha20 MMIO
# DMA copies 16-word plaintext from MEM to ChaCha20 PTEXT registers
# Then CPU triggers encryption and verifies ciphertext
# =====================================================================
t10:
    li    x10, 0x0A
    sw    x10, 0(x1)       # LEDR = 0x0A

    # Write plaintext pattern to memory at 0x2000: word[i] = i+1
    li    x10, 0x2000
    li    x11, 1
    sw    x11, 0(x10)
    li    x11, 2
    sw    x11, 4(x10)
    li    x11, 3
    sw    x11, 8(x10)
    li    x11, 4
    sw    x11, 12(x10)
    li    x11, 5
    sw    x11, 16(x10)
    li    x11, 6
    sw    x11, 20(x10)
    li    x11, 7
    sw    x11, 24(x10)
    li    x11, 8
    sw    x11, 28(x10)
    li    x11, 9
    sw    x11, 32(x10)
    li    x11, 10
    sw    x11, 36(x10)
    li    x11, 11
    sw    x11, 40(x10)
    li    x11, 12
    sw    x11, 44(x10)
    li    x11, 13
    sw    x11, 48(x10)
    li    x11, 14
    sw    x11, 52(x10)
    li    x11, 15
    sw    x11, 56(x10)
    li    x11, 16
    sw    x11, 60(x10)

    # Reset ChaCha20 key/nonce/counter to 0
    sw    zero, 0x00(x3)
    sw    zero, 0x04(x3)
    sw    zero, 0x08(x3)
    sw    zero, 0x0C(x3)
    sw    zero, 0x10(x3)
    sw    zero, 0x14(x3)
    sw    zero, 0x18(x3)
    sw    zero, 0x1C(x3)
    sw    zero, 0x20(x3)
    sw    zero, 0x24(x3)
    sw    zero, 0x28(x3)
    sw    zero, 0x2C(x3)   # counter = 0

    # DMA CH0: copy 16 words from 0x2000 to ChaCha20 PTEXT (0x1006_0040)
    li    x10, 0x2000
    sw    x10, 0x08(x6)    # CH0_SRC_ADDR
    lui   x10, 0x10060     # 0x10060000
    addi  x10, x10, 0x40   # 0x10060040
    sw    x10, 0x0C(x6)    # CH0_DST_ADDR
    li    x10, 16
    sw    x10, 0x10(x6)    # CH0_XFER_CNT = 16
    li    x10, 7            # enable + both increments
    sw    x10, 0x00(x6)    # CH0_CONTROL

    # Wait for DMA
    li    x11, 8000
t10_dma_wait:
    addi  x11, x11, -1
    bne   x11, zero, t10_dma_wait

    # Verify PTEXT[0]=1 and PTEXT[15]=16
    lw    x12, 0x40(x3)
    li    x13, 1
    bne   x12, x13, fail
    lw    x12, 0x7C(x3)
    li    x13, 16
    bne   x12, x13, fail

    # Start ChaCha20 encryption
    li    x10, 1
    sw    x10, 0x30(x3)

    li    x11, 500
t10_chacha_wait:
    addi  x11, x11, -1
    bne   x11, zero, t10_chacha_wait

    # CTEXT[0] = PTEXT[0] XOR keystream[0]
    # keystream[0] for key=0 nonce=0 counter=0 = 0xade0b876
    # CTEXT[0] = 1 ^ 0xade0b876 = 0xade0b877
    lw    x12, 0x80(x3)
    lui   x13, 0xADE0C
    addi  x13, x13, -1929   # 0xADE0B877
    bne   x12, x13, fail

    addi  x4, x4, 1        # pass++

# =====================================================================
# ALL DONE — check total passes
# =====================================================================
done:
    bne   x4, x5, fail     # if pass_count != 10, fail

    li    x10, 0xAA
    sw    x10, 0(x1)       # LEDR = 0xAA → ALL PASS
    j     halt

fail:
    # Write pass count to LEDG FIRST (before TB detects LEDR change)
    sw    x4, 4(x1)
    # Small delay so LEDG propagates before LEDR changes
    nop
    nop
    nop
    nop
    li    x10, 0xFF
    sw    x10, 0(x1)       # LEDR = 0xFF → FAIL

halt:
    j     halt
