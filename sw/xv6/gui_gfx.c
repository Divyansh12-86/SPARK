#include "types.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"
#include "gui_gfx.h"
#include "vga_font.h"

static volatile uint32_t * const vram = (volatile uint32_t *)VGA_BASE;

static int clip_min_x = 0;
static int clip_min_y = 0;
static int clip_max_x = SCREEN_W - 1;
static int clip_max_y = SCREEN_H - 1;

void gfx_init(void) {
    gfx_reset_clip();
}

void gfx_set_clip(int x0, int y0, int x1, int y1) {
    clip_min_x = (x0 < 0) ? 0 : (x0 >= SCREEN_W ? SCREEN_W - 1 : x0);
    clip_min_y = (y0 < 0) ? 0 : (y0 >= SCREEN_H ? SCREEN_H - 1 : y0);
    clip_max_x = (x1 < 0) ? 0 : (x1 >= SCREEN_W ? SCREEN_W - 1 : x1);
    clip_max_y = (y1 < 0) ? 0 : (y1 >= SCREEN_H ? SCREEN_H - 1 : y1);
}

void gfx_reset_clip(void) {
    clip_min_x = 0;
    clip_min_y = 0;
    clip_max_x = SCREEN_W - 1;
    clip_max_y = SCREEN_H - 1;
}

void gfx_put_pixel(int x, int y, uint16_t color) {
    if (x >= clip_min_x && x <= clip_max_x && y >= clip_min_y && y <= clip_max_y) {
        vram[y * SCREEN_W + x] = color & 0x0FFF;
    }
}

uint16_t gfx_get_pixel(int x, int y) {
    if (x >= 0 && x < SCREEN_W && y >= 0 && y < SCREEN_H) {
        return (uint16_t)(vram[y * SCREEN_W + x] & 0x0FFF);
    }
    return 0;
}

void gfx_fill_rect(int x, int y, int w, int h, uint16_t color) {
    if (w <= 0 || h <= 0) return;
    int x0 = (x < clip_min_x) ? clip_min_x : x;
    int y0 = (y < clip_min_y) ? clip_min_y : y;
    int x1 = (x + w - 1 > clip_max_x) ? clip_max_x : (x + w - 1);
    int y1 = (y + h - 1 > clip_max_y) ? clip_max_y : (y + h - 1);

    uint32_t val = color & 0x0FFF;
    for (int cy = y0; cy <= y1; cy++) {
        int row_offset = cy * SCREEN_W;
        for (int cx = x0; cx <= x1; cx++) {
            vram[row_offset + cx] = val;
        }
    }
}

void gfx_draw_rect(int x, int y, int w, int h, uint16_t color) {
    if (w <= 0 || h <= 0) return;
    gfx_fill_rect(x, y, w, 1, color);             // Top edge
    gfx_fill_rect(x, y + h - 1, w, 1, color);     // Bottom edge
    gfx_fill_rect(x, y, 1, h, color);             // Left edge
    gfx_fill_rect(x + w - 1, y, 1, h, color);     // Right edge
}

