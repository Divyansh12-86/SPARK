#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

// Start the first process, then run its scheduler.
void main() {
    uart_init();
    printfinit();

    printf("\n");
    printf("===============================================================\n");
    printf(" xv6 kernel is booting (SPARK RV32I / Sv32 Port)               \n");
    printf("===============================================================\n");
    printf("hart 0 starting\n");

    kinit();            // Physical page allocator
    printf("[xv6] Physical page allocator initialized\n");

    kvminit();          // Create kernel page table
    kvminithart();      // Turn on paging (Sv32 satp)
    printf("[xv6] Paging initialized (Sv32 satp enabled, satp=0x%x)\n", r_satp());

    trapinit();         // Trap vectors
    trapinithart();     // Install kernel trap vector (stvec)
    printf("[xv6] Supervisor trap vector installed (stvec=0x%x)\n", r_stvec());

    plicinit();         // Set up PLIC
    plicinithart();     // Enable interrupts for this hart

    binit();            // Buffer cache
    ramdisk_init();     // RAMDisk block device
    fsinit(ROOTDEV);    // xv6 filesystem
    printf("[xv6] RAMDisk block device mounted at 0x40000000 (size: %d blocks)\n", FSSIZE);
    printf("[xv6] File system initialized successfully\n");

    procinit();         // Process table
    printf("[xv6] Process subsystem initialized\n");

    printf("[xv6] Starting init process...\n");
    userinit();         // First user process

    // Run scheduler (does not return)
    scheduler();
}
