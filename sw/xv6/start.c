#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

void main();
void timerinit();

// entry.s jumps here in machine mode on hart 0.
void start() {
    // Set M Previous Privilege mode to Supervisor, for mret.
    uint32_t x = r_mstatus();
    x &= ~MSTATUS_MPP_MASK;
    x |= MSTATUS_MPP_S;
    w_mstatus(x);

    // Set M Exception Program Counter to main, for mret.
    // Requires gcc -mcmodel=medany
    w_mepc((uint32_t)main);

    // Disable paging for now.
    w_satp(0);

    // Delegate all interrupts and exceptions to supervisor mode.
    w_medeleg(0xffff);
    w_mideleg(0xffff);
    w_sie(r_sie() | SIE_SEIE | SIE_STIE | SIE_SSIE);

    // Configure machine-mode timer interrupt
    timerinit();

    // Switch to supervisor mode and jump to main().
    asm volatile("mret");
}

// Arrange to receive timer interrupts.
// They will arrive in machine mode at mtimecmp threshold.
void timerinit() {
    // Ask the CLINT for a timer interrupt after 100000 cycles.
    int interval = 100000;
    *(volatile uint32_t *)CLINT_MTIMECMP(0) = *(volatile uint32_t *)CLINT_MTIME + interval;

    // Enable machine-mode timer interrupts.
    w_mie(r_mie() | MIE_MTIE);
}
