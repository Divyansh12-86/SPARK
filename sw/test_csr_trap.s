# ============================================================================
# File:        test_csr_trap.s
# Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
# Description: RV32I Assembly verifying privileged CSR operations, synchronous
#              exception entry/return (ECALL), and asynchronous interrupt
#              preemption (Timer IRQ):
#                1. Sets mtvec to trap handler (0x60)
#                2. Writes and reads mscratch with CSRRW, CSRRS, CSRRC
#                3. Triggers ECALL exception -> returns via MRET
#                4. Enables MTIE and MIE, enters wait loop
#                5. Timer IRQ triggers asynchronous interrupt -> returns via MRET
# ============================================================================

.text
.globl _start

_start:
    # 1. Setup mtvec trap handler address to 0x60
    lui   x1, 0
    addi  x1, x1, 0x60          # x1 = 0x0000_0060
    csrrw x5, 0x305, x1         # mtvec <= 0x60, x5 <= old mtvec (0)
    csrrs x6, 0x305, x0         # x6 <= mtvec (0x60)

    # 2. Test CSR atomic read & write (mscratch)
    lui   x2, 0x12345
    addi  x2, x2, 0x678         # x2 = 0x1234_5678
    csrrw x7, 0x340, x2         # mscratch <= 0x1234_5678, x7 <= old mscratch (0)
    csrrs x8, 0x340, x0         # x8 <= mscratch (0x1234_5678)

    # 3. Test CSR atomic clear bits (mscratch)
    addi  x3, x0, 0x0F          # mask lower 4 bits
    csrrc x9, 0x340, x3         # mscratch <= 0x1234_5670, x9 <= old mscratch (0x1234_5678)
    csrrs x10, 0x340, x0        # x10 <= mscratch (0x1234_5670)

    # 4. Trigger synchronous Machine-mode ECALL
    ecall                       # Traps to mtvec (0x60)! mepc recorded as 0x2C

    # 5. Resumed here after MRET!
    addi  x15, x0, 1            # x15 = 1 (Resumed from trap)
    lui   x16, 0x0050A          # x16 = 0x0050A000 (Success sentinel)

    # 6. Setup Hardware Timer Interrupt (mie.MTIE = 1, mstatus.MIE = 1)
    addi  x4, x0, 0x80          # MTIE is bit 7
    csrrw x0, 0x304, x4         # mie <= 0x80
    addi  x4, x0, 0x08          # MIE is bit 3
    csrrs x0, 0x300, x4         # mstatus[3] <= 1 (enable global interrupts)

wait_loop:
    beq   x0, x0, wait_loop     # Waits for hardware timer_irq

    # ------------------------------------------------------------------------
    # Trap Handler located at 0x60
    # ------------------------------------------------------------------------
.org 0x60
trap_handler:
    csrrs x11, 0x342, x0        # x11 <= mcause
    blt   x11, x0, is_interrupt # If mcause < 0 (bit 31=1), it is an interrupt!

    # Synchronous Exception Path (ECALL)
    csrrs x12, 0x341, x0        # x12 <= mepc (expected = 0x2C)
    addi  x12, x12, 4           # mepc + 4 = 0x30
    csrrw x0, 0x341, x12        # mepc <= 0x30
    addi  x13, x0, 1            # x13 = 1 (ECALL handler executed)
    mret                        # Return to 0x30

    # ------------------------------------------------------------------------
    # Asynchronous Interrupt Path (Timer IRQ) located at 0x80
    # ------------------------------------------------------------------------
.org 0x80
is_interrupt:
    addi  x14, x0, 7            # x14 = 7 (Timer interrupt handled!)
    csrrw x0, 0x304, x0         # Disable interrupts (mie <= 0)
    mret                        # Return to wait_loop
