#ifndef _PARAM_H_
#define _PARAM_H_

#define NPROC        8  // maximum number of processes
#define NCPU         1  // maximum number of CPUs
#define NOFILE      16  // open files per process
#define NFILE       16  // open files per system
#define NINODE      16  // maximum number of active i-nodes
#define NDEV        10  // maximum major device number
#define ROOTDEV      1  // device number of file system root disk
#define MAXARG       8  // max exec arguments
#define MAXOPBLOCKS 10  // max # of blocks any FS op writes
#define LOGSIZE     30  // max data blocks in on-disk log
#define NBUF        16  // size of disk buffer cache
#define FSSIZE     512  // size of file system in blocks (256 KB)
#define MAXPATH     64  // maximum file path name

#endif
