#ifndef _MEMLAYOUT_H_
#define _MEMLAYOUT_H_

// Physical memory layout for SPARK SoC

// 16550 UART serial console
#define UART0 0x10000000L
#define UART0_IRQ 1

// CLINT (Core Local Interruptor)
#define CLINT 0x20000000L
#define CLINT_MTIMECMP(hartid) (CLINT + 0x4000 + 8*(hartid))
#define CLINT_MTIME (CLINT + 0xBFF8)

// Processing-In-Memory Subsystem
#define PIM_BASE 0x30000000L
#define PIM_IRQ  3

// RAMDisk Block Storage Device (root filesystem)
#define RAMDISK_BASE 0x40000000L

// Main System RAM
#define KERNBASE 0x80000000L
#define PHYSTOP  (KERNBASE + 256*1024) // 256 KB physical RAM

// PLIC (Platform-Level Interrupt Controller)
#define PLIC 0xC0000000L
#define PLIC_PRIORITY (PLIC + 0x0)
#define PLIC_PENDING  (PLIC + 0x1000)
#define PLIC_SENABLE  (PLIC + 0x2000)
#define PLIC_SPRIORITY (PLIC + 0x200000)
#define PLIC_SCLAIM    (PLIC + 0x200004)

// Software VGA Framebuffer
#define VGA_BASE 0xF0000000L

// Trampoline page at top of user virtual address space
#define TRAMPOLINE (0xFFFFF000)

// User virtual memory space starts at 0
#define USER_STACK_TOP 0x00010000

#endif
