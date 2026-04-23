#!/usr/bin/env python3
"""
fpga_interactive.py — Script 2: Nhap plaintext bat ky, gui FPGA, nhan ket qua
===============================================================================
Cho phep nhap text tu ban phim hoac command line → gui len FPGA → nhan CT/TAG.
Python tu dong tinh expected CT/TAG tu firmware key/nonce → verify luon.

Cach dung:
  python fpga_interactive.py --port COM3 --demo aead
  python fpga_interactive.py --port COM3 --demo aead --text "Hello RISC-V!"
  python fpga_interactive.py --port COM3 --demo chacha --text "Test 123"

Flow:
  1. Ban nhap text bat ky (toi da 64 ky tu)
  2. Script pad thanh 64 bytes (them dau cach)
  3. Gui 64 bytes qua UART toi FPGA
  4. FPGA encrypt → tra ve CT (+ TAG neu AEAD)
  5. Python tu tinh expected tu cung key/nonce
  6. So sanh byte-by-byte → PASS/FAIL
  7. Hoi: gui tiep hay thoat?

Yeu cau: pip install pyserial cryptography
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
    print("ERROR: Can cai pyserial:  pip install pyserial")
    sys.exit(1)

try:
    from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
    HAS_CRYPTO = True
except ImportError:
    HAS_CRYPTO = False

# ============================================================
#  Firmware Key/Nonce (co dinh trong demo_*.S)
# ============================================================

# ChaCha20-only: key=00..1f, nonce=00000000 4a000000 00000000, counter=1
FW_CHACHA_KEY = bytes(range(0x00, 0x20))
FW_CHACHA_NONCE16 = struct.pack('<I', 1) + bytes([
    0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x4a, 0x00,0x00,0x00,0x00])

# AEAD: key=80..9f, nonce=07:00:00:00:40:41:42:43:44:45:46:47
FW_AEAD_KEY = bytes(range(0x80, 0xa0))
FW_AEAD_NONCE = bytes([0x07,0x00,0x00,0x00, 0x40,0x41,0x42,0x43, 0x44,0x45,0x46,0x47])
FW_AEAD_AAD = bytes([0x50,0x51,0x52,0x53, 0xc0,0xc1,0xc2,0xc3, 0xc4,0xc5,0xc6,0xc7])


# ============================================================
#  Helper Functions
# ============================================================

def encode_plaintext(text):
    """Text -> 64 bytes (UTF-8, pad spaces)."""
    raw = text.encode('utf-8', errors='replace')[:64]
    return raw + b' ' * (64 - len(raw))


def compute_expected(plaintext, mode):
    """Tinh expected CT/TAG tu firmware key/nonce. Tra ve (ct, tag)."""
    if not HAS_CRYPTO:
        return None, None
    pt64 = (plaintext + b'\x00' * 64)[:64]
    if mode == "chacha":
        c = Cipher(algorithms.ChaCha20(FW_CHACHA_KEY, FW_CHACHA_NONCE16), mode=None)
        enc = c.encryptor()
        return enc.update(pt64) + enc.finalize(), None
    else:
        aead = ChaCha20Poly1305(FW_AEAD_KEY)
        ct_tag = aead.encrypt(FW_AEAD_NONCE, pt64, FW_AEAD_AAD)
        return ct_tag[:-16], ct_tag[-16:]


def hex_dump(data, cols=16):
    lines = []
    for i in range(0, len(data), cols):
        chunk = data[i:i+cols]
        h = " ".join(f"{b:02x}" for b in chunk)
        a = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"    {i:04x}: {h:<{cols*3}}  {a}")
    return "\n".join(lines)


def compare_bytes(expected, actual, label):
    if expected is None:
        print(f"  {label}: (khong co expected — cai 'pip install cryptography')")
        return True
    if len(expected) != len(actual):
        print(f"  {label}: LENGTH MISMATCH")
        return False
    errors = 0
    for i, (e, a) in enumerate(zip(expected, actual)):
        if e != a:
            if errors < 5:
                print(f"  {label}[{i}]: expected 0x{e:02x}, got 0x{a:02x}")
            errors += 1
    if errors == 0:
        print(f"  {label}: {len(expected)}/{len(expected)} bytes MATCH")
    else:
        print(f"  {label}: {errors}/{len(expected)} bytes MISMATCH")
    return errors == 0


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
        sys.exit(1)


# ============================================================
#  Core: Send custom plaintext → Receive → Verify
# ============================================================

def send_custom(ser, plaintext, mode):
    """Gui plaintext bat ky → nhan CT/TAG → verify."""

    rx_len = 64 if mode == "chacha" else 80
    exp_ct, exp_tag = compute_expected(plaintext, mode)

    # Show what we're sending
    pt_display = plaintext.decode('utf-8', errors='replace').rstrip()
    print(f"\n[TX] Gui 64 bytes:")
    print(f'  "{pt_display}"')
    print(hex_dump(plaintext))

    # Send
    ser.reset_input_buffer()
    t_start = time.perf_counter()

    for byte in plaintext:
        ser.write(bytes([byte]))
        time.sleep(0.001)

    ser.flush()
    print(f"\n  Da gui. Cho FPGA xu ly...")

    # Receive
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
        print(f"\n  TIMEOUT: Nhan {len(response)}/{rx_len} bytes")
        print(f"  -> Kiem tra: FPGA nap dung firmware? Reset FPGA?")
        return False

    # Display
    ct = bytes(response[:64])
    tag = bytes(response[64:]) if rx_len > 64 else None

    print(f"\n[RX] Nhan {len(response)} bytes trong {elapsed_ms:.1f} ms:")
    print(f"\n  Ciphertext ({len(ct)} bytes):")
    print(hex_dump(ct))
    if tag:
        print(f"\n  Tag ({len(tag)} bytes):")
        print(hex_dump(tag))

    # Verify
    print(f"\n[VERIFY]")
    ct_ok = compare_bytes(exp_ct, ct, "Ciphertext")
    tag_ok = True
    if exp_tag and tag:
        tag_ok = compare_bytes(exp_tag, tag, "Tag")

    # Timing
    print(f"\n  Thoi gian: {elapsed_ms:.1f} ms")

    if exp_ct is None:
        print(f"\n  (Cai 'pip install cryptography' de verify tu dong)")
    elif ct_ok and tag_ok:
        print(f"\n  >>> PASS <<<")
    else:
        print(f"\n  >>> FAIL <<<")

    return ct_ok and tag_ok


# ============================================================
#  Main
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="FPGA Interactive — Gui plaintext bat ky",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Vi du:
  python fpga_interactive.py --port COM3 --demo aead
  python fpga_interactive.py --port COM3 --demo aead --text "xin chao"
  python fpga_interactive.py --port COM3 --demo chacha --text "Hello!"
        """,
    )
    parser.add_argument("--port", "-p", default="COM3")
    parser.add_argument("--demo", "-d", default="aead",
                        choices=["chacha", "aead", "aead_dma"])
    parser.add_argument("--text", "-t", default=None,
                        help="Plaintext (toi da 64 ky tu). Neu khong co → hoi nhap.")
    parser.add_argument("--baud", "-b", type=int, default=115200)
    parser.add_argument("--list-ports", action="store_true")
    args = parser.parse_args()

    if args.list_ports:
        from serial.tools.list_ports import comports
        for p in comports():
            print(f"  {p.device:8s}  {p.description}")
        return

    if not HAS_CRYPTO:
        print("WARNING: 'cryptography' chua cai. Chi gui/nhan, khong verify duoc.")
        print("  pip install cryptography")

    # Banner
    mode_name = {"chacha": "ChaCha20", "aead": "AEAD CPU-only", "aead_dma": "AEAD DMA"}
    print(f"\n{'='*60}")
    print(f"  FPGA Interactive Demo — {mode_name[args.demo]}")
    print(f"  Port: {args.port}  |  Baud: {args.baud}")
    print(f"{'='*60}")

    ser = open_serial(args.port, args.baud)
    print(f"  Ket noi {args.port} thanh cong\n")

    try:
        if args.text:
            # Single run from command line
            pt = encode_plaintext(args.text)
            send_custom(ser, pt, args.demo)
        else:
            # Interactive loop
            run_num = 1
            while True:
                print(f"\n{'─'*60}")
                print(f"  Lan #{run_num}")
                print(f"  Nhap plaintext (toi da 64 ky tu), hoac 'q' de thoat:")
                try:
                    user_in = input("  > ").strip()
                except EOFError:
                    break

                if not user_in or user_in.lower() == 'q':
                    break

                pt = encode_plaintext(user_in)
                send_custom(ser, pt, args.demo)
                run_num += 1

                ser.reset_input_buffer()

    except KeyboardInterrupt:
        print(f"\n  Da huy.")
    finally:
        ser.close()
        print(f"  Da dong {args.port}.")


if __name__ == "__main__":
    main()
