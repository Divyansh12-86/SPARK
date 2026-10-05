#
# low-level code to handle user traps and returns.
#
.section .text
.globl trampoline
.align 4
trampoline:
.globl uservec
uservec:
    # placeholder for user mode vector
    sret

.globl userret
userret:
    # placeholder for user mode return
    sret
