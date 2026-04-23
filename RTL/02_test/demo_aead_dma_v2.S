# ============================================================
# demo_aead_dma_v2.S — AEAD DMA Demo with Interactive 7-Seg Display
#
# Based on demo_aead_dma.S (Phases 1-6 identical).
# Phase 7 replaced: instead of static "AEAD" hex display,
# an interactive idle loop reads SW[1:0] to select display mode:
#
#   SW=00 : " PASS " on 7-seg (raw segment mode, centered)
#   SW=01 : First 6 plaintext ASCII chars on 7-seg (raw segment)
#   SW=10 : Running hex counter (hex decoder mode)
#   SW=11 : Legacy 0xAEAD display (hex decoder mode)
#
# Requires peripherals.sv with raw segment registers:
#   SEG_RAW_LO  = 0x1000_5000  (HEX3..HEX0, 7-bit per byte)
#   SEG_RAW_HI  = 0x1000_6000  (HEX5..HEX4, 7-bit per byte)
#   SEG_MODE    = 0x1000_7000  (bit0: 0=hex-decoded, 1=raw)
#
# All 7-seg patterns are ACTIVE-LOW (0=ON, 1=OFF), format gfedcba.
#
# Press KEY[0] (hardware reset) to restart the firmware.
#
# AEAD Parameters (RFC 8439 §2.8.2) — unchanged:
#   Key   : 80 81 82 83 ... 9c 9d 9e 9f  (32 bytes)
#   Nonce : 07 00 00 00 40 41 42 43 44 45 46 47  (12 bytes)
#   AAD   : 50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7  (12 bytes)
#
# Memory layout:
#   0x0000_2000 : Plaintext buffer  (64 bytes)
#   0x0000_2040 : Ciphertext buffer (64 bytes)
#   0x0000_2080 : Tag buffer        (16 bytes)
#   0x0000_2100 : ASCII→7seg lookup table (96 bytes, runtime init)
#
# Peripheral addresses:
#   RED_LED   : 0x1000_0000
#   HEX_LO    : 0x1000_2000
#   HEX_HI    : 0x1000_3000
#   SEG_RAW_LO: 0x1000_5000
#   SEG_RAW_HI: 0x1000_6000
#   SEG_MODE  : 0x1000_7000
#   SW_READ   : 0x1001_0000
#   UART      : 0x1002_0000
#   DMA       : 0x1005_0000
#   ChaCha20  : 0x1006_0000
#   Poly1305  : 0x1007_0000
# ============================================================

    .section .text
    .globl _start

_start:
    # ===== Setup base addresses =====
    lui   s0, 0x10002        # s0 = 0x10002000 (HEX_LO)
    lui   s1, 0x10003        # s1 = 0x10003000 (HEX_HI)
    lui   s2, 0x10020        # s2 = 0x10020000 (UART)
    lui   s5, 0x10060        # s5 = 0x10060000 (ChaCha20)
    lui   s6, 0x10070        # s6 = 0x10070000 (Poly1305)
    lui   s8, 0x10050        # s8 = 0x10050000 (DMA)

    sw    zero, 0(s0)
    sw    zero, 0(s1)

    # ============================================================
    # Phase 1: UART RX — Receive 64 bytes of plaintext
    # ============================================================
    li    t0, 1
    sw    t0, 0(s0)          # HEX_LO = 1

    li    s3, 0x00002000     # plaintext buffer
    li    s4, 64             # bytes remaining
    li    s7, 64             # constant for display

.rx_loop:
    lw    t0, 4(s2)          # UART RX (bit[31]=valid, [7:0]=data)
    srli  t1, t0, 31
    beqz  t1, .rx_loop

    sb    t0, 0(s3)
    addi  s3, s3, 1
    addi  s4, s4, -1

    sub   t2, s7, s4
    sw    t2, 0(s1)          # HEX_HI = bytes received

    bnez  s4, .rx_loop

    # ============================================================
    # Phase 2: Configure ChaCha20 + OTK Generation (counter=0)
    # ============================================================
    li    t0, 2
    sw    t0, 0(s0)
    sw    zero, 0(s1)

    # --- Set Key (32 bytes, 8 LE words) ---
    li    t0, 0x83828180
    sw    t0, 0x00(s5)       # KEY[0]
    li    t0, 0x87868584
    sw    t0, 0x04(s5)       # KEY[1]
    li    t0, 0x8b8a8988
    sw    t0, 0x08(s5)       # KEY[2]
    li    t0, 0x8f8e8d8c
    sw    t0, 0x0C(s5)       # KEY[3]
    li    t0, 0x93929190
    sw    t0, 0x10(s5)       # KEY[4]
    li    t0, 0x97969594
    sw    t0, 0x14(s5)       # KEY[5]
    li    t0, 0x9b9a9998
    sw    t0, 0x18(s5)       # KEY[6]
    li    t0, 0x9f9e9d9c
    sw    t0, 0x1C(s5)       # KEY[7]

    # --- Set Nonce (12 bytes, 3 LE words) ---
    li    t0, 0x00000007
    sw    t0, 0x20(s5)       # NONCE[0]
    li    t0, 0x43424140
    sw    t0, 0x24(s5)       # NONCE[1]
    li    t0, 0x47464544
    sw    t0, 0x28(s5)       # NONCE[2]

    # --- Counter = 0 ---
    sw    zero, 0x2C(s5)

    # --- Clear ChaCha20 IRQ, trigger ---
    li    t0, 1
    sw    t0, 0x38(s5)       # W1C clear IRQ
    li    t0, 1
    sw    t0, 0x30(s5)       # CONTROL = start

    # --- Poll ChaCha20 IRQ until done ---
