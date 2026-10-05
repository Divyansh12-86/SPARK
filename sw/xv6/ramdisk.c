#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"
#include "fs.h"
#include "buf.h"

// RAMDisk controller mapped at 0x4000_0000
void ramdisk_init(void) {
    // RAMDisk is memory-mapped, no hardware handshake required
}

void ramdisk_rw(struct buf *b) {
    if (b->blockno >= FSSIZE)
        panic("ramdisk_rw: blockno out of range");

    volatile uint32_t *disk_addr = (volatile uint32_t *)(RAMDISK_BASE + (b->blockno * BSIZE));
    uint32_t *buf_words = (uint32_t *)b->data;

    if (b->flags & B_DIRTY) {
        // Write buffer data to RAMDisk
        for (int i = 0; i < BSIZE / 4; i++) {
            disk_addr[i] = buf_words[i];
        }
        b->flags &= ~B_DIRTY;
    } else {
        // Read RAMDisk data into buffer
        for (int i = 0; i < BSIZE / 4; i++) {
            buf_words[i] = disk_addr[i];
        }
    }
    b->valid = 1;
}
