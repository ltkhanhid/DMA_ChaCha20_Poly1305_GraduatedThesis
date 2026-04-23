# ============================================================
# demo_chacha.S — Full SoC Demo: UART → CPU → ChaCha20 → CPU → UART
#
# Demonstrates all key SoC peripherals working together:
#   Phase 1: UART RX — Receive 64 bytes of plaintext from host
#   Phase 2: CPU configures ChaCha20 key/nonce/counter (RFC 8439)
#   Phase 3: CPU copies plaintext buffer → ChaCha20 PLAINTEXT regs
#   Phase 4: ChaCha20 encryption triggered, wait until done
#   Phase 5: CPU copies ChaCha20 CIPHERTEXT → output buffer
#   Phase 6: UART TX — Send 64 encrypted bytes back to host
#   Phase 7: Done — display CAFE
#
# 7-Segment Display Status:
#   HEX_LO = Phase number (1-6, then 0xCAFE)
#   HEX_HI = Byte counter during UART RX/TX
#
# Memory layout:
#   0x0000_0000 : Code (instruction memory)
#   0x0000_2000 : Plaintext buffer  (64 bytes)
#   0x0000_2040 : Ciphertext buffer (64 bytes)
#
# ChaCha20 test vector (RFC 8439 §2.4.2):
#   Key   = 00:01:02:...:1e:1f (32 bytes)
#   Nonce = 00:00:00:00:00:00:00:4a:00:00:00:00 (12 bytes)
#   Counter = 1
#
# Build:
#   riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
#       -nostartfiles -T dma_link.ld -o demo_chacha.elf demo_chacha.S
#   python elf2hex.py demo_chacha.elf demo_chacha.hex
# ============================================================

    .section .text
    .globl _start

_start:
    # ===== Setup base addresses =====
    lui   s0, 0x10002        # s0 = 0x10002000 (HEX_LO)
    lui   s1, 0x10003        # s1 = 0x10003000 (HEX_HI)
    lui   s2, 0x10020        # s2 = 0x10020000 (UART)

    sw    zero, 0(s0)
    sw    zero, 0(s1)

    # ============================================================
    # Phase 1: UART RX — Receive 64 bytes of plaintext
    # ============================================================
    li    t0, 1
    sw    t0, 0(s0)          # HEX_LO = 1

    li    s3, 0x00002000     # plaintext buffer
    li    s4, 64             # bytes remaining
    li    s7, 64             # constant for display math

.rx_loop:
    lw    t0, 4(s2)          # Read UART RX (bit[31]=valid, [7:0]=data)
    srli  t1, t0, 31         # t1 = rx_valid
    beqz  t1, .rx_loop

    sb    t0, 0(s3)
    addi  s3, s3, 1
    addi  s4, s4, -1

    sub   t2, s7, s4
    sw    t2, 0(s1)          # HEX_HI = bytes received

    bnez  s4, .rx_loop

    # ============================================================
    # Phase 2: Configure ChaCha20 — RFC 8439 test vector
    # ============================================================
    li    t0, 2
    sw    t0, 0(s0)
    sw    zero, 0(s1)

    lui   s5, 0x10060        # s5 = ChaCha20 base

    li    t0, 0x03020100
    sw    t0, 0x00(s5)
    li    t0, 0x07060504
    sw    t0, 0x04(s5)
    li    t0, 0x0b0a0908
    sw    t0, 0x08(s5)
    li    t0, 0x0f0e0d0c
    sw    t0, 0x0C(s5)
    li    t0, 0x13121110
    sw    t0, 0x10(s5)
    li    t0, 0x17161514
    sw    t0, 0x14(s5)
    li    t0, 0x1b1a1918
    sw    t0, 0x18(s5)
    li    t0, 0x1f1e1d1c
    sw    t0, 0x1C(s5)

    sw    zero, 0x20(s5)     # NONCE[0]
    li    t0, 0x4a000000
    sw    t0, 0x24(s5)       # NONCE[1]
    sw    zero, 0x28(s5)     # NONCE[2]

    li    t0, 1
    sw    t0, 0x2C(s5)       # COUNTER = 1

    # ============================================================
    # Phase 3: CPU copy plaintext → ChaCha20 PLAINTEXT
    # ============================================================
    li    t0, 3
    sw    t0, 0(s0)

    li    t0, 0x00002000     # source
    addi  t1, s5, 0x40       # dest: ChaCha PTEXT base
    li    t2, 16
.copy_ptext:
    lw    t3, 0(t0)
    sw    t3, 0(t1)
    addi  t0, t0, 4
    addi  t1, t1, 4
    addi  t2, t2, -1
    bnez  t2, .copy_ptext

    # ============================================================
    # Phase 4: Trigger ChaCha20 + wait
    # ============================================================
    li    t0, 4
    sw    t0, 0(s0)

    # Clear any pending IRQ before triggering
    li    t0, 1
    sw    t0, 0x38(s5)       # W1C: clear IRQ

    li    t0, 1
    sw    t0, 0x30(s5)       # CONTROL = 1 (trigger)

    # Poll ChaCha20 IRQ register until done (IRQ bit[0] = 1)
.wait_chacha_irq:
    lw    t0, 0x38(s5)       # Read IRQ_STATUS
    andi  t0, t0, 1          # Check bit[0]
    beqz  t0, .wait_chacha_irq

    # ============================================================
    # Phase 5: CPU copy ChaCha20 CIPHERTEXT → output buffer
    # ============================================================
    li    t0, 5
    sw    t0, 0(s0)

    addi  t0, s5, 0x80       # source: ChaCha CTEXT base
    li    t1, 0x00002040     # dest
    li    t2, 16
.copy_ctext:
    lw    t3, 0(t0)
    sw    t3, 0(t1)
    addi  t0, t0, 4
    addi  t1, t1, 4
    addi  t2, t2, -1
    bnez  t2, .copy_ctext

    # Clear ChaCha20 IRQ
    li    t0, 1
    sw    t0, 0x38(s5)

    # ============================================================
    # Phase 6: UART TX — Send 64 ciphertext bytes
    # ============================================================
    li    t0, 6
    sw    t0, 0(s0)
    sw    zero, 0(s1)

    li    s3, 0x00002040     # ciphertext buffer
    li    s4, 64

.tx_loop:
    lw    t0, 0(s2)          # Read UART TX status
    andi  t0, t0, 1
    bnez  t0, .tx_loop       # Wait until not busy

    lbu   t0, 0(s3)          # Load ciphertext byte
    ori   t0, t0, 0x100      # Set send trigger (bit[8])
    sw    t0, 0(s2)          # Write to UART TX

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
    # Phase 7: DONE
    # ============================================================
    li    t0, 0x0000CAFE
    sw    t0, 0(s0)
    li    t0, 0x0000CAFE
    sw    t0, 0(s1)

.done:
    ebreak
    j     .done
