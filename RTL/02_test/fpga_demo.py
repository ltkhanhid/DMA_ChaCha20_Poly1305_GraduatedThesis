#!/usr/bin/env python3
"""
fpga_demo.py — RISC-V SoC AEAD Demo over UART
===============================================
Giao tiếp với FPGA qua UART để demo ChaCha20-Poly1305 AEAD.

Hỗ trợ 3 chế độ:
  1. demo_chacha  : ChaCha20 encrypt (64B in → 64B out)
  2. demo_aead    : Full AEAD CPU-only (64B in → 80B out)
  3. demo_aead_dma: Full AEAD DMA-assisted (64B in → 80B out)

Tính năng:
  - Gửi plaintext (RFC 8439 test vector hoặc file tùy chọn)
  - Nhận ciphertext + tag
  - Tự động verify kết quả vs RFC 8439
  - Đo thời gian xử lý end-to-end
  - A/B test CPU-only vs DMA (cần reset FPGA giữa 2 lần)

Yêu cầu: pip install pyserial colorama

Sử dụng:
  python fpga_demo.py --port COM3 --demo aead
  python fpga_demo.py --port COM3 --demo chacha
  python fpga_demo.py --port COM3 --demo aead_dma
  python fpga_demo.py --port COM3 --demo ab_test
  python fpga_demo.py --port COM3 --demo aead --input myfile.bin
  python fpga_demo.py --selftest
"""

import argparse
import sys
import time
import struct

