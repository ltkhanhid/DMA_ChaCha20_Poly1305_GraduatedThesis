#!/usr/bin/env python3
"""Compare two HEX files"""
import sys

def read_hex(filename):
    with open(filename, 'r') as f:
        return [line.strip().lower() for line in f if line.strip()]

def compare(file1, file2):
    hex1 = read_hex(file1)
    hex2 = read_hex(file2)
    
    print(f"=== Comparing {file1} vs {file2} ===\n")
    print(f"{file1}: {len(hex1)} instructions")
    print(f"{file2}: {len(hex2)} instructions\n")
    
    max_len = max(len(hex1), len(hex2))
    matches = diffs = 0
    
    print(f"{'Addr':<8} {'File1':<12} {'File2':<12} {'Status'}")
    print("-" * 50)
    
    for i in range(max_len):
        addr = i * 4
        v1 = hex1[i] if i < len(hex1) else "--------"
        v2 = hex2[i] if i < len(hex2) else "--------"
        
        if v1 == v2:
            status = "✅"
            matches += 1
        else:
            status = "❌ DIFF"
            diffs += 1
        
        print(f"0x{addr:04x}   {v1:<12} {v2:<12} {status}")
    
    print("-" * 50)
    print(f"\n✅ {matches} matches, ❌ {diffs} differences")
    
    if diffs == 0:
        print("\n🎉 FILES ARE IDENTICAL!")

if __name__ == "__main__":
    compare(sys.argv[1], sys.argv[2])
