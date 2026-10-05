#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

extern char end[]; // first address after kernel loaded from ELF file

struct run {
    struct run *next;
};

struct {
    struct run *freelist;
} kmem;

void freerange(void *pa_start, void *pa_end) {
    char *p;
    p = (char *)PGROUNDUP((uint32_t)pa_start);
    for (; p + PGSIZE <= (char *)pa_end; p += PGSIZE)
        kfree(p);
}

void kinit(void) {
    kmem.freelist = 0;
    freerange(end, (void *)PHYSTOP);
}

// Free the page of physical memory pointed at by pa,
// which normally should have been returned by a
// call to kalloc().
void kfree(void *pa) {
    struct run *r;

    if (((uint32_t)pa % PGSIZE) != 0 || (char *)pa < end || (uint32_t)pa >= PHYSTOP)
        panic("kfree: invalid pa");

    // Freelist linking
    r = (struct run *)pa;
    r->next = kmem.freelist;
    kmem.freelist = r;
}

// Allocate one 4096-byte page of physical memory.
// Returns a pointer that the kernel can use.
// Returns 0 if the memory cannot be allocated.
void* kalloc(void) {
    struct run *r;

    r = kmem.freelist;
    if (r) {
        kmem.freelist = r->next;
        memset((char *)r, 0, PGSIZE); // zero newly allocated page
    }
    return (void *)r;
}
