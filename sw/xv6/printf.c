#include <stdarg.h>
#include "types.h"
#include "param.h"
#include "riscv.h"
#include "defs.h"

static char digits[] = "0123456789abcdef";

static void printint(int xx, int base, int sign) {
    char buf[16];
    int i;
    uint x;

    if (sign && (sign = xx < 0))
        x = -xx;
    else
        x = xx;

    i = 0;
    do {
        buf[i++] = digits[x % base];
    } while ((x /= base) != 0);

    if (sign)
        buf[i++] = '-';

    while (--i >= 0)
        uart_putc(buf[i]);
}

static void printptr(uint32_t x) {
    int i;
    uart_putc('0');
    uart_putc('x');
    for (i = 0; i < (int)(sizeof(uint32_t) * 2); i++, x <<= 4)
        uart_putc(digits[(x >> (sizeof(uint32_t) * 8 - 4)) & 0xf]);
}

void printfinit(void) {
    // printf lock can be initialized here if SMP
}

void printf(char *fmt, ...) {
    va_list ap;
    int i, c;
    char *s;

    if (fmt == 0)
        panic("null fmt");

    va_start(ap, fmt);
    for (i = 0; (c = fmt[i] & 0xff) != 0; i++) {
        if (c != '%') {
            uart_putc(c);
            continue;
        }
        c = fmt[++i] & 0xff;
        if (c == 0)
            break;
        switch (c) {
        case 'd':
            printint(va_arg(ap, int), 10, 1);
            break;
        case 'x':
            printint(va_arg(ap, int), 16, 0);
            break;
        case 'p':
            printptr(va_arg(ap, uint32_t));
            break;
        case 's':
            if ((s = va_arg(ap, char*)) == 0)
                s = "(null)";
            for (; *s; s++)
                uart_putc(*s);
            break;
        case 'c':
            uart_putc(va_arg(ap, int));
            break;
        case '%':
            uart_putc('%');
            break;
        default:
            // Print unknown % sequence to draw attention.
            uart_putc('%');
            uart_putc(c);
            break;
        }
    }
    va_end(ap);
}

void panic(char *s) {
    printf("\npanic: ");
    printf(s);
    printf("\n");
    for (;;)
        ;
}
