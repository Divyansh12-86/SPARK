#
# Kernel entry point at 0x80000000 (Pure RV32I).
#
.section .text._entry
.globl _entry
_entry:
    # Set up a stack for C code on hart 0 (4096 bytes).
    la  sp, stack0
    lui t0, 1          # 4096 = 0x1000
    add sp, sp, t0

    # Jump to start() in start.c
    call start

spin:
    j spin

.section .bss
.align 12
.globl stack0
stack0:
    .space 4096
