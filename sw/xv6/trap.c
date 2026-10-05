#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

extern char kernelvec[];

void trapinit(void) {
    // initialize trap locks if SMP
}

// set up to take exceptions and traps while in the kernel.
void trapinithart(void) {
    w_stvec((uint32_t)kernelvec);
}

// Interrupts and exceptions in kernel code come here via kernelvec.
void kerneltrap() {
    uint32_t which_dev = 0;
    uint32_t sepc = r_sepc();
    uint32_t sstatus = r_sstatus();
    uint32_t scause = r_scause();

    if ((sstatus & SSTATUS_SPP) == 0)
        panic("kerneltrap: not from supervisor mode");

    if (scause & 0x80000000) {
        // Asynchronous trap (interrupt)
        uint32_t irq = scause & 0x7FFFFFFF;
        if (irq == 5) {
            // Supervisor timer interrupt
            which_dev = 2;
        } else if (irq == 9) {
            // Supervisor external interrupt (PLIC)
            int claim = plic_claim();
            if (claim == UART0_IRQ) {
                uart_intr();
            }
            if (claim)
                plic_complete(claim);
            which_dev = 1;
        }
    } else {
        // Synchronous exception
        printf("kerneltrap: unexpected scause=0x%x sepc=0x%x stval=0x%x\n", scause, sepc, r_stval());
        panic("kerneltrap exception");
    }

    // Give up CPU if this is a timer interrupt
    if (which_dev == 2 && myproc() != 0)
        yield();

    // Restore sepc and sstatus
    w_sepc(sepc);
    w_sstatus(sstatus);
}

void usertrapret(void) {
    // Return to user space
}
