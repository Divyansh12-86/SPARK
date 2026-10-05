#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"
#include "proc.h"

struct cpu cpus[NCPU];
struct proc proc[NPROC];

struct proc *initproc;

int nextpid = 1;

void procinit(void) {
    struct proc *p;
    
    for (p = proc; p < &proc[NPROC]; p++) {
        p->state = UNUSED;
        p->kstack = (uint32_t)kalloc();
    }
}

// Return this CPU's cpu struct.
// Only 1 CPU (hart 0) on SPARK
struct cpu* mycpu(void) {
    return &cpus[0];
}

// Return the current struct proc *, or zero if none.
struct proc* myproc(void) {
    struct cpu *c = mycpu();
    return c->proc;
}

static struct proc* allocproc(void) {
    struct proc *p;

    for (p = proc; p < &proc[NPROC]; p++) {
        if (p->state == UNUSED) {
            goto found;
        }
    }
    return 0;

found:
    p->pid = nextpid++;
    p->state = USED;

    // Set up new context to start executing at forkret.
    memset(&p->context, 0, sizeof(p->context));
    p->context.ra = (uint32_t)wm_run_desktop;
    p->context.sp = p->kstack + PGSIZE;

    return p;
}

// Set up first user process.
void userinit(void) {
    struct proc *p;

    p = allocproc();
    initproc = p;

    safestrcpy(p->name, "initcode", sizeof(p->name));
    p->state = RUNNABLE;
}

// Per-CPU process scheduler.
// Each CPU calls scheduler() after setting itself up.
// Scheduler never returns.  It loops, doing:
//  - choose a process to run.
//  - swtch to start running that process.
//  - eventually that process transfers control
//    via swtch back to the scheduler.
void scheduler(void) {
    struct proc *p;
    struct cpu *c = mycpu();

    c->proc = 0;
    for (;;) {
        // Avoid deadlock on simulation by enabling interrupts
        w_sstatus(r_sstatus() | SSTATUS_SIE);

        for (p = proc; p < &proc[NPROC]; p++) {
            if (p->state == RUNNABLE) {
                // Switch to chosen process.  It is the process's job
                // to release its lock and then reacquire it
                // before jumping back to us.
                p->state = RUNNING;
                c->proc = p;
                swtch(&c->context, &p->context);

                // Process is done running for now.
                // It should have changed its p->state before coming back.
                c->proc = 0;
            }
        }
    }
}

// Switch to scheduler.  Must hold only p->lock
// and have changed proc->state. Saves and restores
// intena because intena is a property of this
// kernel thread, not this CPU. It should
// be proc->intena and proc->noff, but that would
// break in the few places where a lock is held but
// there's no process.
void sched(void) {
    struct proc *p = myproc();
    swtch(&p->context, &mycpu()->context);
}

// Give up the CPU for one scheduling round.
void yield(void) {
    struct proc *p = myproc();
    p->state = RUNNABLE;
    sched();
}

void exit(int status) {
    struct proc *p = myproc();
    p->xstate = status;
    p->state = ZOMBIE;
    sched();
    panic("zombie exit");
}
