#!/usr/bin/env python3
"""
fpga_verify.py — Script 1: Verify FPGA với RFC 8439 Test Vector
================================================================
Gửi plaintext CỐ ĐỊNH (RFC 8439) → nhận CT/TAG → verify tự động.
Không cần nhập gì — chạy 1 lệnh là xong.

Cách dùng:
  python fpga_verify.py --port COM3 --demo aead
  python fpga_verify.py --port COM3 --demo chacha
  python fpga_verify.py --port COM3 --demo aead_dma
  python fpga_verify.py --selftest          (không cần FPGA)
  python fpga_verify.py --list-ports

Flow:
  ┌──────────┐    UART 115200    ┌──────────────┐
  │  PC      │ ──── 64 bytes ──→ │  FPGA        │
  │  (script)│ ←─ 64 or 80B ─── │  (demo_*.hex)│
  └──────────┘                   └──────────────┘

  demo chacha:    PC gửi 64B → FPGA trả 64B CT
  demo aead:      PC gửi 64B → FPGA trả 80B (64B CT + 16B TAG)
  demo aead_dma:  PC gửi 64B → FPGA trả 80B (64B CT + 16B TAG)
"""

import argparse
import sys
import time
import struct

# Fix Windows console encoding
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ('utf-8', 'utf8'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass

try:
    import serial
except ImportError:
    serial = None

# ============================================================
#  RFC 8439 Test Vectors (cố định, không thay đổi)
# ============================================================

# Plaintext: "Ladies and Gentlemen of the class of '99: If I could offer you o"
PLAINTEXT = bytes([
    0x4c, 0x61, 0x64, 0x69, 0x65, 0x73, 0x20, 0x61,
    0x6e, 0x64, 0x20, 0x47, 0x65, 0x6e, 0x74, 0x6c,
    0x65, 0x6d, 0x65, 0x6e, 0x20, 0x6f, 0x66, 0x20,
    0x74, 0x68, 0x65, 0x20, 0x63, 0x6c, 0x61, 0x73,
    0x73, 0x20, 0x6f, 0x66, 0x20, 0x27, 0x39, 0x39,
    0x3a, 0x20, 0x49, 0x66, 0x20, 0x49, 0x20, 0x63,
    0x6f, 0x75, 0x6c, 0x64, 0x20, 0x6f, 0x66, 0x66,
    0x65, 0x72, 0x20, 0x79, 0x6f, 0x75, 0x20, 0x6f,
])

# ChaCha20-only expected CT (RFC 8439 §2.4.2)
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

# AEAD expected CT (RFC 8439 §2.8.2, first 64 bytes)
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

# AEAD expected TAG (verified by QuestaSim + Python crypto lib)
AEAD_EXPECTED_TAG = bytes([
    0x57, 0x72, 0x8d, 0x89, 0x81, 0x1f, 0x44, 0xe3,
    0x44, 0x9f, 0x0d, 0x1c, 0x25, 0xa3, 0xe9, 0x5e,
])

# ============================================================
#  Helper Functions
# ============================================================

def hex_dump(data, cols=16):
    lines = []
    for i in range(0, len(data), cols):
        chunk = data[i:i+cols]
        h = " ".join(f"{b:02x}" for b in chunk)
        a = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"    {i:04x}: {h:<{cols*3}}  {a}")
    return "\n".join(lines)


def compare_bytes(expected, actual, label):
    if len(expected) != len(actual):
        print(f"  {label}: LENGTH MISMATCH — expected {len(expected)}, got {len(actual)}")
        return False, 0
    errors = 0
    for i, (e, a) in enumerate(zip(expected, actual)):
        if e != a:
            if errors < 8:
                print(f"  {label}[{i:3d}]: expected 0x{e:02x}, got 0x{a:02x}")
            errors += 1
    ok = errors == 0
    if ok:
        print(f"  {label}: {len(expected)}/{len(expected)} bytes MATCH")
    else:
        print(f"  {label}: {errors}/{len(expected)} bytes MISMATCH")
    return ok, errors


