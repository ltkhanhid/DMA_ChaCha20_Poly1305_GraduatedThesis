# ============================================================
# dma_test.S — DMA Integration Test for SoC (RV32I bare-metal)
#
# Test sequence:
#   1. Initialize 100 words in DMEM at 0x1000 (pattern: 0x100+i)
#   2. CPU memcpy: 0x1000 -> 0x2000 (100 words, lw/sw loop)
#   3. DMA memcpy: 0x1000 -> 0x3000 (100 words, through TL-UL bus)
#   4. Verify both copies match source
#   5. Report results via LEDR and HEX
#
# LEDR phase markers:
#   0x01 = Init source data
#   0x02 = CPU copy start
#   0x03 = CPU copy done
#   0x04 = DMA start (configure registers)
#   0x05 = DMA done
#   0x06 = Verification start
#   0xAA = ALL PASS
#   0xFF = FAIL
#
# Memory map:
#   0x0000_0000 : DMEM (BRAM via TileLink)
#   0x1000_0000 : LEDR
#   0x1000_2000 : HEX 3-0
#   0x1000_3000 : HEX 7-4
#   0x1005_0000 : DMA_CH0_CONTROL  [0]=en [1]=src_inc [2]=dst_inc
#   0x1005_0004 : DMA_CH0_STATUS   [0]=busy [1]=done [2]=error
#   0x1005_0008 : DMA_CH0_SRC_ADDR
#   0x1005_000C : DMA_CH0_DST_ADDR
#   0x1005_0010 : DMA_CH0_XFER_CNT
#   0x1005_0040 : DMA_IRQ_STATUS   [0]=ch0 [1]=ch1
#
# Build:
#   riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
#       -nostartfiles -T dma_link.ld -o dma_test.elf dma_test.S
#   python elf2hex.py dma_test.elf dma_test.hex
# ============================================================

    .section .text
    .globl _start

_start:
    # --- Setup ---
    lui   sp, 1              # sp = 0x1000
    addi  sp, sp, -16        # sp = 0x0FF0
    lui   a5, 0x10000        # a5 = 0x10000000 (LEDR base, kept always)

    # ====== Phase 1: Init source data at DMEM 0x1000 ======
    addi  t0, zero, 1
    sw    t0, 0(a5)          # LEDR = 0x01

    lui   t0, 1              # t0 = 0x1000 (source base)
    addi  t1, zero, 100      # t1 = 100 (word count)
    addi  t2, zero, 0x100    # t2 = starting pattern (0x100)
.L_init:
    sw    t2, 0(t0)
    addi  t0, t0, 4
    addi  t2, t2, 1
    addi  t1, t1, -1
    bne   t1, zero, .L_init

    # ====== Phase 2: CPU memcpy (100 words: 0x1000 -> 0x2000) ======
    addi  t0, zero, 2
    sw    t0, 0(a5)          # LEDR = 0x02

    lui   a0, 1              # a0 = 0x1000 (src)
    lui   a1, 2              # a1 = 0x2000 (dst)
    addi  a2, zero, 100      # a2 = 100 (count)
.L_cpu_copy:
    lw    t3, 0(a0)
    sw    t3, 0(a1)
    addi  a0, a0, 4
    addi  a1, a1, 4
    addi  a2, a2, -1
    bne   a2, zero, .L_cpu_copy

    addi  t0, zero, 3
    sw    t0, 0(a5)          # LEDR = 0x03

    # ====== Phase 3: DMA memcpy (100 words: 0x1000 -> 0x3000) ======
    addi  t0, zero, 4
    sw    t0, 0(a5)          # LEDR = 0x04

    lui   s0, 0x10050        # s0 = 0x10050000 (DMA_BASE)

    lui   t1, 1              # t1 = 0x1000
    sw    t1, 8(s0)          # DMA_CH0_SRC_ADDR = 0x1000

    lui   t1, 3              # t1 = 0x3000
    sw    t1, 12(s0)         # DMA_CH0_DST_ADDR = 0x3000

    addi  t1, zero, 100
    sw    t1, 16(s0)         # DMA_CH0_XFER_CNT = 100

    addi  t1, zero, 7       # enable=1, src_inc=1, dst_inc=1
    sw    t1, 0(s0)          # DMA_CH0_CONTROL = 7 -> START!

.L_dma_poll:
    lw    t1, 4(s0)          # Read DMA_CH0_STATUS
    andi  t1, t1, 1          # bit[0] = busy
    bne   t1, zero, .L_dma_poll

    addi  t0, zero, 5
    sw    t0, 0(a5)          # LEDR = 0x05

    # Clear DMA IRQ
    addi  t1, zero, 1
    sw    t1, 64(s0)         # DMA_IRQ_STATUS W1C bit0

    # ====== Phase 4: Verify ======
    addi  t0, zero, 6
    sw    t0, 0(a5)          # LEDR = 0x06

    # -- Verify CPU copy (0x1000 vs 0x2000) --
    lui   a0, 1              # src = 0x1000
    lui   a1, 2              # cpu_dst = 0x2000
    addi  a2, zero, 100
    addi  a3, zero, 0        # CPU mismatch count
.L_verify_cpu:
    lw    t3, 0(a0)
    lw    t4, 0(a1)
    beq   t3, t4, .L_cpu_ok
    addi  a3, a3, 1
.L_cpu_ok:
    addi  a0, a0, 4
    addi  a1, a1, 4
    addi  a2, a2, -1
    bne   a2, zero, .L_verify_cpu

    # -- Verify DMA copy (0x1000 vs 0x3000) --
    lui   a0, 1              # src = 0x1000
    lui   a1, 3              # dma_dst = 0x3000
    addi  a2, zero, 100
    addi  a4, zero, 0        # DMA mismatch count
.L_verify_dma:
    lw    t3, 0(a0)
    lw    t4, 0(a1)
    beq   t3, t4, .L_dma_ok
    addi  a4, a4, 1
.L_dma_ok:
    addi  a0, a0, 4
    addi  a1, a1, 4
    addi  a2, a2, -1
    bne   a2, zero, .L_verify_dma

    # ====== Report results ======
    lui   t0, 0x10002        # HEX 3-0 base = 0x10002000
    sw    a3, 0(t0)          # HEX 3-0 = CPU error count

    lui   t0, 0x10003        # HEX 7-4 base = 0x10003000
    sw    a4, 0(t0)          # HEX 7-4 = DMA error count

    or    t1, a3, a4         # Any errors?
    bne   t1, zero, .L_fail

    addi  t0, zero, 0xAA     # 0xAA = PASS marker
    sw    t0, 0(a5)          # LEDR = 0xAA
    j     .L_end

.L_fail:
    addi  t0, zero, 0xFF     # 0xFF = FAIL marker
    sw    t0, 0(a5)          # LEDR = 0xFF

.L_end:
    ebreak
    j     .L_end             # Infinite loop safety