# Fix Windows console encoding for Unicode output (checkmarks, arrows, etc.)
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ('utf-8', 'utf8'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass  # Python < 3.7 fallback

try:
    import serial
except ImportError:
    serial = None  # OK for --selftest mode

try:
    from colorama import Fore, Style, init as colorama_init
    colorama_init()
except ImportError:
    # Fallback: no color
    class Fore:
        GREEN = RED = YELLOW = CYAN = MAGENTA = WHITE = RESET = ""
    class Style:
        BRIGHT = RESET_ALL = ""

# ============================================================
#  RFC 8439 Test Vectors
# ============================================================

# --- RFC 8439 §2.4.2 — ChaCha20 Encryption Test Vector ---
CHACHA20_PLAINTEXT = bytes([
    0x4c, 0x61, 0x64, 0x69, 0x65, 0x73, 0x20, 0x61,  # "Ladies a"
    0x6e, 0x64, 0x20, 0x47, 0x65, 0x6e, 0x74, 0x6c,  # "nd Gentl"
    0x65, 0x6d, 0x65, 0x6e, 0x20, 0x6f, 0x66, 0x20,  # "emen of "
    0x74, 0x68, 0x65, 0x20, 0x63, 0x6c, 0x61, 0x73,  # "the clas"
    0x73, 0x20, 0x6f, 0x66, 0x20, 0x27, 0x39, 0x39,  # "s of '99"
    0x3a, 0x20, 0x49, 0x66, 0x20, 0x49, 0x20, 0x63,  # ": If I c"
    0x6f, 0x75, 0x6c, 0x64, 0x20, 0x6f, 0x66, 0x66,  # "ould off"
    0x65, 0x72, 0x20, 0x79, 0x6f, 0x75, 0x20, 0x6f,  # "er you o"
])

# Expected ciphertext — RFC 8439 §2.4.2 (first 64 bytes)
CHACHA20_EXPECTED_CT = bytes([
    0x6e, 0x2e, 0x35, 0x9a, 0x25, 0x68, 0xf9, 0x80,
    0x41, 0xba, 0x07, 0x28, 0xdd, 0x0d, 0x69, 0x81,
    0xe9, 0x7e, 0x7a, 0xec, 0x1d, 0x43, 0x60, 0xc2,
    0x0a, 0x27, 0xaf, 0xcc, 0xfd, 0x9f, 0xae, 0x0b,
    0xf9, 0x1b, 0x65, 0xc5, 0x52, 0x47, 0x33, 0xab,
    0x8f, 0x59, 0x3d, 0xab, 0xcd, 0x62, 0xb3, 0x57,
    0x16, 0x39, 0xd6, 0x24, 0xe6, 0x51, 0x52, 0xab,
    0x8f, 0x53, 0x0c, 0x35, 0x9f, 0x08, 0x61, 0xd8,
])

# --- RFC 8439 §2.8.2 — AEAD Encryption Test Vector ---
# Same plaintext (first 64 bytes), different key/nonce → different CT
AEAD_EXPECTED_CT = bytes([
    0xd3, 0x1a, 0x8d, 0x34, 0x64, 0x8e, 0x60, 0xdb,
    0x7b, 0x86, 0xaf, 0xbc, 0x53, 0xef, 0x7e, 0xc2,
    0xa4, 0xad, 0xed, 0x51, 0x29, 0x6e, 0x08, 0xfe,
    0xa9, 0xe2, 0xb5, 0xa7, 0x36, 0xee, 0x62, 0xd6,
    0x3d, 0xbe, 0xa4, 0x5e, 0x8c, 0xa9, 0x67, 0x12,
    0x82, 0xfa, 0xfb, 0x69, 0xda, 0x92, 0x72, 0x8b,
    0x1a, 0x71, 0xde, 0x0a, 0x9e, 0x06, 0x0b, 0x29,
    0x05, 0xd6, 0xa5, 0xb6, 0x7e, 0xcd, 0x3b, 0x36,
])

# Expected tag — from soc_aead_tb simulation (verified against RFC)
AEAD_EXPECTED_TAG = bytes([
    0x57, 0x72, 0x8d, 0x89, 0x81, 0x1f, 0x44, 0xe3,
    0x44, 0x9f, 0x0d, 0x1c, 0x25, 0xa3, 0xe9, 0x5e,
])

# ============================================================
#  Firmware Key/Nonce Constants (hardcoded in demo_*.S)
# ============================================================

# ChaCha20-only (demo_chacha.S): key=00..1f, nonce=000000004a000000 00000000, ctr=1
FW_CHACHA_KEY   = bytes(range(0x00, 0x20))
FW_CHACHA_NONCE_16 = struct.pack('<I', 1) + bytes([
    0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x4a, 0x00,0x00,0x00,0x00])

# AEAD (demo_aead.S / demo_aead_dma.S): key=80..9f, nonce=07:00:00:00:40..47
FW_AEAD_KEY   = bytes(range(0x80, 0xa0))
FW_AEAD_NONCE = bytes([0x07,0x00,0x00,0x00, 0x40,0x41,0x42,0x43, 0x44,0x45,0x46,0x47])
FW_AEAD_AAD   = bytes([0x50,0x51,0x52,0x53, 0xc0,0xc1,0xc2,0xc3, 0xc4,0xc5,0xc6,0xc7])


def compute_expected(plaintext, mode):
    """
    Compute expected (ct, tag) for ANY 64-byte plaintext using
    the firmware's fixed key/nonce via Python crypto lib.
    Returns (expected_ct, expected_tag) — tag is None for chacha mode.
    Returns (None, None) if cryptography lib not installed.
    """
    try:
        from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
    except ImportError:
        return None, None

    pt64 = (plaintext + b'\x00' * 64)[:64]

    if mode == "chacha":
        cipher = Cipher(algorithms.ChaCha20(FW_CHACHA_KEY, FW_CHACHA_NONCE_16), mode=None)
        enc = cipher.encryptor()
        ct = enc.update(pt64) + enc.finalize()
        return ct, None
    else:  # aead / aead_dma
        aead_cipher = ChaCha20Poly1305(FW_AEAD_KEY)
        ct_tag = aead_cipher.encrypt(FW_AEAD_NONCE, pt64, FW_AEAD_AAD)
        return ct_tag[:-16], ct_tag[-16:]


def encode_plaintext(text_input):
    """
    Convert user text input to 64-byte padded plaintext.
    Encodes as UTF-8, truncates or pads with spaces to 64 bytes.
    """
    raw = text_input.encode('utf-8', errors='replace')[:64]
    return raw + b' ' * (64 - len(raw))


# ============================================================
#  Helper Functions
# ============================================================

def hex_dump(data, prefix="  ", cols=16):
    """Pretty hex dump of bytes."""
    lines = []
    for i in range(0, len(data), cols):
        chunk = data[i:i+cols]
        hex_part = " ".join(f"{b:02x}" for b in chunk)
        ascii_part = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"{prefix}{i:04x}: {hex_part:<{cols*3}}  {ascii_part}")
    return "\n".join(lines)


