#!/usr/bin/env python3
import struct
import sys

BSIZE = 512
FSSIZE = 512
FSMAGIC = 0x10203040

def make_fs(img_path):
    img = bytearray(FSSIZE * BSIZE)

    # Block 1: Superblock
    # struct superblock:
    #   uint32_t magic;
    #   uint32_t size;
    #   uint32_t nblocks;
    #   uint32_t ninodes;
    #   uint32_t nlog;
    #   uint32_t logstart;
    #   uint32_t inodestart;
    #   uint32_t bmapstart;
    sb = struct.pack("<8I", FSMAGIC, FSSIZE, FSSIZE - 50, 64, 30, 2, 32, 48)
    img[1 * BSIZE : 1 * BSIZE + len(sb)] = sb

    # Inode 1: Root directory
    # struct dinode:
    #   int16_t type (1 = T_DIR)
    #   int16_t major
    #   int16_t minor
    #   int16_t nlink
    #   uint32_t size
    #   uint32_t addrs[12]
    root_data_block = 50
    root_inode = struct.pack("<4hI12I", 1, 0, 0, 1, BSIZE, root_data_block, 0,0,0,0,0,0,0,0,0,0,0)
    inodestart = 32
    img[inodestart * BSIZE : inodestart * BSIZE + len(root_inode)] = root_inode

    # Root directory data block: entries for '.', '..', 'README', 'init', 'sh', 'pim_bench'
    entries = [
        (1, "."),
        (1, ".."),
        (2, "README"),
        (3, "init"),
        (4, "sh"),
        (5, "pim_bench")
    ]
    dirent_offset = root_data_block * BSIZE
    for inum, name in entries:
        # struct dirent: uint16_t inum; char name[14];
        name_bytes = name.encode('ascii')[:14].ljust(14, b'\x00')
        de = struct.pack("<H14s", inum, name_bytes)
        img[dirent_offset : dirent_offset + len(de)] = de
        dirent_offset += len(de)

    # README data block (inode 2)
    readme_block = 51
    readme_text = b"Welcome to xv6 running on SPARK RISC-V SoC!\nHardware: RV32I 5-stage CPU, Sv32 Paging MMU, PIM Accelerator.\n"
    img[readme_block * BSIZE : readme_block * BSIZE + len(readme_text)] = readme_text

    readme_inode = struct.pack("<4hI12I", 2, 0, 0, 1, len(readme_text), readme_block, 0,0,0,0,0,0,0,0,0,0,0)
    img[inodestart * BSIZE + 64 : inodestart * BSIZE + 64 + len(readme_inode)] = readme_inode

    with open(img_path, 'wb') as f:
        f.write(img)
    print(f"[MKFS] Successfully generated {img_path} ({len(img)} bytes, {FSSIZE} blocks)")

if __name__ == "__main__":
    out_file = sys.argv[1] if len(sys.argv) > 1 else "fs.img"
    make_fs(out_file)
