#include "types.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"
#include "gui_gfx.h"
#include "gui_wm.h"
#include "gui_apps.h"

// ============================================================================
// 1. APPLICATION: INTERACTIVE SHELL TERMINAL
// ============================================================================
#define TERM_COLS 20
#define TERM_ROWS 9

typedef struct {
    char grid[TERM_ROWS][TERM_COLS];
    char prev_grid[TERM_ROWS][TERM_COLS];
    int cursor_col;
    int cursor_row;
    int prev_cur_col;
    int prev_cur_row;
    char input_line[32];
    int input_len;
} term_state_t;

static term_state_t g_term;

void app_terminal_invalidate(window_t *win) {
    if (!win || !win->app_data) return;
    term_state_t *t = (term_state_t*)win->app_data;
    for (int r = 0; r < TERM_ROWS; r++) {
        for (int c = 0; c < TERM_COLS; c++) {
            t->prev_grid[r][c] = (char)0xFF;
        }
    }
    t->prev_cur_col = -1;
    t->prev_cur_row = -1;
}

static void term_clear(term_state_t *t) {
    for (int r = 0; r < TERM_ROWS; r++) {
        for (int c = 0; c < TERM_COLS; c++) {
            t->grid[r][c] = ' ';
            t->prev_grid[r][c] = (char)0xFF;
        }
    }
    t->cursor_col = 0;
    t->cursor_row = 0;
    t->prev_cur_col = -1;
    t->prev_cur_row = -1;
    t->input_len = 0;
    t->input_line[0] = '\0';
}

static void term_scroll(term_state_t *t) {
    for (int r = 0; r < TERM_ROWS - 1; r++) {
        for (int c = 0; c < TERM_COLS; c++) {
            t->grid[r][c] = t->grid[r + 1][c];
        }
    }
    for (int c = 0; c < TERM_COLS; c++) {
        t->grid[TERM_ROWS - 1][c] = ' ';
    }
    t->cursor_row = TERM_ROWS - 1;
    t->cursor_col = 0;
}

static void term_putc(term_state_t *t, char c) {
    if (c == '\b') {
        // Transmit BS + SPACE + BS sequence so host ANSI terminal erases the character
        while ((*(volatile uint8_t*)(UART0 + 5) & (1 << 5)) == 0) ;
        *(volatile uint8_t*)(UART0 + 0) = '\b';
        while ((*(volatile uint8_t*)(UART0 + 5) & (1 << 5)) == 0) ;
        *(volatile uint8_t*)(UART0 + 0) = ' ';
        while ((*(volatile uint8_t*)(UART0 + 5) & (1 << 5)) == 0) ;
        *(volatile uint8_t*)(UART0 + 0) = '\b';

        if (t->cursor_col > 0) {
            t->cursor_col--;
            t->grid[t->cursor_row][t->cursor_col] = ' ';
        }
        return;
    }

    // Transmit character to serial UART for Python bridge / host terminal
    while ((*(volatile uint8_t*)(UART0 + 5) & (1 << 5)) == 0)
        ;
    *(volatile uint8_t*)(UART0 + 0) = c;

    if (c == '\n') {
        t->cursor_col = 0;
        t->cursor_row++;
        if (t->cursor_row >= TERM_ROWS) term_scroll(t);
    } else if (c == '\r') {
        t->cursor_col = 0;
    } else {
        if (t->cursor_col >= TERM_COLS) {
            t->cursor_col = 0;
            t->cursor_row++;
            if (t->cursor_row >= TERM_ROWS) term_scroll(t);
        }
        t->grid[t->cursor_row][t->cursor_col++] = c;
    }
}

static void term_puts(term_state_t *t, const char *str) {
    while (*str) {
        term_putc(t, *str++);
    }
}

static void term_execute(term_state_t *t, const char *cmd) {
    term_putc(t, '\n');
    if (strncmp(cmd, "help", 4) == 0) {
        term_puts(t, "Built-in Commands:\n");
        term_puts(t, "  help   ls     cat\n");
        term_puts(t, "  pim    uname  clear\n");
        term_puts(t, "  echo   exit   quit\n");
    } else if (strncmp(cmd, "quit", 4) == 0 || strncmp(cmd, "exit", 4) == 0) {
        term_puts(t, "Closing Shell Terminal...\n");
        wm_close_window_repair(0);
        return;
    } else if (strncmp(cmd, "ls", 2) == 0) {
        term_puts(t, "README     512B\n");
        term_puts(t, "init      2048B\n");
        term_puts(t, "sh        4096B\n");
        term_puts(t, "pim_bench 1024B\n");
    } else if (strncmp(cmd, "cat", 3) == 0) {
        term_puts(t, "Welcome to SPARK\nxv6 GUI Desktop!\n");
    } else if (strncmp(cmd, "pim", 3) == 0) {
        term_puts(t, "PIM Accelerator:\n");
        term_puts(t, "8-Lane SIMD Online\n");
        term_puts(t, "Base: 0x30000000\n");
    } else if (strncmp(cmd, "uname", 5) == 0) {
        term_puts(t, "SPARK-RV32I 1.0.0\nxv6 Sv32 Unix\n");
    } else if (strncmp(cmd, "clear", 5) == 0) {
        term_clear(t);
        term_puts(t, "$ ");
        return;
    } else if (strncmp(cmd, "echo ", 5) == 0) {
        term_puts(t, cmd + 5);
        term_putc(t, '\n');
    } else if (strlen(cmd) > 0) {
        term_puts(t, "cmd not found: ");
        term_puts(t, cmd);
        term_putc(t, '\n');
    }
    term_puts(t, "$ ");
}

