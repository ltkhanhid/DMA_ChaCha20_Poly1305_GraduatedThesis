#!/usr/bin/env python3
"""
RISC-V Assembly to Hex Converter
Manually assembles RISC-V assembly code to machine code hex file
Supports RV32I base instruction set
"""

import re
import sys

# Instruction formats and opcodes
OPCODES = {
    # R-type
    'add':  {'opcode': 0b0110011, 'funct3': 0b000, 'funct7': 0b0000000, 'type': 'R'},
    'sub':  {'opcode': 0b0110011, 'funct3': 0b000, 'funct7': 0b0100000, 'type': 'R'},
    'sll':  {'opcode': 0b0110011, 'funct3': 0b001, 'funct7': 0b0000000, 'type': 'R'},
    'slt':  {'opcode': 0b0110011, 'funct3': 0b010, 'funct7': 0b0000000, 'type': 'R'},
    'sltu': {'opcode': 0b0110011, 'funct3': 0b011, 'funct7': 0b0000000, 'type': 'R'},
    'xor':  {'opcode': 0b0110011, 'funct3': 0b100, 'funct7': 0b0000000, 'type': 'R'},
    'srl':  {'opcode': 0b0110011, 'funct3': 0b101, 'funct7': 0b0000000, 'type': 'R'},
    'sra':  {'opcode': 0b0110011, 'funct3': 0b101, 'funct7': 0b0100000, 'type': 'R'},
    'or':   {'opcode': 0b0110011, 'funct3': 0b110, 'funct7': 0b0000000, 'type': 'R'},
    'and':  {'opcode': 0b0110011, 'funct3': 0b111, 'funct7': 0b0000000, 'type': 'R'},
    
    # I-type (ALU)
    'addi':  {'opcode': 0b0010011, 'funct3': 0b000, 'type': 'I'},
    'slti':  {'opcode': 0b0010011, 'funct3': 0b010, 'type': 'I'},
    'sltiu': {'opcode': 0b0010011, 'funct3': 0b011, 'type': 'I'},
    'xori':  {'opcode': 0b0010011, 'funct3': 0b100, 'type': 'I'},
    'ori':   {'opcode': 0b0010011, 'funct3': 0b110, 'type': 'I'},
    'andi':  {'opcode': 0b0010011, 'funct3': 0b111, 'type': 'I'},
    'slli':  {'opcode': 0b0010011, 'funct3': 0b001, 'funct7': 0b0000000, 'type': 'I'},
    'srli':  {'opcode': 0b0010011, 'funct3': 0b101, 'funct7': 0b0000000, 'type': 'I'},
    'srai':  {'opcode': 0b0010011, 'funct3': 0b101, 'funct7': 0b0100000, 'type': 'I'},
    
    # I-type (Load)
    'lb':  {'opcode': 0b0000011, 'funct3': 0b000, 'type': 'I'},
    'lh':  {'opcode': 0b0000011, 'funct3': 0b001, 'type': 'I'},
    'lw':  {'opcode': 0b0000011, 'funct3': 0b010, 'type': 'I'},
    'lbu': {'opcode': 0b0000011, 'funct3': 0b100, 'type': 'I'},
    'lhu': {'opcode': 0b0000011, 'funct3': 0b101, 'type': 'I'},
    
    # I-type (JALR)
    'jalr': {'opcode': 0b1100111, 'funct3': 0b000, 'type': 'I'},
    
    # S-type
    'sb': {'opcode': 0b0100011, 'funct3': 0b000, 'type': 'S'},
    'sh': {'opcode': 0b0100011, 'funct3': 0b001, 'type': 'S'},
    'sw': {'opcode': 0b0100011, 'funct3': 0b010, 'type': 'S'},
    
    # B-type
    'beq':  {'opcode': 0b1100011, 'funct3': 0b000, 'type': 'B'},
    'bne':  {'opcode': 0b1100011, 'funct3': 0b001, 'type': 'B'},
    'blt':  {'opcode': 0b1100011, 'funct3': 0b100, 'type': 'B'},
    'bge':  {'opcode': 0b1100011, 'funct3': 0b101, 'type': 'B'},
    'bltu': {'opcode': 0b1100011, 'funct3': 0b110, 'type': 'B'},
    'bgeu': {'opcode': 0b1100011, 'funct3': 0b111, 'type': 'B'},
    
    # U-type
    'lui':   {'opcode': 0b0110111, 'type': 'U'},
    'auipc': {'opcode': 0b0010111, 'type': 'U'},
    
    # J-type
    'jal': {'opcode': 0b1101111, 'type': 'J'},
}