.wait_otk:
    lw    t0, 0x38(s5)       # IRQ_STATUS
    andi  t0, t0, 1
    beqz  t0, .wait_otk

    # ============================================================
    # Phase 3: Init Poly1305 with OTK — DMA CH0+CH1 PARALLEL
    # ============================================================
    li    t0, 3
    sw    t0, 0(s0)

    # --- DMA CH0: ChaCha20 CTEXT[0..3] → Poly1305 KEY_R ---
    li    t0, 0x10060080     # ChaCha20 CTEXT base
    sw    t0, 0x08(s8)       # CH0_SRC_ADDR
    li    t0, 0x10070000     # Poly1305 KEY_R base
    sw    t0, 0x0C(s8)       # CH0_DST_ADDR
    li    t0, 4
    sw    t0, 0x10(s8)       # CH0_XFER_CNT = 4

    # --- DMA CH1: ChaCha20 CTEXT[4..7] → Poly1305 KEY_S ---
    li    t0, 0x10060090     # CTEXT word[4] = 0x80 + 4*4
    sw    t0, 0x28(s8)       # CH1_SRC_ADDR
    li    t0, 0x10070010     # Poly1305 KEY_S base
    sw    t0, 0x2C(s8)       # CH1_DST_ADDR
    li    t0, 4
    sw    t0, 0x30(s8)       # CH1_XFER_CNT = 4

    # --- Clear DMA IRQ, start both channels simultaneously ---
    li    t0, 3              # W1C bits [1:0]
    sw    t0, 0x40(s8)       # DMA_IRQ_STATUS
    li    t0, 7              # [0]=enable [1]=src_inc [2]=dst_inc
    sw    t0, 0x00(s8)       # CH0 start
    sw    t0, 0x20(s8)       # CH1 start

    # --- Poll until BOTH channels done (IRQ bits [1:0] = 0b11) ---
.wait_dma_otk:
    lw    t0, 0x40(s8)       # DMA_IRQ_STATUS
    andi  t0, t0, 3          # mask bits [1:0]
    li    t1, 3
    bne   t0, t1, .wait_dma_otk

    # --- Pulse Poly1305 init ---
    li    t0, 1
    sw    t0, 0x30(s6)       # CONTROL bit0 = init

    # ============================================================
    # Phase 4: ChaCha20 Encrypt — DMA for data movement
    # ============================================================
    li    t0, 4
    sw    t0, 0(s0)

    # Clear ChaCha20 IRQ from OTK phase
    li    t0, 1
    sw    t0, 0x38(s5)

    # --- Step A: DMA CH0 — PT buffer → ChaCha20 PTEXT ---
    li    t0, 0x00002000     # PT buffer (RAM)
    sw    t0, 0x08(s8)       # CH0_SRC_ADDR
    li    t0, 0x10060040     # ChaCha20 PTEXT base
    sw    t0, 0x0C(s8)       # CH0_DST_ADDR
    li    t0, 16
    sw    t0, 0x10(s8)       # CH0_XFER_CNT = 16 words (64 bytes)
    li    t0, 3
    sw    t0, 0x40(s8)       # Clear DMA IRQ
    li    t0, 7
    sw    t0, 0x00(s8)       # CH0 start — DMA RUNNING, CPU continues

    # =========================================================
    # OVERLAP A: While DMA copies PT→PTEXT, CPU processes
    # Poly1305 Block 1 (AAD). Zero dependency → genuine parallelism.
    # =========================================================

    li    t0, 0x53525150
    sw    t0, 0x20(s6)       # MSG[0] = AAD[3:0] LE
    li    t0, 0xc3c2c1c0
    sw    t0, 0x24(s6)       # MSG[1] = AAD[7:4] LE
    li    t0, 0xc7c6c5c4
    sw    t0, 0x28(s6)       # MSG[2] = AAD[11:8] LE
    sw    zero, 0x2C(s6)     # MSG[3] = 0 (pad)

    li    t0, 16
    sw    t0, 0x34(s6)       # BLOCK_LEN = 16
    li    t0, 1
    sw    t0, 0x3C(s6)       # Clear Poly IRQ
    li    t0, 2
    sw    t0, 0x30(s6)       # Trigger Block 1

