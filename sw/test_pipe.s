# ============================================================================
# File:        test_pipe.s
# Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
# Description: RV32I Assembly test program for 5-Stage Pipelined CPU.
#              Stresses:
#                - RAW Data Hazards (EX-to-EX and MEM-to-EX forwarding)
#                - Load-Use Data Hazard (1-cycle hardware stall)
#                - Control Hazard (branch taken flush)
#                - Jump Hazard (JAL return address and flush)
# ============================================================================

.text
.globl _start

_start:
    # 1. RAW Data Hazard: back-to-back dependency (EX-to-EX forwarding)
    addi x1, x0, 10         # x1 = 10
    addi x2, x1, 5          # x2 = x1 + 5 = 15 (requires EX-to-EX forwarding of x1)
    add  x3, x1, x2         # x3 = x1 + x2 = 25 (requires MEM-to-EX and EX-to-EX forwarding)

    # 2. Load-Use Hazard: load followed immediately by consumer instruction
    sw   x3, 8(x0)          # mem[8] = 25
    lw   x4, 8(x0)          # x4 = 25 (from memory)
    addi x5, x4, 1          # x5 = x4 + 1 = 26 (LOAD-USE HAZARD: hardware must stall 1 cycle)

    # 3. Control Hazard: Branch Taken (must flush instructions currently in IF and ID)
    beq  x3, x3, branch_dst # Branch taken (25 == 25)
    addi x6, x0, 99         # FLUSHED 1! x6 must remain 0
    addi x7, x0, 99         # FLUSHED 2! x7 must remain 0

branch_dst:
    addi x8, x0, 77         # x8 = 77 (Branch destination reached)

    # 4. Jump Hazard: JAL (must save PC+4 and flush following instruction)
    jal  x9, jump_dst       # Jump to jump_dst, x9 = PC + 4
    addi x10, x0, 88        # FLUSHED! x10 must remain 0

jump_dst:
    addi x11, x0, 1         # Completion flag: x11 = 1

done:
    beq  x0, x0, done       # Infinite loop
