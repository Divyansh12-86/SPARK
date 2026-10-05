#ifndef _DEFS_H_
#define _DEFS_H_

#include "types.h"
#include "riscv.h"
#include "param.h"
#include "fs.h"

struct buf;
struct context;
struct inode;
struct proc;
struct stat;

// bio.c
void            binit(void);
struct buf*     bread(uint, uint);
void            brelse(struct buf*);
void            bwrite(struct buf*);

// fs.c
void            fsinit(int);
int             dirlink(struct inode*, char*, uint);
struct inode*   dirlookup(struct inode*, char*, uint*);
struct inode*   ialloc(uint, short);
struct inode*   idup(struct inode*);
void            iinit(void);
void            ilock(struct inode*);
void            iput(struct inode*);
void            iunlock(struct inode*);
void            iunlockput(struct inode*);
void            iupdate(struct inode*);
int             readi(struct inode*, int, uint32_t, uint, uint);
void            stati(struct inode*, struct stat*);
int             writei(struct inode*, int, uint32_t, uint, uint);

// kalloc.c
void*           kalloc(void);
void            kfree(void *);
void            kinit(void);

// printf.c
void            printf(char*, ...);
void            panic(char*) __attribute__((noreturn));
void            printfinit(void);

// proc.c
int             cpuid(void);
void            exit(int);
int             fork(void);
int             growproc(int);
void            proc_mapstacks(pagetable_t);
pagetable_t     proc_pagetable(struct proc *);
void            proc_freepagetable(pagetable_t, uint32_t);
int             kill(int);
struct cpu*     mycpu(void);
struct cpu*     getmycpu(void);
struct proc*    myproc();
void            procinit(void);
void            scheduler(void) __attribute__((noreturn));
void            sched(void);
void            sleep(void*, void*);
void            userinit(void);
int             wait(uint32_t*);
void            wakeup(void*);
void            yield(void);

// swtch.s
void            swtch(struct context*, struct context*);

// trap.c
void            trapinit(void);
void            trapinithart(void);
void            usertrapret(void);

// uart.c
void            uart_init(void);
void            uart_putc(int);
int             uart_getc(void);
void            uart_puts(const char*);
void            uart_intr(void);

// vm.c
void            kvminit(void);
void            kvminithart(void);
uint32_t        kvmpa(uint32_t);
void            kvmmap(pagetable_t, uint32_t, uint32_t, uint32_t, int);
int             mappages(pagetable_t, uint32_t, uint32_t, uint32_t, int);
pagetable_t     uvmcreate(void);
void            uvmfirst(pagetable_t, uchar *, uint);
uint32_t        uvmalloc(pagetable_t, uint32_t, uint32_t, int);
uint32_t        uvmdealloc(pagetable_t, uint32_t, uint32_t);
int             copyout(pagetable_t, uint32_t, char *, uint32_t);
int             copyin(pagetable_t, char *, uint32_t, uint32_t);
int             copyinstr(pagetable_t, char *, uint32_t, uint32_t);

// ramdisk.c
void            ramdisk_init(void);
void            ramdisk_rw(struct buf *);

// plic.c
void            plicinit(void);
void            plicinithart(void);
int             plic_claim(void);
void            plic_complete(int);

// sh.c
void            run_shell(void);

// gui_wm.c
void            wm_run_desktop(void);

// string.c
int             memcmp(const void*, const void*, uint);
void*           memmove(void*, const void*, uint);
void*           memset(void*, int, uint);
char*           safestrcpy(char*, const char*, int);
int             strlen(const char*);
int             strncmp(const char*, const char*, uint);
char*           strncpy(char*, const char*, int);

#endif
