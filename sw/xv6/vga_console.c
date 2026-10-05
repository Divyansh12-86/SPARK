#include "types.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"
#include "vga_console.h"
#include "vga_font.h"

#define FB_WIDTH  320
#define FB_HEIGHT 240
#define CHAR_W    8
#define CHAR_H    8
#define COLS      (FB_WIDTH / CHAR_W)   // 40
#define ROWS      (FB_HEIGHT / CHAR_H)  // 30

#define COLOR_BG  0x0002 // Deep Navy Blue
#define COLOR_FG  0x0FFF // Bright White
#define COLOR_HDR 0x00F0 // Bright Phosphor Green

static int cursor_x = 0;
static int cursor_y = 0;

static volatile uint32_t * const fb = (volatile uint32_t *)VGA_BASE;

void vga_clear(uint16_t color) {
    uint32_t word = color & 0x0FFF;
    for (int i = 0; i < FB_WIDTH * FB_HEIGHT; i++) {
        fb[i] = word;
    }
}

static void draw_char(int cx, int cy, char c, uint16_t fg, uint16_t bg) {
    if (cx < 0 || cx >= COLS || cy < 0 || cy >= ROWS)
        return;

    int glyph_idx = (uchar)c - 32;
    if (glyph_idx < 0 || glyph_idx >= 96)
        glyph_idx = 0; // Space for unprintable

    const uint8_t *glyph = font8x8[glyph_idx];
    int start_x = cx * CHAR_W;
    int start_y = cy * CHAR_H;

    for (int py = 0; py < CHAR_H; py++) {
        uint8_t row_bits = glyph[py];
        int fb_offset = (start_y + py) * FB_WIDTH + start_x;
        for (int px = 0; px < CHAR_W; px++) {
            if (row_bits & (0x80 >> px)) {
                fb[fb_offset + px] = fg;
            } else {
                fb[fb_offset + px] = bg;
            }
        }
    }
}

static void clear_line(int row) {
    if (row < 0 || row >= ROWS) return;
    for (int py = 0; py < CHAR_H; py++) {
        int off = (row * CHAR_H + py) * FB_WIDTH;
        for (int x = 0; x < FB_WIDTH; x++) {
            fb[off + x] = COLOR_BG;
        }
    }
}

static void scroll(void) {
    // Wrap to row 2 (below header) and clear line
    cursor_y = 2;
    cursor_x = 0;
    clear_line(cursor_y);
}

void vga_console_init(void) {
    vga_clear(COLOR_BG);
    cursor_x = 0;
    cursor_y = 0;
}

void vga_putc(char c) {
    if (c == '\n') {
        cursor_x = 0;
        cursor_y++;
        if (cursor_y >= ROWS) {
            scroll();
        } else {
            clear_line(cursor_y);
        }
    } else if (c == '\r') {
        cursor_x = 0;
    } else if (c == '\b') {
        if (cursor_x > 0) {
            cursor_x--;
            draw_char(cursor_x, cursor_y, ' ', COLOR_FG, COLOR_BG);
        }
    } else {
        uint16_t fg = COLOR_FG;
        if (cursor_y == 0 || cursor_y == 1) fg = COLOR_HDR;
        draw_char(cursor_x, cursor_y, c, fg, COLOR_BG);
        cursor_x++;
        if (cursor_x >= COLS) {
            cursor_x = 0;
            cursor_y++;
            if (cursor_y >= ROWS) {
                scroll();
            } else {
                clear_line(cursor_y);
            }
        }
    }
}