.wait_poly_aad:
    lw    t0, 0x3C(s6)
    andi  t0, t0, 1
    beqz  t0, .wait_poly_aad

    # Poll DMA done
.wait_dma_ptext:
    lw    t0, 0x40(s8)
    andi  t0, t0, 1
    beqz  t0, .wait_dma_ptext

    # --- Step B: Trigger ChaCha20 (counter = 1 from auto-increment) ---
    li    t0, 1
    sw    t0, 0x30(s5)       # CONTROL = start

.wait_encrypt:
    lw    t0, 0x38(s5)       # ChaCha20 IRQ
    andi  t0, t0, 1
    beqz  t0, .wait_encrypt

    # --- Step C: DMA CH0 — ChaCha20 CTEXT → CT buffer ---
    li    t0, 0x10060080     # ChaCha20 CTEXT base
    sw    t0, 0x08(s8)       # CH0_SRC_ADDR
    li    t0, 0x00002040     # CT buffer (RAM)
    sw    t0, 0x0C(s8)       # CH0_DST_ADDR
    li    t0, 16
    sw    t0, 0x10(s8)       # CH0_XFER_CNT = 16 words (64 bytes)
    li    t0, 3
    sw    t0, 0x40(s8)       # Clear DMA IRQ
    li    t0, 7
    sw    t0, 0x00(s8)       # CH0 start

.wait_dma_ctext:
    lw    t0, 0x40(s8)
    andi  t0, t0, 1
    beqz  t0, .wait_dma_ctext

    # ============================================================
    # Phase 5: Poly1305 MAC — Pipelined DMA + Poly1305
    # ============================================================
    li    t0, 5
    sw    t0, 0(s0)

    # Pre-load loop-invariant constants
    li    a0, 0x10070020     # Poly1305 MSG base
    li    a1, 4              # XFER_CNT = 4 words
    li    a2, 7              # DMA CONTROL = enable+src_inc+dst_inc
    li    a3, 3              # DMA IRQ W1C mask

    # ---- Block 2: CT[0..15] ----
    li    s3, 0x00002040
    sw    s3, 0x08(s8) ; sw a0, 0x0C(s8) ; sw a1, 0x10(s8)
    sw    a3, 0x40(s8) ; sw a2, 0x00(s8)   # Start DMA block 2
.wdb2: lw t0,0x40(s8); andi t0,t0,1; beqz t0,.wdb2
    li t0,16; sw t0,0x34(s6); li t0,1; sw t0,0x3C(s6)
    li t0,2;  sw t0,0x30(s6)              # Trigger Poly block 2

    # OVERLAP B: DMA block 3 runs while Poly block 2 computes
    addi  s3, s3, 16
    sw    s3, 0x08(s8) ; sw a0, 0x0C(s8) ; sw a1, 0x10(s8)
    sw    a3, 0x40(s8) ; sw a2, 0x00(s8)   # Start DMA block 3
.wpb2: lw t0,0x3C(s6); andi t0,t0,1; beqz t0,.wpb2  # Wait Poly b2
.wdb3: lw t0,0x40(s8); andi t0,t0,1; beqz t0,.wdb3  # Wait DMA  b3
    li t0,16; sw t0,0x34(s6); li t0,1; sw t0,0x3C(s6)
    li t0,2;  sw t0,0x30(s6)              # Trigger Poly block 3

    # OVERLAP B: DMA block 4 runs while Poly block 3 computes
    addi  s3, s3, 16
    sw    s3, 0x08(s8) ; sw a0, 0x0C(s8) ; sw a1, 0x10(s8)
    sw    a3, 0x40(s8) ; sw a2, 0x00(s8)   # Start DMA block 4
