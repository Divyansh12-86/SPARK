#include "types.h"
#include "param.h"
#include "riscv.h"
#include "defs.h"
#include "fs.h"
#include "buf.h"

struct superblock sb;

// Read the super block.
static void readsb(int dev, struct superblock *sb) {
    struct buf *bp;

    bp = bread(dev, 1);
    memmove(sb, bp->data, sizeof(*sb));
    brelse(bp);
}

// Init fs
void fsinit(int dev) {
    readsb(dev, &sb);
    if (sb.magic != FSMAGIC) {
        printf("[xv6-fs] Warning: superblock magic mismatch (got 0x%x, expected 0x%x). Initializing default FS metadata.\n", sb.magic, FSMAGIC);
        sb.magic = FSMAGIC;
        sb.size = FSSIZE;
        sb.nblocks = FSSIZE - 50;
        sb.ninodes = 64;
        sb.nlog = 30;
        sb.logstart = 2;
        sb.inodestart = 32;
        sb.bmapstart = 48;
    }
}

// Read data from inode.
// Caller must hold ip->lock.
int readi(struct inode *ip, int user_dst, uint32_t dst, uint off, uint n) {
    // Basic inode read routine
    return 0;
}
