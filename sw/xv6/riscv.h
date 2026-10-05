#ifndef _RISCV_H_
#define _RISCV_H_

#include "types.h"

// Which hart (core) is this?
static inline uint32_t r_mhartid() {
    uint32_t x;
    asm volatile("csrr %0, mhartid" : "=r" (x));
    return x;
}

// Machine Status Register, mstatus
#define MSTATUS_MPP_MASK (3L << 11)
#define MSTATUS_MPP_M    (3L << 11)
#define MSTATUS_MPP_S    (1L << 11)
#define MSTATUS_MPP_U    (0L << 11)
#define MSTATUS_MIE      (1L << 3)
#define MSTATUS_SIE      (1L << 1)

static inline uint32_t r_mstatus() {
    uint32_t x;
    asm volatile("csrr %0, mstatus" : "=r" (x));
    return x;
}

static inline void w_mstatus(uint32_t x) {
    asm volatile("csrw mstatus, %0" : : "r" (x));
}

// Machine Exception Program Counter, mepc
static inline void w_mepc(uint32_t x) {
    asm volatile("csrw mepc, %0" : : "r" (x));
}

// Supervisor Status Register, sstatus
#define SSTATUS_SPP (1L << 8)  // Previous mode, 1=Supervisor, 0=User
#define SSTATUS_SPIE (1L << 5) // Supervisor Previous Interrupt Enable
#define SSTATUS_UPIE (1L << 4) // User Previous Interrupt Enable
#define SSTATUS_SIE (1L << 1)  // Supervisor Interrupt Enable
#define SSTATUS_UIE (1L << 0)  // User Interrupt Enable

static inline uint32_t r_sstatus() {
    uint32_t x;
    asm volatile("csrr %0, sstatus" : "=r" (x));
    return x;
}

static inline void w_sstatus(uint32_t x) {
    asm volatile("csrw sstatus, %0" : : "r" (x));
}

// Supervisor Interrupt Pending
static inline uint32_t r_sip() {
    uint32_t x;
    asm volatile("csrr %0, sip" : "=r" (x));
    return x;
}

static inline void w_sip(uint32_t x) {
    asm volatile("csrw sip, %0" : : "r" (x));
}

// Supervisor Interrupt Enable
#define SIE_SEIE (1L << 9) // external
#define SIE_STIE (1L << 5) // timer
#define SIE_SSIE (1L << 1) // software

static inline uint32_t r_sie() {
    uint32_t x;
    asm volatile("csrr %0, sie" : "=r" (x));
    return x;
}

static inline void w_sie(uint32_t x) {
    asm volatile("csrw sie, %0" : : "r" (x));
}

// Machine Interrupt Enable
#define MIE_MEIE (1L << 11) // external
#define MIE_MTIE (1L << 7)  // timer
#define MIE_MSIE (1L << 3)  // software

static inline uint32_t r_mie() {
    uint32_t x;
    asm volatile("csrr %0, mie" : "=r" (x));
    return x;
}

static inline void w_mie(uint32_t x) {
    asm volatile("csrw mie, %0" : : "r" (x));
}

// Machine Exception Delegation
static inline uint32_t r_medeleg() {
    uint32_t x;
    asm volatile("csrr %0, medeleg" : "=r" (x));
    return x;
}

static inline void w_medeleg(uint32_t x) {
    asm volatile("csrw medeleg, %0" : : "r" (x));
}

// Machine Interrupt Delegation
static inline uint32_t r_mideleg() {
    uint32_t x;
    asm volatile("csrr %0, mideleg" : "=r" (x));
    return x;
}

static inline void w_mideleg(uint32_t x) {
    asm volatile("csrw mideleg, %0" : : "r" (x));
}

// Supervisor Exception Program Counter, sepc
static inline void w_sepc(uint32_t x) {
    asm volatile("csrw sepc, %0" : : "r" (x));
}

static inline uint32_t r_sepc() {
    uint32_t x;
    asm volatile("csrr %0, sepc" : "=r" (x));
    return x;
}

// Machine Exception Delegation
static inline uint32_t r_stvec() {
    uint32_t x;
    asm volatile("csrr %0, stvec" : "=r" (x));
    return x;
}

static inline void w_stvec(uint32_t x) {
    asm volatile("csrw stvec, %0" : : "r" (x));
}

// Supervisor Trap Cause
static inline uint32_t r_scause() {
    uint32_t x;
    asm volatile("csrr %0, scause" : "=r" (x));
    return x;
}

// Supervisor Trap Value
static inline uint32_t r_stval() {
    uint32_t x;
    asm volatile("csrr %0, stval" : "=r" (x));
    return x;
}

// Machine-mode Trap Vector
static inline void w_mtvec(uint32_t x) {
    asm volatile("csrw mtvec, %0" : : "r" (x));
}

// Supervisor Address Translation and Protection (satp) register
#define SATP_SV32 (1U << 31)
#define MAKE_SATP(pagetable) (SATP_SV32 | (((uint32_t)(pagetable)) >> 12))

static inline void w_satp(uint32_t x) {
    asm volatile("csrw satp, %0" : : "r" (x));
}

static inline uint32_t r_satp() {
    uint32_t x;
    asm volatile("csrr %0, satp" : "=r" (x));
    return x;
}

// Supervisor Scratch Register
static inline void w_sscratch(uint32_t x) {
    asm volatile("csrw sscratch, %0" : : "r" (x));
}

// Machine Scratch Register
static inline void w_mscratch(uint32_t x) {
    asm volatile("csrw mscratch, %0" : : "r" (x));
}

// Flush TLB
static inline void sfence_vma() {
    // zero, zero means flush all TLB entries
    asm volatile("sfence.vma zero, zero");
}

// Sv32 Paging Definitions
#define PGSIZE 4096 // bytes per page
#define PGSHIFT 12  // bits of offset within a page

#define PGROUNDUP(sz)  (((sz)+PGSIZE-1) & ~(PGSIZE-1))
#define PGROUNDDOWN(a) (((a)) & ~(PGSIZE-1))

#define PTE_V (1L << 0) // Valid
#define PTE_R (1L << 1) // Readable
#define PTE_W (1L << 2) // Writable
#define PTE_X (1L << 3) // Executable
#define PTE_U (1L << 4) // User accessible
#define PTE_G (1L << 5) // Global
#define PTE_A (1L << 6) // Accessed
#define PTE_D (1L << 7) // Dirty

// Shift a physical address to the PPN position in a PTE
#define PA2PTE(pa) ((((uint32_t)(pa)) >> 12) << 10)

// Extract physical address from a PTE
#define PTE2PA(pte) ((((pte) >> 10) << 12))

#define PTE_FLAGS(pte) ((pte) & 0x3FF)

// Extract the 10-bit page directory/table index from virtual address
// level 1: va[31:22]
// level 0: va[21:12]
#define PXSHIFT(level) (PGSHIFT + (10*(level)))
#define PXMASK 0x3FF
#define PX(level, va) ((((uint32_t)(va)) >> PXSHIFT(level)) & PXMASK)

#endif