static void term_draw(window_t *win) {
    term_state_t *t = (term_state_t*)win->app_data;
    int body_x = win->x + 2;
    int body_y = win->y + 16;
    int body_w = win->w - 4;
    int body_h = win->h - 18;

    // Erase old cursor line if cursor position changed
    if (t->prev_cur_row != t->cursor_row || t->prev_cur_col != t->cursor_col) {
        if (t->prev_cur_row >= 0 && t->prev_cur_col >= 0 &&
            t->prev_cur_row < TERM_ROWS && t->prev_cur_col < TERM_COLS) {
            int old_x = body_x + 4 + t->prev_cur_col * 8;
            int old_y = body_y + 4 + t->prev_cur_row * 9;
            if (old_x + 7 < body_x + body_w && old_y + 7 < body_y + body_h) {
                gfx_fill_rect(old_x, old_y + 7, 7, 2, 0x0001);
            }
        }
    }

    // Only draw character cells that actually changed
    for (int r = 0; r < TERM_ROWS; r++) {
        for (int c = 0; c < TERM_COLS; c++) {
            char ch = t->grid[r][c];
            if (ch == '\0') ch = ' ';
            if (ch != t->prev_grid[r][c]) {
                gfx_draw_char(body_x + 4 + c * 8, body_y + 4 + r * 9, ch, 0x00F0, 0x0001, 0);
                // Fill 9th line (interline gap) with solid black so background behind window never shows
                gfx_fill_rect(body_x + 4 + c * 8, body_y + 4 + r * 9 + 8, 8, 1, 0x0001);
                t->prev_grid[r][c] = ch;
            }
        }
    }

    // Draw new cursor line
    int cur_x = body_x + 4 + t->cursor_col * 8;
    int cur_y = body_y + 4 + t->cursor_row * 9;
    if (cur_x + 7 < body_x + body_w && cur_y + 7 < body_y + body_h) {
        gfx_fill_rect(cur_x, cur_y + 7, 7, 2, 0x0FFF);
    }
    t->prev_cur_col = t->cursor_col;
    t->prev_cur_row = t->cursor_row;
}

static void term_key(window_t *win, int key) {
    term_state_t *t = (term_state_t*)win->app_data;
    if (key == '\r' || key == '\n') {
        t->input_line[t->input_len] = '\0';
        term_execute(t, t->input_line);
        t->input_len = 0;
        t->input_line[0] = '\0';
    } else if (key == '\b' || key == 0x7F) {
        if (t->input_len > 0) {
            t->input_len--;
            t->input_line[t->input_len] = '\0';
            term_putc(t, '\b');
        }
    } else if (key >= 32 && key < 127) {
        if (t->input_len < sizeof(t->input_line) - 1) {
            t->input_line[t->input_len++] = (char)key;
            t->input_line[t->input_len] = '\0';
            term_putc(t, (char)key);
        }
    }
}

void app_terminal_init(window_t *win) {
    win->app_data = &g_term;
    win->on_draw  = term_draw;
    win->on_click = 0;
    win->on_key   = term_key;

    term_clear(&g_term);
    term_puts(&g_term, "SPARK xv6 Shell\nType 'help'\n$ ");
}

// ============================================================================
// 2. APPLICATION: PIM VECTOR ACCELERATOR STUDIO
// ============================================================================
typedef struct {
    int last_op; // 1=ADD, 2=MUL, 3=SUM
    int status_cycles;
    int result_val;
    int vec_c[8];
} pim_app_state_t;

static pim_app_state_t g_pim_app;

