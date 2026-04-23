# ==============================================================================
# HUONG DAN SU DUNG GNU RISC-V TOOLCHAIN CHO RV32I
# ==============================================================================
# Author: Created for DATN project
# Toolchain: xPack GNU RISC-V Embedded GCC 14.2.0
# ==============================================================================

# ******************************************************************************
# 1. CAI DAT VA KIEM TRA
# ******************************************************************************

# Toolchain da duoc cai dat tai: C:\riscv-toolchain
# Cac lenh chinh:
#   - riscv-none-elf-as      : Assembler
#   - riscv-none-elf-gcc     : C Compiler  
#   - riscv-none-elf-ld      : Linker
#   - riscv-none-elf-objdump : Disassembler
#   - riscv-none-elf-objcopy : Binary conversion

# Kiem tra version:
# riscv-none-elf-gcc --version

# ******************************************************************************
# 2. CAU TRUC FILE ASSEMBLY (.S)
# ******************************************************************************

# --- DINH NGHIA HANG SO (Constants) ---
# .equ TEN, GIA_TRI
.equ UART_BASE, 0x10020000
.equ LEDR_BASE, 0x10000000
.equ SW_BASE,   0x10001000

# --- SECTIONS ---
# .section .text     : Code section (instructions)
# .section .data     : Initialized data
# .section .bss      : Uninitialized data
# .section .rodata   : Read-only data

# --- LABELS VA DIRECTIVES ---
# .globl _start      : Export symbol to linker
# _start:            : Entry point label
# .word 0x12345678   : 32-bit data
# .byte 0x00         : 8-bit data
# .string "Hello"    : ASCII string with null terminator

# ******************************************************************************
# 3. TAP LENH RV32I CO BAN
# ******************************************************************************

# === LOAD/STORE ===
# lui  rd, imm[31:12]   : Load Upper Immediate (rd = imm << 12)
# li   rd, imm          : Load Immediate (pseudo-instruction)
# lw   rd, offset(rs1)  : Load Word
# sw   rs2, offset(rs1) : Store Word
# lb/lh/lbu/lhu         : Load byte/half (signed/unsigned)
# sb/sh                 : Store byte/half

# === ARITHMETIC ===
# add  rd, rs1, rs2     : rd = rs1 + rs2
# addi rd, rs1, imm     : rd = rs1 + imm
# sub  rd, rs1, rs2     : rd = rs1 - rs2
# and  rd, rs1, rs2     : rd = rs1 & rs2
# andi rd, rs1, imm     : rd = rs1 & imm
# or   rd, rs1, rs2     : rd = rs1 | rs2
# ori  rd, rs1, imm     : rd = rs1 | imm
# xor  rd, rs1, rs2     : rd = rs1 ^ rs2
# sll  rd, rs1, rs2     : rd = rs1 << rs2
# slli rd, rs1, shamt   : rd = rs1 << shamt
# srl  rd, rs1, rs2     : rd = rs1 >> rs2 (logical)
# srli rd, rs1, shamt   : rd = rs1 >> shamt (logical)
# sra  rd, rs1, rs2     : rd = rs1 >> rs2 (arithmetic)
# srai rd, rs1, shamt   : rd = rs1 >> shamt (arithmetic)

# === BRANCH (Conditional Jump) ===
# beq  rs1, rs2, label  : Branch if rs1 == rs2
# bne  rs1, rs2, label  : Branch if rs1 != rs2
# blt  rs1, rs2, label  : Branch if rs1 < rs2 (signed)
# bge  rs1, rs2, label  : Branch if rs1 >= rs2 (signed)
# bltu rs1, rs2, label  : Branch if rs1 < rs2 (unsigned)
# bgeu rs1, rs2, label  : Branch if rs1 >= rs2 (unsigned)

# === JUMP ===
# jal  rd, label        : Jump and Link (rd = PC+4, PC = label)
# jalr rd, rs1, offset  : Jump and Link Register
# j    label            : Jump (pseudo, = jal x0, label)
# ret                   : Return (pseudo, = jalr x0, x1, 0)

# === COMPARISON ===
# slt  rd, rs1, rs2     : rd = (rs1 < rs2) ? 1 : 0 (signed)
# slti rd, rs1, imm     : rd = (rs1 < imm) ? 1 : 0 (signed)
# sltu rd, rs1, rs2     : rd = (rs1 < rs2) ? 1 : 0 (unsigned)

# === PSEUDO-INSTRUCTIONS ===
# mv   rd, rs           : Move (= addi rd, rs, 0)
# li   rd, imm          : Load immediate (may expand to lui+addi)
# la   rd, label        : Load address (= auipc + addi)
# nop                   : No operation (= addi x0, x0, 0)
# not  rd, rs           : Bitwise NOT (= xori rd, rs, -1)
# neg  rd, rs           : Negate (= sub rd, x0, rs)

# ******************************************************************************
# 4. CAC LENH BIEN DICH (Compile Commands)
# ******************************************************************************