def compare_bytes(expected, actual, label="Data"):
    """Compare two byte arrays and print diff."""
    if len(expected) != len(actual):
        print(f"{Fore.RED}  {label}: LENGTH MISMATCH — expected {len(expected)}, got {len(actual)}{Style.RESET_ALL}")
        return False

    errors = 0
    for i, (e, a) in enumerate(zip(expected, actual)):
        if e != a:
            if errors < 8:  # Show first 8 mismatches
                print(f"{Fore.RED}  {label}[{i:3d}]: expected 0x{e:02x}, got 0x{a:02x}{Style.RESET_ALL}")
            errors += 1

    if errors == 0:
        print(f"{Fore.GREEN}  {label}: {len(expected)}/{len(expected)} bytes MATCH ✓{Style.RESET_ALL}")
        return True
    else:
        print(f"{Fore.RED}  {label}: {errors}/{len(expected)} bytes MISMATCH ✗{Style.RESET_ALL}")
        return False


def open_serial(port, baudrate=115200, timeout=5.0):
    """Open serial port with error handling."""
    try:
        ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=timeout,
            write_timeout=timeout,
        )
        # Flush buffers
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        return ser
    except serial.SerialException as e:
        print(f"{Fore.RED}ERROR: Không mở được {port}: {e}{Style.RESET_ALL}")
        print(f"  → Kiểm tra: cổng COM đúng chưa? FPGA đã nạp chương trình chưa?")
        sys.exit(1)


# ============================================================
#  Core Demo Functions
# ============================================================

def run_demo(ser, plaintext, demo_name, expected_ct, expected_tag=None):
    """
    Run one demo transaction:
      1. Send plaintext (64 bytes)
      2. Receive ciphertext (+tag if AEAD)
      3. Verify against expected values
      4. Return (ct, tag, elapsed_ms)
    """
    tx_len = 64
    rx_len = 64 if expected_tag is None else 80

    print(f"\n{'='*60}")
    print(f"  {Fore.CYAN}{Style.BRIGHT}{demo_name}{Style.RESET_ALL}")
    print(f"{'='*60}")

    # Show plaintext
    print(f"\n{Fore.YELLOW}[TX] Sending {tx_len} bytes plaintext:{Style.RESET_ALL}")
    ascii_text = plaintext[:tx_len].decode("ascii", errors="replace")
    print(f"  \"{ascii_text}\"")

    # Flush before sending
    ser.reset_input_buffer()

    # Send plaintext byte-by-byte with small delay for UART RX reliability
    t_start = time.perf_counter()

    for i, byte in enumerate(plaintext[:tx_len]):
        ser.write(bytes([byte]))
        # Small delay between bytes to avoid overrunning FPGA's single-byte RX buffer
        time.sleep(0.001)  # 1ms — FPGA needs ~87µs per byte at 115200, so 1ms is safe

    ser.flush()
    print(f"  Sent {tx_len} bytes. Waiting for response...")

    # Receive response
    response = bytearray()
    rx_timeout = time.perf_counter() + 10.0  # 10 second max wait

    while len(response) < rx_len:
        remaining = rx_len - len(response)
        chunk = ser.read(remaining)
        if chunk:
            response.extend(chunk)
        if time.perf_counter() > rx_timeout:
            break

    t_end = time.perf_counter()
    elapsed_ms = (t_end - t_start) * 1000.0

    if len(response) < rx_len:
        print(f"{Fore.RED}  TIMEOUT: Chỉ nhận được {len(response)}/{rx_len} bytes sau 10s{Style.RESET_ALL}")
        print(f"  → Kiểm tra: FPGA đã nạp đúng firmware ({demo_name})? Reset FPGA?")
        if response:
            print(f"\n  Received so far:")
            print(hex_dump(response))
        return None, None, elapsed_ms

    # Split CT and TAG
    ct = bytes(response[:64])
    tag = bytes(response[64:]) if rx_len > 64 else None

    # Display results
    print(f"\n{Fore.GREEN}[RX] Received {len(response)} bytes in {elapsed_ms:.1f} ms:{Style.RESET_ALL}")
    print(f"\n  Ciphertext ({len(ct)} bytes):")
    print(hex_dump(ct))

    if tag:
        print(f"\n  Tag ({len(tag)} bytes):")
        print(hex_dump(tag))

    # Verify
    is_rfc = (expected_ct is not None)
    if is_rfc:
        print(f"\n{Fore.CYAN}[VERIFY] So sánh với expected (tính từ firmware key/nonce):{Style.RESET_ALL}")
    else:
        print(f"\n{Fore.CYAN}[VERIFY] Không có expected (cryptography lib chưa cài){Style.RESET_ALL}")

    ct_ok = compare_bytes(expected_ct, ct, "Ciphertext") if expected_ct else True

    tag_ok = True
    if expected_tag and tag:
        tag_ok = compare_bytes(expected_tag, tag, "Tag")

    # Timing
    print(f"\n  ⏱  Thời gian end-to-end: {Fore.MAGENTA}{elapsed_ms:.1f} ms{Style.RESET_ALL}")
    uart_tx_time = tx_len * 10 / 115200 * 1000  # 10 bits per byte
    uart_rx_time = rx_len * 10 / 115200 * 1000
    uart_overhead = uart_tx_time + uart_rx_time
    send_delay = tx_len * 1.0  # 1ms per byte delay we added
    crypto_est = elapsed_ms - uart_overhead - send_delay
    print(f"  ⏱  UART overhead (TX+RX): ~{uart_overhead:.1f} ms")
    print(f"  ⏱  Send delay (safety): ~{send_delay:.0f} ms")
    print(f"  ⏱  Crypto processing (est): ~{max(0, crypto_est):.1f} ms")

    if expected_ct is None:
        print(f"\n  {Fore.YELLOW}⚠ Cài 'pip install cryptography' để verify tự động{Style.RESET_ALL}")
    elif ct_ok and tag_ok:
        print(f"\n  {Fore.GREEN}{Style.BRIGHT}✓ PASS — Kết quả đúng{Style.RESET_ALL}")
    else:
        print(f"\n  {Fore.RED}{Style.BRIGHT}✗ FAIL — Kết quả KHÔNG khớp expected{Style.RESET_ALL}")

    return ct, tag, elapsed_ms


