#ifndef _FS_H_
#define _FS_H_

#include "types.h"

// xv6 File System Structure (512-byte block size matching SPARK RAMDisk)

#define ROOTINO 1   // root i-number
#define BSIZE 512   // block size in bytes

// Disk layout:
// [ boot block | super block | log | inode blocks | free bit map | data blocks ]
//
// mkfs builds the super block and fills it with:
// total number of blocks, number of data blocks, number of inodes, number of log blocks

#define FSMAGIC 0x10203040

struct superblock {
    uint32_t magic;        // Must be FSMAGIC
    uint32_t size;         // Size of file system image (blocks)
    uint32_t nblocks;      // Number of data blocks
    uint32_t ninodes;      // Number of inodes.
    uint32_t nlog;         // Number of log blocks
    uint32_t logstart;     // Block number of first log block
    uint32_t inodestart;   // Block number of first inode block
    uint32_t bmapstart;    // Block number of first free map block
};

#define NDIRECT 11
#define NINDIRECT (BSIZE / sizeof(uint32_t))
#define MAXFILE (NDIRECT + NINDIRECT)

// On-disk inode structure
struct dinode {
    int16_t  type;               // File type
    int16_t  major;              // Major device number (T_DEVICE only)
    int16_t  minor;              // Minor device number (T_DEVICE only)
    int16_t  nlink;              // Number of links to inode in file system
    uint32_t size;               // Size of file (bytes)
    uint32_t addrs[NDIRECT+1];   // Data block addresses
};

// Inodes per block.
#define IPB           (BSIZE / sizeof(struct dinode))

// Block containing inode i
#define IBLOCK(i, sb)     ((i) / IPB + sb.inodestart)

// Bitmap bits per block
#define BPB           (BSIZE*8)

// Block of free map containing bit for block b
#define BBLOCK(b, sb) ((b)/BPB + sb.bmapstart)

// Directory entry
#define DIRSIZ 14

struct dirent {
    uint16_t inum;
    char name[DIRSIZ];
};

#define T_DIR     1   // Directory
#define T_FILE    2   // File
#define T_DEVICE  3   // Device

#endif
