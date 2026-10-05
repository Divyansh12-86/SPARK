# ============================================================================
# File:        test_spark_soc.s
# Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
# Description: RV32I Assembly firmware verifying full SoC unification:
#              - Transmits "SPARK" over UART (0x1000_0000)
#              - Configures CLINT timer (0x2000_4000)
#              - Writes RGB color pixels into Framebuffer (0xF000_0000)
#              - Triggers PIM Hardware Acceleration (0x3000_0000)
# ============================================================================

.text
.globl _start

_start:
    # ------------------------------------------------------------------------
    # 1. Transmit "SPARK" on UART (0x1000_0000)
    # ------------------------------------------------------------------------
    lui  x1, 0x10000
    addi x2, x0, 83         # 'S'
    sw   x2, 0(x1)
    addi x2, x0, 80         # 'P'
    sw   x2, 0(x1)
    addi x2, x0, 65         # 'A'
    sw   x2, 0(x1)
    addi x2, x0, 82         # 'R'
    sw   x2, 0(x1)
    addi x2, x0, 75         # 'K'
    sw   x2, 0(x1)

    # ------------------------------------------------------------------------
    # 2. Configure CLINT timer compare at 0x2000_4000
    # ------------------------------------------------------------------------
    lui  x5, 0x20004
    addi x4, x0, 30         # compare threshold = 30 cycles
    sw   x4, 0(x5)
    sw   x0, 4(x5)

    # ------------------------------------------------------------------------
    # 3. Write pixels to Framebuffer VRAM at 0xF000_0000
    # ------------------------------------------------------------------------
    lui  x10, 0xF0000
    addi x11, x0, 0xF00     # Red pixel
    sw   x11, 0(x10)
    addi x11, x0, 0x0F0     # Green pixel
    sw   x11, 4(x10)
    addi x11, x0, 0x00F     # Blue pixel
    sw   x11, 8(x10)

    # ------------------------------------------------------------------------
    # 4. Trigger PIM MMIO at 0x3000_0000
    # ------------------------------------------------------------------------
    lui  x20, 0x30000
    addi x21, x0, 16        # rs1 = 16 elements
    sw   x21, 8(x20)        # write to 0x3000_0008 (PIM rs1 register)
    addi x22, x0, 4         # cmd = PIM_CFG (opcode 4)
    sw   x22, 0(x20)        # write to 0x3000_0000 (trigger command)

    # ------------------------------------------------------------------------
    # 5. Signal Completion
    # ------------------------------------------------------------------------
    addi x31, x0, 1         # x31 = 1 (All SoC subsystems exercised)

done:
    beq  x0, x0, done
