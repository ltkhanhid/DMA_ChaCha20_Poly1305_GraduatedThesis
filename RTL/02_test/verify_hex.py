#!/usr/bin/env python3
"""
Verify HEX file matches objdump output
Usage: python verify_hex.py <object_file> <hex_file>
"""

import subprocess
import sys
import re

def get_objdump_instructions(obj_file):
    """Extract machine codes from objdump"""
    result = subprocess.run(
        ['riscv-none-elf-objdump', '-d', obj_file],
        capture_output=True, text=True
    )
    
    instructions = []
    # Pattern: "   0:   10000537   lui a0,0x10000"
    pattern = r'^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s+'
    
    for line in result.stdout.split('\n'):
        match = re.match(pattern, line)
        if match:
            instructions.append(match.group(1).lower())
    
    return instructions

def get_hex_file_instructions(hex_file):
    """Read instructions from HEX file"""
    instructions = []
    with open(hex_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line and len(line) == 8:
                instructions.append(line.lower())
    return instructions

def verify(obj_file, hex_file):
    print(f"=== Verifying {hex_file} against {obj_file} ===\n")
    
    objdump_instr = get_objdump_instructions(obj_file)
    hex_instr = get_hex_file_instructions(hex_file)
    
    print(f"objdump: {len(objdump_instr)} instructions")
    print(f"HEX file: {len(hex_instr)} instructions\n")
    
    if len(objdump_instr) != len(hex_instr):
        print(f"❌ ERROR: Instruction count mismatch!")
        return False
    
    all_match = True
    print(f"{'Addr':<6} {'objdump':<12} {'HEX file':<12} {'Status'}")
    print("-" * 45)
    
    for i, (obj, hex_val) in enumerate(zip(objdump_instr, hex_instr)):
        addr = i * 4
        if obj == hex_val:
            status = "✅"
        else:
            status = "❌ MISMATCH"
            all_match = False
        print(f"0x{addr:04x}  {obj:<12} {hex_val:<12} {status}")
    
    print("-" * 45)
    if all_match:
        print(f"\n✅ VERIFIED: All {len(objdump_instr)} instructions match!")
    else:
        print(f"\n❌ FAILED: Some instructions don't match!")
    
    return all_match

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python verify_hex.py <object_file> <hex_file>")
        sys.exit(1)
    
    success = verify(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)