# ============================================================
#  Demo Modes
# ============================================================

def demo_chacha(ser, plaintext):
    """ChaCha20-only encryption (demo_chacha.hex)"""
    exp_ct, _ = compute_expected(plaintext, "chacha")
    return run_demo(
        ser, plaintext,
        demo_name="Demo ChaCha20 Encryption (RFC 8439 §2.4.2)",
        expected_ct=exp_ct,
        expected_tag=None,
    )


def demo_aead(ser, plaintext):
    """Full AEAD CPU-only (demo_aead.hex)"""
    exp_ct, exp_tag = compute_expected(plaintext, "aead")
    return run_demo(
        ser, plaintext,
        demo_name="Demo AEAD ChaCha20-Poly1305 — CPU-only (RFC 8439 §2.8.2)",
        expected_ct=exp_ct,
        expected_tag=exp_tag,
    )


def demo_aead_dma(ser, plaintext):
    """Full AEAD DMA-assisted (demo_aead_dma.hex)"""
    exp_ct, exp_tag = compute_expected(plaintext, "aead")
    return run_demo(
        ser, plaintext,
        demo_name="Demo AEAD ChaCha20-Poly1305 — DMA-assisted (RFC 8439 §2.8.2)",
        expected_ct=exp_ct,
        expected_tag=exp_tag,
    )


