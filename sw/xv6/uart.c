#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"
#include "vga_console.h"

// 16550 UART Registers
#define Reg(reg) ((volatile uint8_t *)(UART0 + (reg)))

#define RBR 0 // In:  Receive buffer
#define THR 0 // Out: Transmitter holding register
#define IER 1 // Out: Interrupt Enable Register
#define IIR 2 // In:  Interrupt ID Register
#define FCR 2 // Out: FIFO Control Register
#define LCR 3 // Out: Line Control Register
#define MCR 4 // Out: Modem Control Register
#define LSR 5 // In:  Line Status Register
#define MSR 6 // In:  Modem Status Register
#define SCR 7 // I/O: Scratch Register

#define LSR_RX_READY (1 << 0)
#define LSR_TX_IDLE  (1 << 5)

#define ReadReg(reg) (*(Reg(reg)))
#define WriteReg(reg, v) (*(Reg(reg)) = (v))

void uart_init(void) {
    vga_console_init();

    // Disable interrupts
    WriteReg(IER, 0x00);

    // Enter DLAB to set baud rate divisor
    WriteReg(LCR, 0x80);

    // Divisor = 1 for max simulation speed
    WriteReg(0, 0x01); // DLL
    WriteReg(1, 0x00); // DLM

    // Leave DLAB; 8 bits, no parity, 1 stop bit
    WriteReg(LCR, 0x03);

    // Enable and clear FIFO
    WriteReg(FCR, 0x07);

    // Enable receive interrupts
    WriteReg(IER, 0x01);
}

void uart_putc(int c) {
    // Mirror character to VGA Display Console
    vga_putc((char)c);

    // Wait until transmitter is empty
    while ((ReadReg(LSR) & LSR_TX_IDLE) == 0)
        ;
    WriteReg(THR, c);
}

#define UART_RX_BUF_SIZE 256
static char rx_buf[UART_RX_BUF_SIZE];
static volatile uint32_t rx_head = 0;
static volatile uint32_t rx_tail = 0;

void uart_intr(void) {
    while (ReadReg(LSR) & LSR_RX_READY) {
        int c = ReadReg(RBR);
        uint32_t next = (rx_head + 1) % UART_RX_BUF_SIZE;
        if (next != rx_tail) {
            rx_buf[rx_head] = (char)c;
            rx_head = next;
        }
    }
}

int uart_getc(void) {
    if (rx_head != rx_tail) {
        int c = (unsigned char)rx_buf[rx_tail];
        rx_tail = (rx_tail + 1) % UART_RX_BUF_SIZE;
        return c;
    }
    if (ReadReg(LSR) & LSR_RX_READY) {
        return ReadReg(RBR);
    }
    return -1;
}

void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}