void gfx_draw_line(int x0, int y0, int x1, int y1, uint16_t color) {
    int dx = (x1 > x0) ? (x1 - x0) : (x0 - x1);
    int sx = (x0 < x1) ? 1 : -1;
    int dy = (y1 > y0) ? -(y1 - y0) : -(y0 - y1);
    int sy = (y0 < y1) ? 1 : -1;
    int err = dx + dy;

    for (;;) {
        gfx_put_pixel(x0, y0, color);
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

void gfx_draw_char(int x, int y, char c, uint16_t fg, uint16_t bg, int transparent) {
    int glyph_idx = (uchar)c - 32;
    if (glyph_idx < 0 || glyph_idx >= 96) glyph_idx = 0;

    const uint8_t *glyph = font8x8[glyph_idx];
    for (int py = 0; py < 8; py++) {
        int cy = y + py;
        if (cy < clip_min_y || cy > clip_max_y) continue;
        uint8_t bits = glyph[py];
        int row_offset = cy * SCREEN_W;
        for (int px = 0; px < 8; px++) {
            int cx = x + px;
            if (cx < clip_min_x || cx > clip_max_x) continue;
            if (bits & (0x80 >> px)) {
                vram[row_offset + cx] = fg & 0x0FFF;
            } else if (!transparent) {
                vram[row_offset + cx] = bg & 0x0FFF;
            }
        }
    }
}

void gfx_draw_string(int x, int y, const char *str, uint16_t fg, uint16_t bg, int transparent) {
    int cx = x;
    while (*str) {
        if (*str == '\n') {
            cx = x;
            y += 8;
        } else {
            gfx_draw_char(cx, y, *str, fg, bg, transparent);
            cx += 8;
        }
        str++;
    }
}

void gfx_draw_gradient_v(int x, int y, int w, int h, uint16_t c_top, uint16_t c_bot) {
    int r1 = (c_top >> 8) & 0xF, g1 = (c_top >> 4) & 0xF, b1 = c_top & 0xF;
    int r2 = (c_bot >> 8) & 0xF, g2 = (c_bot >> 4) & 0xF, b2 = c_bot & 0xF;

    for (int cy = 0; cy < h; cy++) {
        int py = y + cy;
        if (py < clip_min_y || py > clip_max_y) continue;
        int r = r1 + ((r2 - r1) * cy) / (h > 1 ? h - 1 : 1);
        int g = g1 + ((g2 - g1) * cy) / (h > 1 ? h - 1 : 1);
        int b = b1 + ((b2 - b1) * cy) / (h > 1 ? h - 1 : 1);
        uint16_t col = ((r & 0xF) << 8) | ((g & 0xF) << 4) | (b & 0xF);
        gfx_fill_rect(x, py, w, 1, col);
    }
}

void gfx_draw_button_3d(int x, int y, int w, int h, const char *label, int pressed) {
    uint16_t bg = pressed ? THEME_BTN_BORDER_DRK : THEME_BTN_FACE;
    uint16_t top_edge = pressed ? THEME_BTN_BORDER_DRK : THEME_BTN_BORDER_LGT;
    uint16_t bot_edge = pressed ? THEME_BTN_BORDER_LGT : THEME_BTN_BORDER_DRK;

    gfx_fill_rect(x, y, w, h, bg);
    gfx_fill_rect(x, y, w, 1, top_edge);
    gfx_fill_rect(x, y, 1, h, top_edge);
    gfx_fill_rect(x, y + h - 1, w, 1, bot_edge);
    gfx_fill_rect(x + w - 1, y, 1, h, bot_edge);

    int text_len = strlen(label);
    int tx = x + (w - text_len * 8) / 2;
    int ty = y + (h - 8) / 2;
    if (pressed) { tx += 1; ty += 1; }
    gfx_draw_string(tx, ty, label, THEME_BTN_TEXT, bg, 1);
}

void gfx_draw_window_frame(int x, int y, int w, int h, const char *title, int focused) {
    // Drop shadow (bottom strip and right strip only, never full-body fill)
    gfx_fill_rect(x + 2, y + h, w, 2, 0x0112);
    gfx_fill_rect(x + w, y + 2, 2, h, 0x0112);

    // Window border
    gfx_draw_rect(x, y, w, h, THEME_WIN_BORDER);

    // Title bar
    uint16_t title_c1 = focused ? THEME_TITLE_ACTIVE : THEME_TITLE_INACTIVE;
    uint16_t title_c2 = focused ? 0x0125 : 0x0445;
    gfx_draw_gradient_v(x + 1, y + 1, w - 2, 14, title_c1, title_c2);

    // Title text
    gfx_draw_string(x + 4, y + 4, title, THEME_TITLE_TEXT, title_c1, 1);

    // Window control: Close button [X]
    int bx = x + w - 14;
    int by = y + 2;
    gfx_fill_rect(bx, by, 11, 11, GFX_COLOR_RED);
    gfx_draw_rect(bx, by, 11, 11, GFX_COLOR_DARK_RED);
    gfx_draw_string(bx + 2, by + 2, "x", GFX_COLOR_WHITE, GFX_COLOR_RED, 1);
}