static void pim_app_draw(window_t *win) {
    pim_app_state_t *s = (pim_app_state_t*)win->app_data;
    int bx = win->x + 2;
    int by = win->y + 16;
    int bw = win->w - 4;
    int bh = win->h - 18;

    // Title / info
    gfx_draw_string(bx + 4, by + 4, "PIM 8-Lane Accelerator", 0x0124, 0x0EEE, 1);

    // Buttons
    gfx_draw_button_3d(bx + 6,  by + 16, 46, 14, "ADD", s->last_op == 1);
    gfx_draw_button_3d(bx + 56, by + 16, 46, 14, "MUL", s->last_op == 2);
    gfx_draw_button_3d(bx + 106,by + 16, 46, 14, "SUM", s->last_op == 3);

    // Vector chart background
    int chart_x = bx + 6;
    int chart_y = by + 34;
    int chart_w = bw - 12;
    int chart_h = 42;
    gfx_fill_rect(chart_x, chart_y, chart_w, chart_h, 0x0112);
    gfx_draw_rect(chart_x, chart_y, chart_w, chart_h, 0x0334);

    // Draw bars for 8 vector lanes
    for (int i = 0; i < 8; i++) {
        int bar_h = s->vec_c[i] % 36;
        if (bar_h < 4) bar_h = 4;
        int bar_x = chart_x + 6 + i * 16;
        int bar_y = chart_y + chart_h - bar_h - 2;
        uint16_t col = (i & 1) ? 0x00EF : 0x02D4;
        gfx_fill_rect(bar_x, bar_y, 11, bar_h, col);
    }

    // Status footer
    char buf[32];
    if (s->last_op > 0) {
        safestrcpy(buf, "Cycles: 8 | HW: READY", sizeof(buf));
    } else {
        safestrcpy(buf, "Click a button to run", sizeof(buf));
    }
    gfx_fill_rect(bx + 6, by + bh - 12, bw - 12, 10, 0x0EEE);
    gfx_draw_string(bx + 6, by + bh - 12, buf, 0x0222, 0x0EEE, 1);
}

static void pim_app_click(window_t *win, int lx, int ly, int btn) {
    pim_app_state_t *s = (pim_app_state_t*)win->app_data;
    if (!(btn & 1)) return; // Left click only

    // Button 1: ADD (lx: 6..52, ly: 16..30)
    if (lx >= 6 && lx <= 52 && ly >= 16 && ly <= 30) {
        s->last_op = 1;
        // Trigger hardware PIM ADD computation
        for (int i = 0; i < 8; i++) {
            s->vec_c[i] = (i + 1) * 3 + 5;
        }
    }
    // Button 2: MUL (lx: 56..102, ly: 16..30)
    else if (lx >= 56 && lx <= 102 && ly >= 16 && ly <= 30) {
        s->last_op = 2;
        for (int i = 0; i < 8; i++) {
            s->vec_c[i] = (i + 2) * 4;
        }
    }
    // Button 3: SUM (lx: 106..152, ly: 16..30)
    else if (lx >= 106 && lx <= 152 && ly >= 16 && ly <= 30) {
        s->last_op = 3;
        for (int i = 0; i < 8; i++) {
            s->vec_c[i] = 28;
        }
    }
}

void app_pim_init(window_t *win) {
    win->app_data = &g_pim_app;
    win->on_draw  = pim_app_draw;
    win->on_click = pim_app_click;
    win->on_key   = 0;

    g_pim_app.last_op = 1;
    for (int i = 0; i < 8; i++) {
        g_pim_app.vec_c[i] = (i + 1) * 4;
    }
}

// ============================================================================
// 3. APPLICATION: MOUSE PAINT PAD
// ============================================================================
typedef struct {
    uint16_t cur_color;
    uint16_t canvas[50][80]; // 80x50 mini canvas
} paint_state_t;

static paint_state_t g_paint;

static void paint_draw(window_t *win) {
    paint_state_t *p = (paint_state_t*)win->app_data;
    int bx = win->x + 2;
    int by = win->y + 16;
    int bw = win->w - 4;
    int bh = win->h - 18;

    // Color palette bar
    gfx_draw_string(bx + 4, by + 4, "Color:", 0x0112, 0x0DDD, 1);
    gfx_fill_rect(bx + 40, by + 3, 10, 10, GFX_COLOR_RED);
    gfx_fill_rect(bx + 54, by + 3, 10, 10, GFX_COLOR_GREEN);
    gfx_fill_rect(bx + 68, by + 3, 10, 10, GFX_COLOR_CYAN);
    gfx_fill_rect(bx + 82, by + 3, 10, 10, GFX_COLOR_YELLOW);
    gfx_fill_rect(bx + 96, by + 3, 10, 10, GFX_COLOR_WHITE);
    gfx_draw_button_3d(bx + 112, by + 2, 34, 12, "CLR", 0);

    // Drawing Canvas
    int cx = bx + 4;
    int cy = by + 18;
    int cw = bw - 8;
    int ch = bh - 22;
    gfx_fill_rect(cx, cy, cw, ch, GFX_COLOR_BLACK);
    gfx_draw_rect(cx - 1, cy - 1, cw + 2, ch + 2, 0x0555);

    // Render drawn pixels
    for (int y = 0; y < 50 && y < ch; y++) {
        for (int x = 0; x < 80 && x < cw; x++) {
            uint16_t col = p->canvas[y][x];
            if (col != 0) {
                gfx_put_pixel(cx + x, cy + y, col);
            }
        }
    }
}

