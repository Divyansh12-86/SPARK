#ifndef GUI_GFX_H
#define GUI_GFX_H

#include "types.h"

// Screen Dimensions
#define SCREEN_W 320
#define SCREEN_H 240

// 12-bit RGB Color Palette (0x0RGB: 4 bits R, 4 bits G, 4 bits B)
#define GFX_COLOR_BLACK       0x0000
#define GFX_COLOR_WHITE       0x0FFF
#define GFX_COLOR_LIGHT_GREY  0x0CCC
#define GFX_COLOR_MID_GREY    0x0888
#define GFX_COLOR_DARK_GREY   0x0444
#define GFX_COLOR_CHARCOAL    0x0222

#define GFX_COLOR_NAVY        0x0124
#define GFX_COLOR_SLATE_BLUE  0x0236
#define GFX_COLOR_CYAN        0x00EF
#define GFX_COLOR_DARK_CYAN   0x0068
#define GFX_COLOR_TEAL        0x00AA

#define GFX_COLOR_GREEN       0x02D4
#define GFX_COLOR_DARK_GREEN  0x0182
#define GFX_COLOR_BRIGHT_GRN  0x00F0

#define GFX_COLOR_RED         0x0E22
#define GFX_COLOR_DARK_RED    0x0811
#define GFX_COLOR_ORANGE      0x0F80
#define GFX_COLOR_YELLOW      0x0FE0

// Desktop UI Theme
#define THEME_DESK_BG         0x0124 // Deep royal slate
#define THEME_TASKBAR_BG      0x0112 // Modern dark bar
#define THEME_TASKBAR_TEXT    0x0FFF // Crisp white
#define THEME_WIN_BG          0x0DDE // Soft metallic slate
#define THEME_WIN_BORDER      0x0334 // Subtle window border
#define THEME_TITLE_ACTIVE    0x0248 // Vibrant cobalt blue
#define THEME_TITLE_INACTIVE  0x0667 // Muted slate grey
#define THEME_TITLE_TEXT      0x0FFF // White title text
#define THEME_BTN_FACE        0x0CCD // Button surface
#define THEME_BTN_BORDER_LGT  0x0EEF // 3D highlight
#define THEME_BTN_BORDER_DRK  0x0778 // 3D shadow
#define THEME_BTN_TEXT        0x0112 // Charcoal button text

// Graphics Primitives
void gfx_init(void);
void gfx_set_clip(int x0, int y0, int x1, int y1);
void gfx_reset_clip(void);

void gfx_put_pixel(int x, int y, uint16_t color);
uint16_t gfx_get_pixel(int x, int y);

void gfx_fill_rect(int x, int y, int w, int h, uint16_t color);
void gfx_draw_rect(int x, int y, int w, int h, uint16_t color);
void gfx_draw_line(int x0, int y0, int x1, int y1, uint16_t color);

void gfx_draw_char(int x, int y, char c, uint16_t fg, uint16_t bg, int transparent);
void gfx_draw_string(int x, int y, const char *str, uint16_t fg, uint16_t bg, int transparent);

void gfx_draw_gradient_v(int x, int y, int w, int h, uint16_t c_top, uint16_t c_bot);
void gfx_draw_button_3d(int x, int y, int w, int h, const char *label, int pressed);
void gfx_draw_window_frame(int x, int y, int w, int h, const char *title, int focused);

#endif
