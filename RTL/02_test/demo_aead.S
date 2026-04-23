# ============================================================
# demo_aead.S — Full SoC AEAD Demo: ChaCha20-Poly1305 (RFC 8439 §2.8)
#
# Demonstrates the complete AEAD_CHACHA20_POLY1305 construction
# on the RISC-V SoC with hardware ChaCha20 and Poly1305 accelerators.
#
# AEAD Flow (RFC 8439 §2.8):
#   Phase 1: UART RX — Receive 64 bytes plaintext
#   Phase 2: OTK Generation — ChaCha20(key, nonce, counter=0)
#            PTEXT=0 → CTEXT = keystream → OTK r||s = CTEXT[0..7]
#   Phase 3: Init Poly1305 with OTK (r, s)
#   Phase 4: ChaCha20 Encrypt — counter=1 (auto-incremented)
#            Load plaintext → PTEXT, trigger → CTEXT = ciphertext
#   Phase 5: Poly1305 MAC computation
#            Block 1: AAD (12 bytes + 4 pad = 16)
#            Block 2-5: Ciphertext (64 bytes = 4 × 16)
#            Block 6: Lengths (len_aad=12, len_ct=64 as u64LE)
#            Finalize → Tag (16 bytes)
#   Phase 6: UART TX — Send 64 ciphertext + 16 tag = 80 bytes
#   Phase 7: Done — display 0xAEAD on 7-segment
#
# AEAD Parameters (RFC 8439 §2.8.2):
#   Key   : 80 81 82 83 ... 9c 9d 9e 9f  (32 bytes)
#   Nonce : 07 00 00 00 40 41 42 43 44 45 46 47  (12 bytes)
#   AAD   : 50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7  (12 bytes, hardcoded)
#
# Memory layout:
#   0x0000_2000 : Plaintext buffer  (64 bytes)
#   0x0000_2040 : Ciphertext buffer (64 bytes)
#   0x0000_2080 : Tag buffer        (16 bytes)
#
# Peripheral addresses:
#   HEX_LO   : 0x1000_2000
#   HEX_HI   : 0x1000_3000
#   UART      : 0x1002_0000
#   ChaCha20  : 0x1006_0000
#   Poly1305  : 0x1007_0000
#
# Build:
#   riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
#       -nostartfiles -T dma_link.ld -o demo_aead.elf demo_aead.S
#   python elf2hex.py demo_aead.elf demo_aead.hex
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
    #
    # Key   = {80,81,...,9f} → LE words
    # Nonce = {07,00,00,00, 40,41,42,43, 44,45,46,47}
    # PTEXT = 0 (default after reset)
    # After trigger: CTEXT = 0 XOR keystream = raw keystream
    # OTK r = CTEXT[0..3], OTK s = CTEXT[4..7]
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
    # Phase 3: Init Poly1305 with OTK
    #
    # Read ChaCha20 CTEXT[0..3] → Poly1305 KEY_R[0..3]
    # Read ChaCha20 CTEXT[4..7] → Poly1305 KEY_S[0..3]
    # Then pulse init
    # ============================================================
    li    t0, 3
    sw    t0, 0(s0)

    # Copy CTEXT[0..3] → KEY_R[0..3]   (r part of OTK)
    lw    t0, 0x80(s5)
    sw    t0, 0x00(s6)
    lw    t0, 0x84(s5)
    sw    t0, 0x04(s6)
    lw    t0, 0x88(s5)
    sw    t0, 0x08(s6)
    lw    t0, 0x8C(s5)
    sw    t0, 0x0C(s6)

    # Copy CTEXT[4..7] → KEY_S[0..3]   (s part of OTK)
    lw    t0, 0x90(s5)
    sw    t0, 0x10(s6)
    lw    t0, 0x94(s5)
    sw    t0, 0x14(s6)
    lw    t0, 0x98(s5)
    sw    t0, 0x18(s6)
    lw    t0, 0x9C(s5)
    sw    t0, 0x1C(s6)

    # Pulse Poly1305 init (CONTROL bit0)
    li    t0, 1
    sw    t0, 0x30(s6)       # init — instantaneous, no busy

    # ============================================================
    # Phase 4: ChaCha20 Encryption (counter = 1, auto-incremented)
    #
    # Copy plaintext buffer → ChaCha20 PTEXT registers
    # Trigger → CTEXT = plaintext XOR keystream(counter=1) = ciphertext
    # Copy CTEXT → ciphertext buffer
    # ============================================================
    li    t0, 4
    sw    t0, 0(s0)

    # Clear ChaCha20 IRQ from OTK phase
    li    t0, 1
    sw    t0, 0x38(s5)

    # Copy plaintext → PTEXT[0..15]
    li    t0, 0x00002000     # source: plaintext buffer
    addi  t1, s5, 0x40      # dest: PTEXT base (0x10060040)
    li    t2, 16             # 16 words = 64 bytes
.copy_ptext:
    lw    t3, 0(t0)
    sw    t3, 0(t1)
    addi  t0, t0, 4
    addi  t1, t1, 4
    addi  t2, t2, -1
    bnez  t2, .copy_ptext

    # Trigger ChaCha20 (counter = 1 from auto-increment)
    li    t0, 1
    sw    t0, 0x30(s5)

    # Poll ChaCha20 IRQ