def parse_register(reg_str):
    """Convert register name to number (x0-x31)"""
    reg_str = reg_str.strip().lower()
    if reg_str.startswith('x'):
        return int(reg_str[1:])
    # ABI names
    abi_map = {
        'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
        't0': 5, 't1': 6, 't2': 7,
        's0': 8, 'fp': 8, 's1': 9,
        'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14, 'a5': 15, 'a6': 16, 'a7': 17,
        's2': 18, 's3': 19, 's4': 20, 's5': 21, 's6': 22, 's7': 23, 's8': 24, 's9': 25, 's10': 26, 's11': 27,
        't3': 28, 't4': 29, 't5': 30, 't6': 31
    }
    return abi_map.get(reg_str, 0)

def parse_immediate(imm_str):
    """Parse immediate value (decimal or hex)"""
    imm_str = imm_str.strip()
    if imm_str.startswith('0x'):
        return int(imm_str, 16)
    elif imm_str.startswith('-'):
        return int(imm_str)
    else:
        return int(imm_str)

def sign_extend(value, bits):
    """Sign extend a value to 32 bits"""
    sign_bit = 1 << (bits - 1)
    return (value & (sign_bit - 1)) - (value & sign_bit)

def encode_r_type(opcode, rd, funct3, rs1, rs2, funct7):
    """Encode R-type instruction"""
    instr = (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
    return instr & 0xFFFFFFFF

def encode_i_type(opcode, rd, funct3, rs1, imm):
    """Encode I-type instruction"""
    imm = imm & 0xFFF  # 12-bit immediate
    instr = (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
    return instr & 0xFFFFFFFF

def encode_s_type(opcode, funct3, rs1, rs2, imm):
    """Encode S-type instruction"""
    imm = imm & 0xFFF
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F
    instr = (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode
    return instr & 0xFFFFFFFF

def encode_b_type(opcode, funct3, rs1, rs2, imm):
    """Encode B-type instruction"""
    imm = imm & 0x1FFF  # 13-bit
    imm_12 = (imm >> 12) & 0x1
    imm_10_5 = (imm >> 5) & 0x3F
    imm_4_1 = (imm >> 1) & 0xF
    imm_11 = (imm >> 11) & 0x1
    instr = (imm_12 << 31) | (imm_10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_1 << 8) | (imm_11 << 7) | opcode
    return instr & 0xFFFFFFFF

def encode_u_type(opcode, rd, imm):
    """Encode U-type instruction"""
    imm = (imm & 0xFFFFF) << 12  # 20-bit immediate in upper bits
    instr = imm | (rd << 7) | opcode
    return instr & 0xFFFFFFFF

def encode_j_type(opcode, rd, imm):
    """Encode J-type instruction"""
    imm = imm & 0x1FFFFF  # 21-bit
    imm_20 = (imm >> 20) & 0x1
    imm_10_1 = (imm >> 1) & 0x3FF
    imm_11 = (imm >> 11) & 0x1
    imm_19_12 = (imm >> 12) & 0xFF
    instr = (imm_20 << 31) | (imm_19_12 << 12) | (imm_11 << 20) | (imm_10_1 << 21) | (rd << 7) | opcode
    return instr & 0xFFFFFFFF

def assemble_instruction(line, labels, pc):
    """Assemble a single instruction"""
    # Remove comments
    line = re.sub(r'#.*', '', line).strip()
    if not line:
        return None
    
    # Parse instruction
    parts = re.split(r'[,\s]+', line)
    mnemonic = parts[0].lower()
    
    if mnemonic not in OPCODES:
        return None
    
    info = OPCODES[mnemonic]
    instr_type = info['type']
    
    try:
        if instr_type == 'R':
            rd = parse_register(parts[1])
            rs1 = parse_register(parts[2])
            rs2 = parse_register(parts[3])
            return encode_r_type(info['opcode'], rd, info['funct3'], rs1, rs2, info['funct7'])
        
        elif instr_type == 'I':
            rd = parse_register(parts[1])
            if mnemonic in ['lw', 'lh', 'lb', 'lbu', 'lhu']:
                # Load: lw rd, offset(rs1)
                match = re.match(r'(-?\w+)\((\w+)\)', parts[2])
                if match:
                    imm = parse_immediate(match.group(1))
                    rs1 = parse_register(match.group(2))
                else:
                    imm = 0
                    rs1 = parse_register(parts[2])
            elif mnemonic == 'jalr':
                # jalr rd, offset(rs1) or jalr rd, rs1
                if '(' in parts[2]:
                    match = re.match(r'(-?\w+)\((\w+)\)', parts[2])
                    imm = parse_immediate(match.group(1))
                    rs1 = parse_register(match.group(2))
                else:
                    rs1 = parse_register(parts[2])
                    imm = parse_immediate(parts[3]) if len(parts) > 3 else 0
            else:
                # ALU: addi rd, rs1, imm
                rs1 = parse_register(parts[2])
                imm = parse_immediate(parts[3])
            
            if mnemonic in ['slli', 'srli', 'srai']:
                # Shift instructions have funct7
                imm = (info['funct7'] << 5) | (imm & 0x1F)
            
            return encode_i_type(info['opcode'], rd, info['funct3'], rs1, imm)
        
        elif instr_type == 'S':
            # sw rs2, offset(rs1)
            rs2 = parse_register(parts[1])
            match = re.match(r'(-?\w+)\((\w+)\)', parts[2])
            if match:
                imm = parse_immediate(match.group(1))
                rs1 = parse_register(match.group(2))
            else:
                imm = 0
                rs1 = parse_register(parts[2])
            return encode_s_type(info['opcode'], info['funct3'], rs1, rs2, imm)
        
        elif instr_type == 'B':
            # beq rs1, rs2, offset
            rs1 = parse_register(parts[1])
            rs2 = parse_register(parts[2])
            # Check if label or immediate
            if parts[3] in labels:
                imm = labels[parts[3]] - pc
            else:
                imm = parse_immediate(parts[3])
            return encode_b_type(info['opcode'], info['funct3'], rs1, rs2, imm)
        
        elif instr_type == 'U':
            # lui rd, imm
            rd = parse_register(parts[1])
            imm = parse_immediate(parts[2])
            return encode_u_type(info['opcode'], rd, imm)
        
        elif instr_type == 'J':
            # jal rd, offset
            rd = parse_register(parts[1])
            if parts[2] in labels:
                imm = labels[parts[2]] - pc
            else:
                imm = parse_immediate(parts[2])
            return encode_j_type(info['opcode'], rd, imm)
    
    except Exception as e:
        print(f"Error assembling '{line}': {e}")
        return None

def assemble(asm_file, hex_file):
    """Assemble RISC-V assembly to hex file"""
    with open(asm_file, 'r') as f:
        lines = f.readlines()
    
    # First pass: collect labels
    labels = {}
    pc = 0
    instructions = []
    
    for line in lines:
        line = re.sub(r'#.*', '', line).strip()
        if not line or line.startswith('.'):
            continue
        
        # Check for label
        if ':' in line:
            label = line.split(':')[0].strip()
            labels[label] = pc
            line = line.split(':', 1)[1].strip()
            if not line:
                continue
        
        instructions.append((pc, line))
        pc += 4
    
    # Second pass: assemble instructions
    machine_code = []
    for pc, line in instructions:
        instr = assemble_instruction(line, labels, pc)
        if instr is not None:
            machine_code.append(instr)
    
    # Write to hex file
    with open(hex_file, 'w') as f:
        for instr in machine_code:
            f.write(f"{instr:08x}\n")
    
    print(f"Assembled {len(machine_code)} instructions")
    print(f"Output: {hex_file}")
    
    # Print disassembly
    print("\nDisassembly:")
    for i, instr in enumerate(machine_code):
        print(f"0x{i*4:04x}: {instr:08x}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python asm2hex.py <input.asm> <output.hex>")
        sys.exit(1)
    
    assemble(sys.argv[1], sys.argv[2])
