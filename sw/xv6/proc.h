#ifndef _PROC_H_
#define _PROC_H_

#include "types.h"
#include "param.h"
#include "riscv.h"

// Saved registers for kernel context switches.
struct context {
    uint32_t ra;
    uint32_t sp;

    // callee-saved
    uint32_t s0;
    uint32_t s1;
    uint32_t s2;
    uint32_t s3;
    uint32_t s4;
    uint32_t s5;
    uint32_t s6;
    uint32_t s7;
    uint32_t s8;
    uint32_t s9;
    uint32_t s10;
    uint32_t s11;
};

// Per-CPU state.
struct cpu {
    struct proc *proc;          // The process running on this cpu, or null.
    struct context context;     // swtch() here to enter scheduler().
    int noff;                   // Depth of push_off() nesting.
    int intena;                 // Were interrupts enabled before push_off()?
};

enum procstate { UNUSED, USED, SLEEPING, RUNNABLE, RUNNING, ZOMBIE };

// Per-process state
struct proc {
    enum procstate state;        // Process state
    void *chan;                  // If non-zero, sleeping on chan
    int killed;                  // If non-zero, have been killed
    int xstate;                  // Exit status to be returned to parent's wait
    int pid;                     // Process ID

    uint32_t kstack;             // Virtual address of kernel stack
    uint32_t sz;                 // Size of process memory (bytes)
    pagetable_t pagetable;       // User page table
    struct context context;      // swtch() here to run process
    char name[16];               // Process name (debugging)
};

#endif