def open_serial(port, baud=115200):
    try:
        ser = serial.Serial(
            port=port, baudrate=baud,
            bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=5.0, write_timeout=5.0,
        )
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        return ser
    except serial.SerialException as e:
        print(f"ERROR: Khong mo duoc {port}: {e}")
        print(f"  -> Kiem tra: cong COM dung chua? FPGA da nap chuong trinh chua?")
        sys.exit(1)


# ============================================================
#  Core: Send → Receive → Verify
# ============================================================

def send_and_verify(ser, mode):
    """
    Gửi plaintext RFC 8439 → nhận response → verify vs expected.

    mode: "chacha"   → gửi 64B, nhận 64B CT
          "aead"     → gửi 64B, nhận 80B (64B CT + 16B TAG)
          "aead_dma" → gửi 64B, nhận 80B (64B CT + 16B TAG)
    """
    if mode == "chacha":
        exp_ct = CHACHA20_EXPECTED_CT
        exp_tag = None
        rx_len = 64
        label = "ChaCha20 Encryption (RFC 8439 Section 2.4.2)"
    else:
        exp_ct = AEAD_EXPECTED_CT
        exp_tag = AEAD_EXPECTED_TAG
        rx_len = 80
        dma_str = " + DMA" if mode == "aead_dma" else " CPU-only"
        label = f"AEAD ChaCha20-Poly1305{dma_str} (RFC 8439 Section 2.8.2)"

    print(f"\n{'='*60}")
    print(f"  {label}")
    print(f"{'='*60}")

    # --- Step 1: Send plaintext ---
    pt_ascii = PLAINTEXT.decode("ascii", errors="replace")
    print(f"\n[TX] Gui 64 bytes plaintext:")
    print(f'  "{pt_ascii}"')

    ser.reset_input_buffer()
    t_start = time.perf_counter()

    for byte in PLAINTEXT:
        ser.write(bytes([byte]))
        time.sleep(0.001)  # 1ms delay — safe cho FPGA single-byte RX buffer

    ser.flush()
    print(f"  Da gui 64 bytes. Cho FPGA xu ly...")

    # --- Step 2: Receive response ---
    response = bytearray()
    deadline = time.perf_counter() + 10.0

    while len(response) < rx_len:
        chunk = ser.read(rx_len - len(response))
        if chunk:
            response.extend(chunk)
        if time.perf_counter() > deadline:
            break

    t_end = time.perf_counter()
    elapsed_ms = (t_end - t_start) * 1000.0

    if len(response) < rx_len:
        print(f"\n  TIMEOUT: Chi nhan duoc {len(response)}/{rx_len} bytes sau 10s")
        print(f"  -> Kiem tra: FPGA nap dung firmware? Da reset FPGA?")
        if response:
            print(hex_dump(response))
        return False

    # --- Step 3: Display ---
    ct = bytes(response[:64])
    tag = bytes(response[64:]) if rx_len > 64 else None

    print(f"\n[RX] Nhan {len(response)} bytes trong {elapsed_ms:.1f} ms:")
    print(f"\n  Ciphertext ({len(ct)} bytes):")
    print(hex_dump(ct))
    if tag:
        print(f"\n  Tag ({len(tag)} bytes):")
        print(hex_dump(tag))

    # --- Step 4: Verify ---
    print(f"\n[VERIFY] So sanh voi RFC 8439 expected:")
    ct_ok, _ = compare_bytes(exp_ct, ct, "Ciphertext")

    tag_ok = True
    if exp_tag:
        tag_ok, _ = compare_bytes(exp_tag, tag, "Tag")

    # --- Step 5: Timing ---
    uart_overhead = (64 + rx_len) * 10 / 115200 * 1000
    send_delay = 64 * 1.0
    crypto_est = max(0, elapsed_ms - uart_overhead - send_delay)
    print(f"\n  Thoi gian end-to-end : {elapsed_ms:.1f} ms")
    print(f"  UART overhead (est)  : ~{uart_overhead:.1f} ms")
    print(f"  Send delay (safety)  : ~{send_delay:.0f} ms")
    print(f"  Crypto processing    : ~{crypto_est:.1f} ms")

    # --- Result ---
    if ct_ok and tag_ok:
        print(f"\n  >>> PASS — Ket qua dung RFC 8439 <<<")
    else:
        print(f"\n  >>> FAIL — Ket qua KHONG khop RFC 8439 <<<")

    return ct_ok and tag_ok