.wpb3: lw t0,0x3C(s6); andi t0,t0,1; beqz t0,.wpb3  # Wait Poly b3
.wdb4: lw t0,0x40(s8); andi t0,t0,1; beqz t0,.wdb4  # Wait DMA  b4
    li t0,16; sw t0,0x34(s6); li t0,1; sw t0,0x3C(s6)
    li t0,2;  sw t0,0x30(s6)              # Trigger Poly block 4

    # OVERLAP B: DMA block 5 runs while Poly block 4 computes
    addi  s3, s3, 16
    sw    s3, 0x08(s8) ; sw a0, 0x0C(s8) ; sw a1, 0x10(s8)
    sw    a3, 0x40(s8) ; sw a2, 0x00(s8)   # Start DMA block 5
.wpb4: lw t0,0x3C(s6); andi t0,t0,1; beqz t0,.wpb4  # Wait Poly b4
.wdb5: lw t0,0x40(s8); andi t0,t0,1; beqz t0,.wdb5  # Wait DMA  b5
    li t0,16; sw t0,0x34(s6); li t0,1; sw t0,0x3C(s6)
    li t0,2;  sw t0,0x30(s6)              # Trigger Poly block 5
.wpb5: lw t0,0x3C(s6); andi t0,t0,1; beqz t0,.wpb5  # Wait Poly b5

    # ---- Block 6: Lengths (CPU direct write) ----
    li    t0, 12             # 0x0000000C
    sw    t0, 0x20(s6)       # MSG[0] = aad_len low
    sw    zero, 0x24(s6)     # MSG[1] = aad_len high
    li    t0, 64             # 0x00000040
    sw    t0, 0x28(s6)       # MSG[2] = ct_len low
    sw    zero, 0x2C(s6)     # MSG[3] = ct_len high

    li    t0, 16
    sw    t0, 0x34(s6)       # BLOCK_LEN = 16
    li    t0, 1
    sw    t0, 0x3C(s6)
    li    t0, 2
    sw    t0, 0x30(s6)

.wait_poly_len:
    lw    t0, 0x3C(s6)
    andi  t0, t0, 1
    beqz  t0, .wait_poly_len

    # ---- Finalize: compute tag ----
    li    t0, 1
    sw    t0, 0x3C(s6)       # Clear IRQ
    li    t0, 4              # bit2 = finalize
    sw    t0, 0x30(s6)

.wait_poly_final:
    lw    t0, 0x3C(s6)
    andi  t0, t0, 1
    beqz  t0, .wait_poly_final

    # ---- Read TAG[0..3] → tag buffer ----
    li    a0, 0x00002080
    lw    t0, 0x40(s6)       # TAG[0]
    sw    t0, 0(a0)
    lw    t0, 0x44(s6)       # TAG[1]
    sw    t0, 4(a0)
    lw    t0, 0x48(s6)       # TAG[2]
    sw    t0, 8(a0)
    lw    t0, 0x4C(s6)       # TAG[3]
    sw    t0, 12(a0)

    # ============================================================
    # Phase 6: UART TX — DMA burst 80 bytes via TX_FIFO_WORD
    # ============================================================
    li    t0, 6
    sw    t0, 0(s0)
    sw    zero, 0(s1)

    # DMA CH0: CT+TAG buffer → UART TX_FIFO_WORD
    li    t0, 0x00002040     # src = CT buffer (contiguous CT+TAG)
    sw    t0, 0x08(s8)       # CH0_SRC_ADDR
    li    t0, 0x1002000C     # dst = UART TX_FIFO_WORD register
    sw    t0, 0x0C(s8)       # CH0_DST_ADDR (fixed, no increment)
    li    t0, 20             # 20 words × 4 bytes = 80 bytes
    sw    t0, 0x10(s8)       # CH0_XFER_CNT
    li    t0, 3
    sw    t0, 0x40(s8)       # Clear DMA IRQ
    li    t0, 3              # enable + src_inc (NO dst_inc)
    sw    t0, 0x00(s8)       # CH0 start → DMA fills FIFO

    # Wait for DMA to finish filling FIFO
.wait_dma_tx:
    lw    t0, 0x40(s8)       # DMA IRQ_STATUS
    andi  t0, t0, 1
    beqz  t0, .wait_dma_tx

    # Update display
    li    t0, 80
    sw    t0, 0(s1)          # HEX_HI = 80 (all queued)

    # Wait for FIFO to fully drain