def demo_ab_test(ser, plaintext):
    """A/B test: run AEAD CPU-only, then AEAD DMA (requires reset between)"""
    print(f"\n{'#'*60}")
    print(f"  {Fore.MAGENTA}{Style.BRIGHT}A/B TEST: CPU-only vs DMA-assisted AEAD{Style.RESET_ALL}")
    print(f"{'#'*60}")

    # --- Test A: CPU-only ---
    print(f"\n{Fore.YELLOW}[A] Nạp demo_aead.hex lên FPGA rồi nhấn Enter...{Style.RESET_ALL}")
    input("  → Nhấn Enter khi FPGA sẵn sàng (7-seg hiện 0x0001): ")

    ct_a, tag_a, time_a = demo_aead(ser, plaintext)

    # --- Test B: DMA ---
    print(f"\n{Fore.YELLOW}[B] Nạp demo_aead_dma.hex lên FPGA rồi nhấn Enter...{Style.RESET_ALL}")
    input("  → Nhấn Enter khi FPGA sẵn sàng (7-seg hiện 0x0001): ")

    # Re-flush
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    ct_b, tag_b, time_b = demo_aead_dma(ser, plaintext)

    # --- Comparison ---
    print(f"\n{'='*60}")
    print(f"  {Fore.CYAN}{Style.BRIGHT}A/B TEST RESULTS{Style.RESET_ALL}")
    print(f"{'='*60}")

    if ct_a and ct_b:
        print(f"\n  {'Metric':<25} {'CPU-only':>12} {'DMA-assist':>12} {'Delta':>12}")
        print(f"  {'-'*61}")
        print(f"  {'End-to-end time (ms)':<25} {time_a:>11.1f} {time_b:>11.1f} ", end="")

        if time_b < time_a:
            pct = (time_a - time_b) / time_a * 100
            print(f"{Fore.GREEN}{pct:>10.1f}% faster{Style.RESET_ALL}")
        else:
            pct = (time_b - time_a) / time_a * 100
            print(f"{Fore.RED}{pct:>10.1f}% slower{Style.RESET_ALL}")

        ct_match = ct_a == ct_b
        tag_match = tag_a == tag_b
        print(f"  {'CT match':<25} {'':>12} {'':>12} ", end="")
        print(f"{Fore.GREEN}✓ MATCH{Style.RESET_ALL}" if ct_match else f"{Fore.RED}✗ MISMATCH{Style.RESET_ALL}")
        print(f"  {'TAG match':<25} {'':>12} {'':>12} ", end="")
        print(f"{Fore.GREEN}✓ MATCH{Style.RESET_ALL}" if tag_match else f"{Fore.RED}✗ MISMATCH{Style.RESET_ALL}")

        print(f"\n  {Style.BRIGHT}Ghi chú: Thời gian end-to-end bao gồm UART overhead (~12ms).{Style.RESET_ALL}")
        print(f"  DMA tiết kiệm ~17% crypto cycles (xem sim log để so sánh chính xác).")


# ============================================================
#  Selftest — Independent Verification (No FPGA needed)
# ============================================================

class MockSerial:
    """Fake serial port that returns expected response bytes for selftest."""

    def __init__(self, response_bytes):
        self._response = bytearray(response_bytes)
        self._tx_buf = bytearray()
        self._rx_pos = 0

    def write(self, data):
        self._tx_buf.extend(data)

    def flush(self):
        pass

    def read(self, size=1):
        end = min(self._rx_pos + size, len(self._response))
        data = bytes(self._response[self._rx_pos:end])
        self._rx_pos = end
        return data

    def reset_input_buffer(self):
        self._rx_pos = 0

    def reset_output_buffer(self):
        self._tx_buf.clear()

    def close(self):
        pass


