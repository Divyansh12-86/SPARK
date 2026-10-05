#ifndef _VGA_CONSOLE_H_
#define _VGA_CONSOLE_H_

#include "types.h"

void vga_console_init(void);
void vga_putc(char c);
void vga_clear(uint16_t color);

#endif