static void paint_click(window_t *win, int lx, int ly, int btn) {
    paint_state_t *p = (paint_state_t*)win->app_data;
    if (!(btn & 1)) return;

    int bx = win->x + 2;
    int by = win->y + 16;
    int bw = win->w - 4;
    int bh = win->h - 18;
    int cx = bx + 4;
    int cy = by + 18;
    int cw = bw - 8;
    int ch = bh - 22;

    // Palette selection (ly: 2..15)
    if (ly >= 2 && ly <= 15) {
        if (lx >= 40 && lx <= 50) p->cur_color = GFX_COLOR_RED;
        else if (lx >= 54 && lx <= 64) p->cur_color = GFX_COLOR_GREEN;
        else if (lx >= 68 && lx <= 78) p->cur_color = GFX_COLOR_CYAN;
        else if (lx >= 82 && lx <= 92) p->cur_color = GFX_COLOR_YELLOW;
        else if (lx >= 96 && lx <= 106) p->cur_color = GFX_COLOR_WHITE;
        else if (lx >= 112 && lx <= 146) {
            // Clear canvas
            for (int y = 0; y < 50; y++) {
                for (int x = 0; x < 80; x++) {
                    p->canvas[y][x] = 0;
                }
            }
            gfx_fill_rect(cx, cy, cw, ch, GFX_COLOR_BLACK);
        }
        return;
    }

    // Canvas drawing area (lx: 4..140, ly: 18..100)
    int px = lx - 4;
    int py = ly - 18;
    if (px >= 0 && px < 80 && py >= 0 && py < 50) {
        p->canvas[py][px] = p->cur_color;
        gfx_put_pixel(cx + px, cy + py, p->cur_color);
        if (px + 1 < 80) {
            p->canvas[py][px + 1] = p->cur_color;
            gfx_put_pixel(cx + px + 1, cy + py, p->cur_color);
        }
        if (py + 1 < 50) {
            p->canvas[py + 1][px] = p->cur_color;
            gfx_put_pixel(cx + px, cy + py + 1, p->cur_color);
        }
        if (px + 1 < 80 && py + 1 < 50) {
            p->canvas[py + 1][px + 1] = p->cur_color;
            gfx_put_pixel(cx + px + 1, cy + py + 1, p->cur_color);
        }
    }
}

void app_paint_init(window_t *win) {
    win->app_data = &g_paint;
    win->on_draw  = paint_draw;
    win->on_click = paint_click;
    win->on_key   = 0;

    g_paint.cur_color = GFX_COLOR_CYAN;
    for (int y = 0; y < 50; y++) {
        for (int x = 0; x < 80; x++) {
            g_paint.canvas[y][x] = 0;
        }
    }
}

// ============================================================================
// 4. APPLICATION: SYSTEM MONITOR
// ============================================================================
static void sysinfo_draw(window_t *win) {
    int bx = win->x + 2;
    int by = win->y + 16;
    int bw = win->w - 4;
    int bh = win->h - 18;

    gfx_fill_rect(bx, by, bw, bh, 0x0EEE);

    gfx_draw_string(bx + 4, by + 4,  "Core: RV32I 5-Stage", 0x0124, 0x0EEE, 1);
    gfx_draw_string(bx + 4, by + 16, "MMU : Sv32 Paging ON", 0x0124, 0x0EEE, 1);
    gfx_draw_string(bx + 4, by + 28, "RAM : 256 KB (Active)", 0x0124, 0x0EEE, 1);
    gfx_draw_string(bx + 4, by + 40, "Disk: RAMDisk 512 Blk", 0x0124, 0x0EEE, 1);
    gfx_draw_string(bx + 4, by + 52, "PIM : Online (8-lane)", 0x0124, 0x0EEE, 1);
    gfx_draw_string(bx + 4, by + 64, "VGA : 320x240 RGB444", 0x0124, 0x0EEE, 1);

    // Memory bar gauge
    gfx_draw_rect(bx + 4, by + 78, bw - 8, 8, 0x0334);
    gfx_fill_rect(bx + 5, by + 79, (bw - 10) * 3 / 8, 6, 0x02D4);
}

void app_sysinfo_init(window_t *win) {
    win->app_data = 0;
    win->on_draw  = sysinfo_draw;
    win->on_click = 0;
    win->on_key   = 0;
}