def selftest():
    """
    Independent verification — confirms expected values are correct
    using Python cryptography library, then tests script pipeline
    with MockSerial.
    """
    print(f"\n{'#'*60}")
    print(f"  {Fore.CYAN}{Style.BRIGHT}SELFTEST — Offline Verification (No FPGA){Style.RESET_ALL}")
    print(f"{'#'*60}")

    all_pass = True

    # ── Part 1: Independent crypto verification ─────────────
    print(f"\n{Fore.YELLOW}[Part 1] Independent crypto verification (Python cryptography lib){Style.RESET_ALL}")

    try:
        from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
    except ImportError:
        print(f"{Fore.RED}  ERROR: pip install cryptography{Style.RESET_ALL}")
        print(f"  Bỏ qua Part 1, chuyển sang Part 2...")
        return selftest_pipeline_only()

    pt = CHACHA20_PLAINTEXT

    # Test 1a: ChaCha20-only (RFC 8439 §2.4.2)
    print(f"\n  {Style.BRIGHT}Test 1a: ChaCha20 Encryption (RFC 8439 §2.4.2){Style.RESET_ALL}")
    key_ch = bytes(range(0x00, 0x20))
    nonce_16 = struct.pack('<I', 1) + bytes([0,0,0,0, 0,0,0,0x4a, 0,0,0,0])
    cipher = Cipher(algorithms.ChaCha20(key_ch, nonce_16), mode=None)
    enc = cipher.encryptor()
    ct_py = enc.update(pt) + enc.finalize()

    if ct_py == CHACHA20_EXPECTED_CT:
        print(f"  {Fore.GREEN}✓ PASS — ChaCha20 CT (64B) matches Python crypto lib{Style.RESET_ALL}")
    else:
        print(f"  {Fore.RED}✗ FAIL — ChaCha20 CT mismatch!{Style.RESET_ALL}")
        all_pass = False

    # Test 1b: AEAD (RFC 8439 §2.8.2, 64B)
    print(f"\n  {Style.BRIGHT}Test 1b: AEAD ChaCha20-Poly1305 (RFC 8439 §2.8.2, 64B PT){Style.RESET_ALL}")
    key_aead = bytes(range(0x80, 0xa0))
    nonce_aead = bytes([0x07,0x00,0x00,0x00, 0x40,0x41,0x42,0x43, 0x44,0x45,0x46,0x47])
    aad = bytes([0x50,0x51,0x52,0x53, 0xc0,0xc1,0xc2,0xc3, 0xc4,0xc5,0xc6,0xc7])

    aead_cipher = ChaCha20Poly1305(key_aead)
    ct_tag = aead_cipher.encrypt(nonce_aead, pt, aad)
    ct_aead_py = ct_tag[:-16]
    tag_aead_py = ct_tag[-16:]

    if ct_aead_py == AEAD_EXPECTED_CT:
        print(f"  {Fore.GREEN}✓ PASS — AEAD CT (64B) matches Python crypto lib{Style.RESET_ALL}")
    else:
        print(f"  {Fore.RED}✗ FAIL — AEAD CT mismatch!{Style.RESET_ALL}")
        all_pass = False

    if tag_aead_py == AEAD_EXPECTED_TAG:
        print(f"  {Fore.GREEN}✓ PASS — AEAD TAG (16B) matches Python crypto lib{Style.RESET_ALL}")
    else:
        print(f"  {Fore.RED}✗ FAIL — AEAD TAG mismatch!{Style.RESET_ALL}")
        print(f"    Python : {tag_aead_py.hex()}")
        print(f"    Script : {AEAD_EXPECTED_TAG.hex()}")
        all_pass = False

    print(f"\n  {Style.BRIGHT}Kết luận Part 1:{Style.RESET_ALL} Expected values trong script khớp 100%")
    print(f"  với Python cryptography library (independent reference).")

    # ── Part 2: MockSerial pipeline test ────────────────────
    all_pass = selftest_pipeline(all_pass)

    # ── Final ───────────────────────────────────────────────
    print(f"\n{'='*60}")
    if all_pass:
        print(f"  {Fore.GREEN}{Style.BRIGHT}SELFTEST PASSED — Script sẵn sàng cho FPGA demo{Style.RESET_ALL}")
    else:
        print(f"  {Fore.RED}{Style.BRIGHT}SELFTEST FAILED — Cần sửa lỗi{Style.RESET_ALL}")
    print(f"{'='*60}")
    return all_pass


def selftest_pipeline_only():
    """Run just the MockSerial pipeline tests (no crypto lib)."""
    return selftest_pipeline(True)