.tx_drain:
    lw    t0, 0(s2)          # bit[0] = tx_active
    andi  t0, t0, 1
    bnez  t0, .tx_drain

    # ============================================================
    # Phase 7: Interactive Display — switch-selectable modes
    #
    # SW=00 : " PASS " raw segment (centered 6 digits)
    # SW=01 : First 3 plaintext bytes as 6 hex digits
    #         HEX5..HEX4 = PT[2], HEX3..HEX2 = PT[1], HEX1..HEX0 = PT[0]
    # SW=10 : Running hex counter
    # SW=11 : 00AEAd (legacy, 2 left digits = 00)
    #
    # Registers:
    #   s0 = HEX_LO     (0x10002000, unchanged)
    #   s1 = HEX_HI     (0x10003000, unchanged)
    #   s2 = SEG_RAW_LO (0x10005000)
    #   s3 = SEG_RAW_HI (0x10006000)
    #   s4 = SEG_MODE   (0x10007000)
    #   s5 = SW_READ    (0x10010000)
    #   s6 = PT buffer  (0x00002000)
    #   s8 = counter    (for mode 10)
    # ============================================================
    lui   s2, 0x10005        # s2 = 0x10005000 (SEG_RAW_LO)
    lui   s3, 0x10006        # s3 = 0x10006000 (SEG_RAW_HI)
    lui   s4, 0x10007        # s4 = 0x10007000 (SEG_MODE)
    lui   s5, 0x10010        # s5 = 0x10010000 (SW_READ)
    li    s6, 0x00002000     # s6 = plaintext buffer
    li    s8, 0              # s8 = running counter

    # ---- Main idle loop: poll SW[1:0], branch to display mode ----
.idle_loop:
    lw    t0, 0(s5)          # t0 = SW register value
    andi  t0, t0, 3          # mask SW[1:0]

    beqz  t0, .mode_pass     # SW=00 → " PASS "
    li    t1, 1
    beq   t0, t1, .mode_ascii # SW=01 → first 3 PT bytes as hex
    li    t1, 2
    beq   t0, t1, .mode_count # SW=10 → running counter
    j     .mode_aead          # SW=11 → legacy AEAD

    # ---- Mode 00: Display " PASS " (centered on HEX5..HEX0) ----
    #   HEX5=' '  HEX4='P'  HEX3='A'  HEX2='S'  HEX1='S'  HEX0=' '
.mode_pass:
    li    t0, 1
    sw    t0, 0(s4)          # enable raw segment mode
    li    t0, 0x0812127F     # {A=0x08, S=0x12, S=0x12, ' '=0x7F}
    sw    t0, 0(s2)          # SEG_RAW_LO = HEX3..HEX0
    li    t0, 0x00007F0C     # {' '=0x7F, P=0x0C}
    sw    t0, 0(s3)          # SEG_RAW_HI = HEX5..HEX4
    j     .idle_loop

    # ---- Mode 01: First 3 plaintext bytes as 6 hex digits ----
    #   HEX5..HEX4 = PT[2]   HEX3..HEX2 = PT[1]   HEX1..HEX0 = PT[0]
    #   Uses hex decoder (no LUT) — always correct for any byte value
    #   Example RFC 8439 plaintext "Ladies...": PT[0]=4C PT[1]=61 PT[2]=64
    #     → displays  64 61 4C  (left to right)
.mode_ascii:
    sw    zero, 0(s4)        # disable raw mode (use hex decoder)
    lbu   t0, 0(s6)          # PT[0]
    lbu   t1, 1(s6)          # PT[1]
    slli  t1, t1, 8          # PT[1] → bits[15:8]
    or    t0, t0, t1         # t0 = (PT[1]<<8) | PT[0]
    sw    t0, 0(s0)          # HEX_LO → HEX3..HEX2=PT[1], HEX1..HEX0=PT[0]
    lbu   t0, 2(s6)          # PT[2]
    sw    t0, 0(s1)          # HEX_HI → HEX5..HEX4=PT[2], HEX7..HEX6=0
    j     .idle_loop

    # ---- Mode 10: Running hex counter ----
.mode_count:
    sw    zero, 0(s4)        # disable raw mode (hex decoder)
    addi  s8, s8, 1          # increment counter
    sw    s8, 0(s0)          # HEX_LO = counter[15:0]
    srli  t0, s8, 16
    sw    t0, 0(s1)          # HEX_HI = counter[31:16]
    # Delay ~0.2s at 50MHz (~10M cycles, ~2.5M loop iterations)
    li    t0, 2500000
.delay_cnt:
    addi  t0, t0, -1
    bnez  t0, .delay_cnt
    j     .idle_loop

    # ---- Mode 11: Legacy AEAD hex display ("00AEAd") ----
.mode_aead:
    sw    zero, 0(s4)        # disable raw mode (hex decoder)
    li    t0, 0x0000AEAD
    sw    t0, 0(s0)          # HEX_LO = 0xAEAD → HEX3='A' HEX2='E' HEX1='A' HEX0='d'
    sw    zero, 0(s1)        # HEX_HI = 0x0000 → HEX5='0' HEX4='0'
    j     .idle_loop
