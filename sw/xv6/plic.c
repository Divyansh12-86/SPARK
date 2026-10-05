#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

// Set up interrupt priorities and enables in the PLIC
void plicinit(void) {
    // Set priority = 1 for UART0 (IRQ 1)
    *(volatile uint32_t *)(PLIC + UART0_IRQ * 4) = 1;

    // Set priority = 1 for PIM Subsystem (IRQ 3)
    *(volatile uint32_t *)(PLIC + PIM_IRQ * 4) = 1;
}

void plicinithart(void) {
    // Enable UART0 and PIM interrupts in S-mode
    *(volatile uint32_t *)(PLIC_SENABLE) = (1 << UART0_IRQ) | (1 << PIM_IRQ);

    // Set this hart's S-mode priority threshold to 0
    *(volatile uint32_t *)(PLIC_SPRIORITY) = 0;
}

// Ask the PLIC what interrupt we should serve.
int plic_claim(void) {
    int irq = *(volatile uint32_t *)(PLIC_SCLAIM);
    return irq;
}

// Tell the PLIC we've served this IRQ.
void plic_complete(int irq) {
    *(volatile uint32_t *)(PLIC_SCLAIM) = irq;
}