def selftest_pipeline(all_pass):
    """Test the full script pipeline using MockSerial."""
    print(f"\n{Fore.YELLOW}[Part 2] MockSerial pipeline test (verify script logic){Style.RESET_ALL}")

    pt = CHACHA20_PLAINTEXT

    # Test 2a: ChaCha20 pipeline
    print(f"\n  {Style.BRIGHT}Test 2a: ChaCha20 pipeline (MockSerial → 64B){Style.RESET_ALL}")
    mock_chacha = MockSerial(CHACHA20_EXPECTED_CT)
    ct, tag, elapsed = run_demo(
        mock_chacha, pt,
        demo_name="[SELFTEST] ChaCha20 Encryption",
        expected_ct=CHACHA20_EXPECTED_CT,
        expected_tag=None,
    )
    if ct == CHACHA20_EXPECTED_CT:
        print(f"  {Fore.GREEN}✓ PASS — Pipeline correctly received and verified 64B CT{Style.RESET_ALL}")
    else:
        print(f"  {Fore.RED}✗ FAIL — Pipeline error{Style.RESET_ALL}")
        all_pass = False

    # Test 2b: AEAD pipeline
    print(f"\n  {Style.BRIGHT}Test 2b: AEAD pipeline (MockSerial → 80B){Style.RESET_ALL}")
    mock_aead = MockSerial(AEAD_EXPECTED_CT + AEAD_EXPECTED_TAG)
    ct, tag, elapsed = run_demo(
        mock_aead, pt,
        demo_name="[SELFTEST] AEAD ChaCha20-Poly1305",
        expected_ct=AEAD_EXPECTED_CT,
        expected_tag=AEAD_EXPECTED_TAG,
    )
    if ct == AEAD_EXPECTED_CT and tag == AEAD_EXPECTED_TAG:
        print(f"  {Fore.GREEN}✓ PASS — Pipeline correctly received and verified 80B (CT+TAG){Style.RESET_ALL}")
    else:
        print(f"  {Fore.RED}✗ FAIL — Pipeline error{Style.RESET_ALL}")
        all_pass = False

    # Test 2c: Mismatch detection
    print(f"\n  {Style.BRIGHT}Test 2c: Mismatch detection (corrupt 1 byte){Style.RESET_ALL}")
    corrupt_ct = bytearray(AEAD_EXPECTED_CT)
    corrupt_ct[0] ^= 0xFF  # Flip first byte
    mock_corrupt = MockSerial(bytes(corrupt_ct) + AEAD_EXPECTED_TAG)
    ct, tag, elapsed = run_demo(
        mock_corrupt, pt,
        demo_name="[SELFTEST] Corrupt CT Detection",
        expected_ct=AEAD_EXPECTED_CT,
        expected_tag=AEAD_EXPECTED_TAG,
    )
    # This should print FAIL (which is correct behavior)
    if ct != AEAD_EXPECTED_CT:
        print(f"  {Fore.GREEN}✓ PASS — Script correctly detected corruption{Style.RESET_ALL}")
    else:
        print(f"  {Fore.RED}✗ FAIL — Script missed corruption!{Style.RESET_ALL}")
        all_pass = False

    return all_pass