# --- Bien dich file .S thanh .o (Object file) ---
# riscv-none-elf-as -march=rv32i -mabi=ilp32 -o output.o input.S

# --- Neu dung lenh CSR (Zicsr extension) ---
# riscv-none-elf-as -march=rv32i_zicsr -mabi=ilp32 -o output.o input.S

# --- Disassemble de xem machine code ---
# riscv-none-elf-objdump -d output.o

# --- Chuyen sang HEX bang script Python ---
# python elf2hex.py output.o output.hex

# ******************************************************************************
# 5. VI DU HOAN CHINH: LED BLINK
# ******************************************************************************

.equ LEDR_BASE, 0x10000000
.equ DELAY_COUNT, 5000000

.section .text
.globl _start

_start:
    # Load LEDR base address
    lui  x10, %hi(LEDR_BASE)    # x10 = 0x10000000
    
main_loop:
    # Turn all LEDs ON
    li   x5, 0x3FF              # 10 bits = 10 LEDs
    sw   x5, 0(x10)             # Write to LEDR
    
    # Delay
    jal  x1, delay
    
    # Turn all LEDs OFF
    sw   x0, 0(x10)
    
    # Delay
    jal  x1, delay
    
    # Loop
    j    main_loop

# Delay subroutine
delay:
    lui  x6, %hi(DELAY_COUNT)
    addi x6, x6, %lo(DELAY_COUNT)
delay_loop:
    addi x6, x6, -1
    bne  x6, x0, delay_loop
    ret

# ******************************************************************************
# 6. VI DU: UART POLLING
# ******************************************************************************

# .equ UART_BASE, 0x10020000
# .equ UART_TX, 0x00
# .equ UART_RX, 0x04
#
# # Send one byte
# send_byte:
#     lui  x20, %hi(UART_BASE)
#     ori  x5, x5, 0x100        # Set send flag (bit 8)
#     sw   x5, UART_TX(x20)     # Write to TX register
#     ret
#
# # Receive one byte (blocking)
# recv_byte:
#     lui  x20, %hi(UART_BASE)
# wait_rx:
#     lw   x5, UART_RX(x20)     # Read RX register
#     srli x6, x5, 31           # Check valid bit [31]
#     beq  x6, x0, wait_rx      # Wait until valid
#     andi x5, x5, 0xFF         # Extract data byte
#     ret

# ******************************************************************************
# 7. VI DU: CSR INSTRUCTIONS (Can -march=rv32i_zicsr)
# ******************************************************************************

# # Setup interrupt handler
# la   t0, isr_handler
# csrw mtvec, t0              # Set trap vector
#
# # Enable machine timer interrupt
# li   t0, 0x80               # MIE.MTIE bit
# csrs mie, t0
#
# # Enable global interrupt
# li   t0, 0x8                # MSTATUS.MIE bit  
# csrs mstatus, t0
#
# # Interrupt handler
# isr_handler:
#     # ... handle interrupt ...
#     mret                    # Return from interrupt

# ******************************************************************************
# 8. WORKFLOW HOAN CHINH
# ******************************************************************************

# Step 1: Viet code assembly (.S file)
#         File: program.S

# Step 2: Bien dich thanh object file
#         riscv-none-elf-as -march=rv32i -mabi=ilp32 -o program.o program.S

# Step 3: Kiem tra disassembly (optional)
#         riscv-none-elf-objdump -d program.o

# Step 4: Chuyen thanh HEX file
#         python elf2hex.py program.o program.hex

# Step 5: Dung HEX file voi instr_mem.sv
#         $readmemh("program.hex", mem_array);

# ******************************************************************************
# 9. LOI THUONG GAP
# ******************************************************************************

# Error: "unknown CSR"
# -> Them _zicsr: -march=rv32i_zicsr

# Error: "illegal operand"  
# -> Kiem tra lai ten thanh ghi (x0-x31 hoac ten: t0-t6, s0-s11, a0-a7)

# Error: "offset out of range"
# -> Immediate chi 12-bit (-2048 to 2047), dung lui + addi

# Warning: "unrecognized opcode"
# -> Kiem tra -march=rv32i (khong phai rv64)

# ******************************************************************************
# 10. BANG THANH GHI (Register Convention)
# ******************************************************************************

# x0  (zero) : Always 0
# x1  (ra)   : Return address
# x2  (sp)   : Stack pointer
# x3  (gp)   : Global pointer
# x4  (tp)   : Thread pointer
# x5  (t0)   : Temporary 0
# x6  (t1)   : Temporary 1
# x7  (t2)   : Temporary 2
# x8  (s0/fp): Saved / Frame pointer
# x9  (s1)   : Saved 1
# x10 (a0)   : Argument 0 / Return value
# x11 (a1)   : Argument 1 / Return value
# x12-x17 (a2-a7): Arguments 2-7
# x18-x27 (s2-s11): Saved 2-11
# x28-x31 (t3-t6): Temporaries 3-6
