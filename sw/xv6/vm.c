#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

// The kernel's page table.
pagetable_t kernel_pagetable;

extern char etext[];      // kernel.ld sets this to end of kernel code.
extern char trampoline[]; // trampoline.s

// Return the address of the PTE in page table that corresponds to
// virtual address va.  If alloc!=0, create any required page-table pages.
pte_t* walk(pagetable_t pagetable, uint32_t va, int alloc) {
    if (va >= 0xFFFFFFFF)
        panic("walk: va out of range");

    // In Sv32, level 1 is the page directory (va[31:22])
    uint32_t pde_idx = PX(1, va);
    pte_t *pde = &pagetable[pde_idx];

    if (*pde & PTE_V) {
        pagetable = (pagetable_t)PTE2PA(*pde);
    } else {
        if (!alloc || (pagetable = (pde_t *)kalloc()) == 0)
            return 0;
        memset(pagetable, 0, PGSIZE);
        *pde = PA2PTE(pagetable) | PTE_V;
    }

    // Level 0 is the page table entry (va[21:12])
    return &pagetable[PX(0, va)];
}

// Look up a virtual address, return the physical address,
// or 0 if not mapped.
uint32_t walkaddr(pagetable_t pagetable, uint32_t va) {
    pte_t *pte;
    uint32_t pa;

    if (va >= 0xFFFFFFFF)
        return 0;

    pte = walk(pagetable, va, 0);
    if (pte == 0)
        return 0;
    if ((*pte & PTE_V) == 0)
        return 0;
    if ((*pte & PTE_U) == 0)
        return 0;
    pa = PTE2PA(*pte);
    return pa;
}

// Create PTEs for virtual addresses starting at va that refer to
// physical addresses starting at pa. va and size might not
// be page-aligned. Returns 0 on success, -1 if walk() couldn't
// allocate a needed page-table page.
int mappages(pagetable_t pagetable, uint32_t va, uint32_t size, uint32_t pa, int perm) {
    uint32_t a, last;
    pte_t *pte;

    if (size == 0)
        panic("mappages: size 0");

    a = PGROUNDDOWN(va);
    last = PGROUNDDOWN(va + size - 1);
    for (;;) {
        if ((pte = walk(pagetable, a, 1)) == 0)
            return -1;
        if (*pte & PTE_V)
            panic("mappages: remap");
        *pte = PA2PTE(pa) | perm | PTE_V;
        if (a == last)
            break;
        a += PGSIZE;
        pa += PGSIZE;
    }
    return 0;
}

// Add a mapping to the kernel page table.
void kvmmap(pagetable_t kpgtbl, uint32_t va, uint32_t pa, uint32_t sz, int perm) {
    if (mappages(kpgtbl, va, sz, pa, perm) != 0)
        panic("kvmmap failed");
}

// Initialize the one kernel_pagetable
pagetable_t kvmmake(void) {
    pagetable_t kpgtbl;

    kpgtbl = (pagetable_t)kalloc();
    if (kpgtbl == 0)
        panic("kvmmake: kalloc failed");
    memset(kpgtbl, 0, PGSIZE);

    // Identity map UART 16550 registers (0x1000_0000)
    kvmmap(kpgtbl, UART0, UART0, PGSIZE, PTE_R | PTE_W);

    // Identity map CLINT (0x2000_0000)
    kvmmap(kpgtbl, CLINT, CLINT, 0x10000, PTE_R | PTE_W);

    // Identity map RAMDisk Block Device (0x4000_0000)
    kvmmap(kpgtbl, RAMDISK_BASE, RAMDISK_BASE, 256*1024, PTE_R | PTE_W);

    // Identity map PLIC (0xC000_0000)
    kvmmap(kpgtbl, PLIC, PLIC, 0x400000, PTE_R | PTE_W);

    // Identity map VGA Framebuffer (0xF000_0000)
    kvmmap(kpgtbl, VGA_BASE, VGA_BASE, 0x20000, PTE_R | PTE_W);

    // Map kernel code as read and execute
    kvmmap(kpgtbl, KERNBASE, KERNBASE, (uint32_t)etext - KERNBASE, PTE_R | PTE_X);

    // Map kernel data and physical RAM as read and write
    kvmmap(kpgtbl, (uint32_t)etext, (uint32_t)etext, PHYSTOP - (uint32_t)etext, PTE_R | PTE_W);

    // Map the trampoline for trap entry/exit
    kvmmap(kpgtbl, TRAMPOLINE, (uint32_t)trampoline, PGSIZE, PTE_R | PTE_X);

    return kpgtbl;
}

void kvminit(void) {
    kernel_pagetable = kvmmake();
}

// Switch h/w page table register to the kernel's page table,
// and enable Sv32 paging!
void kvminithart(void) {
    // Wait for any previous memory operations to finish
    sfence_vma();

    // Write satp with Sv32 mode and root page directory PPN
    w_satp(MAKE_SATP(kernel_pagetable));

    // Flush all TLB entries
    sfence_vma();
}