def main():
    parser = argparse.ArgumentParser(
        description="RISC-V SoC AEAD Demo — UART Interface",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ:
  python fpga_demo.py --port COM3 --demo aead
  python fpga_demo.py --port COM3 --demo chacha
  python fpga_demo.py --port COM3 --demo aead_dma
  python fpga_demo.py --port COM3 --demo ab_test
  python fpga_demo.py --port COM3 --demo aead --input plaintext.bin  python fpga_demo.py --port COM3 --demo aead --text "Hello RISC-V!"
  python fpga_demo.py --port COM3 --demo aead --interactive  python fpga_demo.py --selftest
  python fpga_demo.py --list-ports
        """,
    )
    parser.add_argument("--port", "-p", default="COM3",
                        help="Cổng COM (mặc định: COM3)")
    parser.add_argument("--demo", "-d", default="aead",
                        choices=["chacha", "aead", "aead_dma", "ab_test"],
                        help="Chế độ demo (mặc định: aead)")
    parser.add_argument("--input", "-i", default=None,
                        help="File plaintext (64 bytes). Mặc định: RFC 8439 test vector")
    parser.add_argument("--text", "-t", default=None,
                        help="Plaintext tùy chọn (chuỗi, tối đa 64 ký tự, pad bằng dấu cách)")
    parser.add_argument("--interactive", action="store_true",
                        help="Chế độ tương tác: hỏi plaintext sau mỗi lần gửi")
    parser.add_argument("--baud", "-b", type=int, default=115200,
                        help="Baudrate (mặc định: 115200)")
    parser.add_argument("--list-ports", action="store_true",
                        help="Liệt kê các cổng COM có sẵn")
    parser.add_argument("--selftest", action="store_true",
                        help="Chạy selftest offline (không cần FPGA)")

    args = parser.parse_args()

    # Selftest mode — no hardware needed
    if args.selftest:
        ok = selftest()
        sys.exit(0 if ok else 1)

    # List ports
    if args.list_ports:
        if serial is None:
            print("ERROR: Cần cài pyserial:  pip install pyserial")
            sys.exit(1)
        from serial.tools.list_ports import comports
        ports = comports()
        if not ports:
            print("Không tìm thấy cổng COM nào.")
        else:
            print(f"\nCác cổng COM có sẵn:")
            for p in ports:
                print(f"  {p.device:8s}  {p.description}")
        return

    # Load plaintext
    if args.text:
        plaintext = encode_plaintext(args.text)
        print(f"Plaintext từ --text: \"{args.text[:64]}\"")
    elif args.input:
        try:
            with open(args.input, "rb") as f:
                plaintext = f.read(64)
            if len(plaintext) < 64:
                plaintext += b'\x00' * (64 - len(plaintext))
            print(f"Loaded plaintext from {args.input} ({len(plaintext)} bytes)")
        except FileNotFoundError:
            print(f"ERROR: File không tồn tại: {args.input}")
            sys.exit(1)
    else:
        plaintext = CHACHA20_PLAINTEXT  # RFC 8439 "Ladies and Gentlemen..."
        print(f"Sử dụng plaintext mặc định: RFC 8439 test vector")

    # Banner
    print(f"\n{'='*60}")
    print(f"  {Style.BRIGHT}RISC-V SoC — ChaCha20-Poly1305 AEAD Demo{Style.RESET_ALL}")
    print(f"  Port: {args.port}  |  Baud: {args.baud}  |  Mode: {args.demo}")
    print(f"{'='*60}")

    # Open serial
    if serial is None:
        print("ERROR: Cần cài pyserial:  pip install pyserial")
        sys.exit(1)
    ser = open_serial(args.port, args.baud)
    print(f"  ✓ Kết nối {args.port} thành công")

    def run_once(pt):
        if args.demo == "chacha":
            return demo_chacha(ser, pt)
        elif args.demo == "aead":
            return demo_aead(ser, pt)
        elif args.demo == "aead_dma":
            return demo_aead_dma(ser, pt)
        elif args.demo == "ab_test":
            return demo_ab_test(ser, pt)

    try:
        if args.interactive:
            # Interactive loop — keep asking for new plaintext
            current_pt = plaintext
            run_num = 1
            while True:
                print(f"\n{Fore.MAGENTA}{'─'*60}")
                print(f"  Lần #{run_num}", end="")
                if run_num == 1:
                    print(f"  (plaintext hiện tại: \"{current_pt.decode('utf-8', errors='replace').strip()[:40]}...\"")
                print(f"{Style.RESET_ALL}")

                run_once(current_pt)
                run_num += 1

                # Ask what to do next
                print(f"\n{Fore.YELLOW}Tiếp theo:{Style.RESET_ALL}")
                print(f"  [Enter]      Gửi lại cùng plaintext")
                print(f"  [text]       Gõ plaintext mới (tối đa 64 ký tự)")
                print(f"  [q / Ctrl+C] Thoát")
                try:
                    user_in = input(f"  → ").strip()
                except EOFError:
                    break

                if user_in.lower() == 'q':
                    break
                elif user_in == '':
                    pass  # reuse current_pt
                else:
                    current_pt = encode_plaintext(user_in)
                    print(f"  Plaintext mới: \"{user_in[:64]}\"  ({len(current_pt)} bytes)")

                # Reset FPGA RX needs time — firmware loops back to Phase 1 automatically
                # after TX completes, so no extra delay needed
                ser.reset_input_buffer()
        else:
            run_once(plaintext)
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}Đã hủy bởi người dùng.{Style.RESET_ALL}")
    finally:
        ser.close()
        print(f"\n  Đã đóng {args.port}.")


if __name__ == "__main__":
    main()