# ============================================================
#  Selftest (không cần FPGA)
# ============================================================

class MockSerial:
    def __init__(self, response):
        self._resp = bytearray(response)
        self._pos = 0
    def write(self, data): pass
    def flush(self): pass
    def read(self, size=1):
        end = min(self._pos + size, len(self._resp))
        data = bytes(self._resp[self._pos:end])
        self._pos = end
        return data
    def reset_input_buffer(self):
        self._pos = 0
    def reset_output_buffer(self): pass
    def close(self): pass


def selftest():
    print(f"\n{'='*60}")
    print(f"  SELFTEST — Kiem tra offline (khong can FPGA)")
    print(f"{'='*60}")

    all_pass = True

    # Part 1: Python crypto lib verification
    print(f"\n[Part 1] Kiem tra expected values bang Python crypto lib")
    try:
        from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms

        # ChaCha20
        key = bytes(range(0x00, 0x20))
        nonce16 = struct.pack('<I', 1) + bytes([0,0,0,0, 0,0,0,0x4a, 0,0,0,0])
        c = Cipher(algorithms.ChaCha20(key, nonce16), mode=None)
        ct = c.encryptor().update(PLAINTEXT) + c.encryptor().finalize()
        # Re-create (encryptor is consumed)
        c = Cipher(algorithms.ChaCha20(key, nonce16), mode=None)
        enc = c.encryptor()
        ct = enc.update(PLAINTEXT) + enc.finalize()
        ok1 = ct == CHACHA20_EXPECTED_CT
        print(f"  ChaCha20 CT:  {'PASS' if ok1 else 'FAIL'}")

        # AEAD
        aead = ChaCha20Poly1305(bytes(range(0x80, 0xa0)))
        nonce = bytes([0x07,0,0,0, 0x40,0x41,0x42,0x43, 0x44,0x45,0x46,0x47])
        aad = bytes([0x50,0x51,0x52,0x53, 0xc0,0xc1,0xc2,0xc3, 0xc4,0xc5,0xc6,0xc7])
        ct_tag = aead.encrypt(nonce, PLAINTEXT, aad)
        ok2 = ct_tag[:-16] == AEAD_EXPECTED_CT
        ok3 = ct_tag[-16:] == AEAD_EXPECTED_TAG
        print(f"  AEAD CT:      {'PASS' if ok2 else 'FAIL'}")
        print(f"  AEAD TAG:     {'PASS' if ok3 else 'FAIL'}")
        if not (ok1 and ok2 and ok3):
            all_pass = False
    except ImportError:
        print(f"  (cryptography chua cai — bo qua)")

    # Part 2: MockSerial pipeline test
    print(f"\n[Part 2] Kiem tra pipeline bang MockSerial")

    # ChaCha20 pipeline
    mock = MockSerial(CHACHA20_EXPECTED_CT)
    pt_ok = mock_send_and_verify(mock, "chacha")
    print(f"  ChaCha20 pipeline: {'PASS' if pt_ok else 'FAIL'}")
    if not pt_ok: all_pass = False

    # AEAD pipeline
    mock = MockSerial(AEAD_EXPECTED_CT + AEAD_EXPECTED_TAG)
    pt_ok = mock_send_and_verify(mock, "aead")
    print(f"  AEAD pipeline:     {'PASS' if pt_ok else 'FAIL'}")
    if not pt_ok: all_pass = False

    print(f"\n{'='*60}")
    print(f"  {'SELFTEST PASSED' if all_pass else 'SELFTEST FAILED'}")
    print(f"{'='*60}")
    return all_pass