.wait_encrypt:
    lw    t0, 0x38(s5)
    andi  t0, t0, 1
    beqz  t0, .wait_encrypt

    # Copy CTEXT[0..15] → ciphertext buffer
    addi  t0, s5, 0x80      # source: CTEXT base
    li    t1, 0x00002040     # dest: ciphertext buffer
    li    t2, 16
.copy_ctext:
    lw    t3, 0(t0)
    sw    t3, 0(t1)
    addi  t0, t0, 4
    addi  t1, t1, 4
    addi  t2, t2, -1
    bnez  t2, .copy_ctext

    # ============================================================
    # Phase 5: Poly1305 MAC Computation
    #
    # mac_data = AAD(12) | pad(4) | CT(64) | len_aad(8LE) | len_ct(8LE)
    #          = 16 + 64 + 16 = 96 bytes = 6 Poly1305 blocks
    #
    # Block 1: AAD {50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7 00 00 00 00}
    # Block 2: CT[ 0..15]
    # Block 3: CT[16..31]
    # Block 4: CT[32..47]
    # Block 5: CT[48..63]
    # Block 6: {0c 00 00 00 00 00 00 00  40 00 00 00 00 00 00 00}
    # ============================================================
    li    t0, 5
    sw    t0, 0(s0)

    # ---- Block 1: AAD + padding ----
    li    t0, 0x53525150
    sw    t0, 0x20(s6)       # MSG[0]
    li    t0, 0xc3c2c1c0
    sw    t0, 0x24(s6)       # MSG[1]
    li    t0, 0xc7c6c5c4
    sw    t0, 0x28(s6)       # MSG[2]
    sw    zero, 0x2C(s6)     # MSG[3] = 0 (padding)

    li    t0, 16
    sw    t0, 0x34(s6)       # BLOCK_LEN = 16

    # Clear Poly IRQ, trigger block
    li    t0, 1
    sw    t0, 0x3C(s6)       # W1C clear IRQ
    li    t0, 2
    sw    t0, 0x30(s6)       # CONTROL bit1 = block

.wait_poly_aad:
    lw    t0, 0x3C(s6)       # IRQ_STATUS
    andi  t0, t0, 1
    beqz  t0, .wait_poly_aad

    # ---- Blocks 2-5: Ciphertext (4 × 16 bytes) ----
    li    s3, 0x00002040     # CT buffer base
    li    s4, 4              # 4 blocks

.mac_ct_loop:
    # Load 4 words from CT buffer → MSG[0..3]
    lw    t0, 0(s3)
    sw    t0, 0x20(s6)
    lw    t0, 4(s3)
    sw    t0, 0x24(s6)
    lw    t0, 8(s3)
    sw    t0, 0x28(s6)
    lw    t0, 12(s3)
    sw    t0, 0x2C(s6)

    li    t0, 16
    sw    t0, 0x34(s6)       # BLOCK_LEN = 16

    # Clear IRQ, trigger block
    li    t0, 1
    sw    t0, 0x3C(s6)
    li    t0, 2
    sw    t0, 0x30(s6)

.wait_poly_ct:
    lw    t0, 0x3C(s6)
    andi  t0, t0, 1
    beqz  t0, .wait_poly_ct

    addi  s3, s3, 16         # advance to next 16 bytes
    addi  s4, s4, -1
    bnez  s4, .mac_ct_loop

    # ---- Block 6: Lengths (len_aad=12, len_ct=64 as u64 LE) ----
    li    t0, 12             # 0x0000000C
    sw    t0, 0x20(s6)       # MSG[0] = aad_len low
    sw    zero, 0x24(s6)     # MSG[1] = aad_len high
    li    t0, 64             # 0x00000040
    sw    t0, 0x28(s6)       # MSG[2] = ct_len low
    sw    zero, 0x2C(s6)     # MSG[3] = ct_len high

    li    t0, 16
    sw    t0, 0x34(s6)       # BLOCK_LEN = 16

    # Clear IRQ, trigger block
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

    # ---- Read TAG[0..3] → tag buffer (0x2080) ----
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
    # Phase 6: UART TX — Send 80 bytes (64 CT + 16 TAG)
    # ============================================================
    li    t0, 6
    sw    t0, 0(s0)
    sw    zero, 0(s1)

    li    s3, 0x00002040     # start at ciphertext buffer (CT + TAG contiguous)
    li    s4, 80             # total bytes to send
    li    s7, 80

.tx_loop:
    lw    t0, 0(s2)          # UART TX status
    andi  t0, t0, 1
    bnez  t0, .tx_loop       # wait until not busy

    lbu   t0, 0(s3)
    ori   t0, t0, 0x100      # bit[8] = send trigger
    sw    t0, 0(s2)

    addi  s3, s3, 1
    addi  s4, s4, -1

    sub   t2, s7, s4
    sw    t2, 0(s1)          # HEX_HI = bytes sent

    bnez  s4, .tx_loop

.tx_drain:
    lw    t0, 0(s2)
    andi  t0, t0, 1
    bnez  t0, .tx_drain

    # ============================================================
    # Phase 7: Done — display 0xAEAD
    # ============================================================
    li    t0, 0x0000AEAD
    sw    t0, 0(s0)
    li    t0, 0x0000AEAD
    sw    t0, 0(s1)

.done:
    ebreak
    j     .done
