# ============================================================================
# File:        test_soc.s
# Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
# Description: RV32I Assembly test program for full SoC Verification.
#              - Writes "SPARK" string to memory-mapped UART at 0x1000_0000
#              - Configures CLINT timer compare at 0x2000_4000
#              - Verifies end-to-end SoC bus memory map
# ============================================================================

.text
.globl _start

_start:
    # 1. Base address of 16550 UART (0x1000_0000)
    lui  x1, 0x10000

    # Transmit 'S' (0x53 = 83)
    addi x2, x0, 83
    sw   x2, 0(x1)

    # Transmit 'P' (0x50 = 80)
    addi x2, x0, 80
    sw   x2, 0(x1)

    # Transmit 'A' (0x41 = 65)
    addi x2, x0, 65
    sw   x2, 0(x1)

    # Transmit 'R' (0x52 = 82)
    addi x2, x0, 82
    sw   x2, 0(x1)

    # Transmit 'K' (0x4B = 75)
    addi x2, x0, 75
    sw   x2, 0(x1)

    # 2. Configure CLINT mtimecmp at 0x2000_4000
    lui  x5, 0x20004        # x5 = 0x2000_4000 (mtimecmp lower word)
    addi x4, x0, 20         # compare threshold = 20 cycles
    sw   x4, 0(x5)          # mtimecmp[31:0] = 20
    sw   x0, 4(x5)          # mtimecmp[63:32] = 0

    # 3. Mark completion
    addi x6, x0, 1          # x6 = 1 (SoC test completed)

done:
    beq  x0, x0, done
