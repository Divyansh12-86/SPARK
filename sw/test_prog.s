# ============================================================================
# File:        test_prog.s
# Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
# Description: RV32I Assembly test program for Single-Cycle CPU verification.
# ============================================================================

.text
.globl _start

_start:
    # 1. Arithmetic with immediates and registers
    addi x1, x0, 10         # x1 = 10
    addi x2, x0, 20         # x2 = 20
    add  x3, x1, x2         # x3 = 10 + 20 = 30
    sub  x4, x2, x1         # x4 = 20 - 10 = 10

    # 2. Data Memory Store and Load
    sw   x3, 4(x0)          # mem[4] = 30
    lw   x5, 4(x0)          # x5 = mem[4] = 30

    # 3. Conditional Branch (BEQ)
    beq  x3, x5, branch_dst # Taken because x3 == x5 (30 == 30)
    addi x6, x0, 99         # Skipped! x6 must remain 0

branch_dst:
    addi x7, x0, 42         # x7 = 42

    # 4. Upper Immediate (LUI)
    lui  x8, 0x12345        # x8 = 0x12345000

    # 5. Unconditional Jump and Link (JAL)
    jal  x9, jump_dst       # Jump to jump_dst, x9 = PC + 4 (return address = 0x28)
    addi x10, x0, 88        # Skipped! x10 must remain 0

jump_dst:
    addi x11, x0, 1         # x11 = 1 (marks successful program completion)

done:
    beq  x0, x0, done       # Infinite loop (halt)
