#!/usr/bin/env python3
"""
Convert RISC-V ELF/binary to HEX format for instruction memory
Usage: python elf2hex.py input.o output.hex
"""

import sys
import subprocess
import os

def elf_to_hex(input_file, output_file):
    # Get toolchain path
    objcopy = "riscv-none-elf-objcopy"
    objdump = "riscv-none-elf-objdump"
    
    # Create binary file
    bin_file = input_file.replace('.o', '.bin').replace('.elf', '.bin')
    
    # Extract .text section to binary
    cmd = f'{objcopy} -O binary -j .text {input_file} {bin_file}'
    print(f"Running: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        return False
    
    # Read binary and convert to hex
    with open(bin_file, 'rb') as f:
        binary_data = f.read()
    
    # Write hex file (32-bit words, little endian)
    with open(output_file, 'w') as f:
        for i in range(0, len(binary_data), 4):
            if i + 4 <= len(binary_data):
                word = binary_data[i:i+4]
                # Little endian to 32-bit hex
                hex_val = (word[3] << 24) | (word[2] << 16) | (word[1] << 8) | word[0]
                f.write(f'{hex_val:08x}\n')
            else:
                # Pad remaining bytes
                word = binary_data[i:]
                hex_val = 0
                for j, b in enumerate(word):
                    hex_val |= b << (j * 8)
                f.write(f'{hex_val:08x}\n')
    
    print(f"Created: {output_file}")
    print(f"Total instructions: {len(binary_data) // 4}")
    
    # Show disassembly
    print("\n=== Disassembly ===")
    cmd = f'{objdump} -d {input_file}'
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    print(result.stdout)
    
    # Cleanup
    os.remove(bin_file)
    
    return True

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python elf2hex.py input.o output.hex")
        sys.exit(1)
    
    elf_to_hex(sys.argv[1], sys.argv[2])