def mock_send_and_verify(mock, mode):
    """Simplified send_and_verify for MockSerial (suppressed output)."""
    exp_ct = CHACHA20_EXPECTED_CT if mode == "chacha" else AEAD_EXPECTED_CT
    exp_tag = None if mode == "chacha" else AEAD_EXPECTED_TAG
    rx_len = 64 if mode == "chacha" else 80

    mock.reset_input_buffer()
    for byte in PLAINTEXT:
        mock.write(bytes([byte]))
    mock.flush()

    response = bytearray()
    while len(response) < rx_len:
        chunk = mock.read(rx_len - len(response))
        if chunk:
            response.extend(chunk)
        else:
            break

    ct = bytes(response[:64])
    tag = bytes(response[64:]) if rx_len > 64 else None

    ct_ok = ct == exp_ct
    tag_ok = (tag == exp_tag) if exp_tag else True
    return ct_ok and tag_ok


# ============================================================
#  Main
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="FPGA Verify — RFC 8439 test vector verification",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ:
  python fpga_verify.py --port COM3 --demo aead         # AEAD CPU-only
  python fpga_verify.py --port COM3 --demo aead_dma     # AEAD + DMA
  python fpga_verify.py --port COM3 --demo chacha       # ChaCha20 only
  python fpga_verify.py --selftest                       # Kiem tra offline
  python fpga_verify.py --list-ports                     # Liet ke COM ports
        """,
    )
    parser.add_argument("--port", "-p", default="COM3",
                        help="Cong COM (mac dinh: COM3)")
    parser.add_argument("--demo", "-d", default="aead",
                        choices=["chacha", "aead", "aead_dma"],
                        help="Che do demo (mac dinh: aead)")
    parser.add_argument("--baud", "-b", type=int, default=115200,
                        help="Baudrate (mac dinh: 115200)")
    parser.add_argument("--list-ports", action="store_true",
                        help="Liet ke cac cong COM co san")
    parser.add_argument("--selftest", action="store_true",
                        help="Chay selftest offline (khong can FPGA)")
    args = parser.parse_args()

    # --- Selftest ---
    if args.selftest:
        ok = selftest()
        sys.exit(0 if ok else 1)

    # --- List ports ---
    if args.list_ports:
        if serial is None:
            print("ERROR: Can cai pyserial:  pip install pyserial")
            sys.exit(1)
        from serial.tools.list_ports import comports
        ports = comports()
        if not ports:
            print("Khong tim thay cong COM nao.")
        else:
            print(f"\nCac cong COM co san:")
            for p in ports:
                print(f"  {p.device:8s}  {p.description}")
        return

    # --- Check pyserial ---
    if serial is None:
        print("ERROR: Can cai pyserial:  pip install pyserial")
        sys.exit(1)

    # --- Banner ---
    print(f"\n{'='*60}")
    print(f"  RISC-V SoC — FPGA Verification (RFC 8439)")
    print(f"  Port: {args.port}  |  Baud: {args.baud}  |  Mode: {args.demo}")
    print(f"{'='*60}")

    # --- Run ---
    ser = open_serial(args.port, args.baud)
    print(f"  Ket noi {args.port} thanh cong")

    try:
        ok = send_and_verify(ser, args.demo)
    except KeyboardInterrupt:
        print(f"\n  Da huy boi nguoi dung.")
    finally:
        ser.close()
        print(f"\n  Da dong {args.port}.")


if __name__ == "__main__":
    main()
