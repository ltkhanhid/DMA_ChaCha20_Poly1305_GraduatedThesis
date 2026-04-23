#!/usr/bin/env python3
"""Disassemble RISC-V hex file to check instructions"""

def decode_riscv(instr):
    """Simple RISC-V decoder for RV32I"""
    opcode = instr & 0x7F
    rd = (instr >> 7) & 0x1F
    funct3 = (instr >> 12) & 0x7
    rs1 = (instr >> 15) & 0x1F
    rs2 = (instr >> 20) & 0x1F
    funct7 = (instr >> 25) & 0x7F
    
    # LUI
    if opcode == 0x37:
        imm = instr & 0xFFFFF000
        return f"lui x{rd}, 0x{imm>>12:05x}"
    
    # LOAD
    elif opcode == 0x03:
        imm = (instr >> 20) & 0xFFF
        if imm & 0x800:
            imm |= 0xFFFFF000  # Sign extend
        return f"lw x{rd}, {imm}(x{rs1})"
    
    # STORE
    elif opcode == 0x23:
        imm = ((instr >> 25) << 5) | ((instr >> 7) & 0x1F)
        if imm & 0x800:
            imm |= 0xFFFFF000
        return f"sw x{rs2}, {imm}(x{rs1})"
    
    # BRANCH
    elif opcode == 0x63:
        imm = (((instr >> 31) & 0x1) << 12) | (((instr >> 7) & 0x1) << 11) | \
              (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1)
        if imm & 0x1000:
            imm |= 0xFFFFE000
        if funct3 == 0x0:
            return f"beq x{rs1}, x{rs2}, {imm}"
        elif funct3 == 0x1:
            return f"bne x{rs1}, x{rs2}, {imm}"
        return f"b??? x{rs1}, x{rs2}, {imm}"
    
    # OP-IMM (addi, andi, ori, srli, etc)
    elif opcode == 0x13:
        imm = (instr >> 20) & 0xFFF
        if funct3 == 0x7:  # ANDI
            return f"andi x{rd}, x{rs1}, 0x{imm:x}"
        elif funct3 == 0x6:  # ORI
            return f"ori x{rd}, x{rs1}, 0x{imm:x}"
        elif funct3 == 0x5:  # SRLI/SRAI
            shamt = (instr >> 20) & 0x1F
            if funct7 == 0x00:
                return f"srli x{rd}, x{rs1}, {shamt}"
            else:
                return f"srai x{rd}, x{rs1}, {shamt}"
        elif funct3 == 0x0:  # ADDI
            if imm & 0x800:
                imm |= 0xFFFFF000
            return f"addi x{rd}, x{rs1}, {imm}"
        return f"op-imm x{rd}, x{rs1}, 0x{imm:x}"
    
    # JAL
    elif opcode == 0x6F:
        imm = ((instr >> 31) << 20) | (((instr >> 12) & 0xFF) << 12) | \
              (((instr >> 20) & 0x1) << 11) | (((instr >> 21) & 0x3FF) << 1)
        if imm & 0x100000:
            imm |= 0xFFE00000
        return f"jal x{rd}, {imm}"
    
    return f"??? 0x{instr:08x}"

# Read hex file
with open("../02_test/uart.hex", "r") as f:
    lines = f.readlines()

print("Disassembly of uart.hex:")
print("=" * 60)
addr = 0
for line in lines:
    line = line.strip()
    if line and not line.startswith('#'):
        instr = int(line, 16)
        disasm = decode_riscv(instr)
        print(f"0x{addr:08x}:  {instr:08x}  {disasm}")
        addr += 4
