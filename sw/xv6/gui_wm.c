#include "types.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"
#include "gui_gfx.h"
#include "gui_wm.h"
#include "gui_apps.h"

static window_t g_windows[MAX_WINDOWS];
static int g_num_windows = 0;
static int g_focused_id = -1;

// Dragging state
static int g_drag_win_id = -1;
static int g_drag_offset_x = 0;
static int g_drag_offset_y = 0;
static int g_drag_target_x = 0;
static int g_drag_target_y = 0;
static int g_drag_has_moved = 0;

// Mouse tracking
static int g_mouse_x = 160;
static int g_mouse_y = 120;
static int g_mouse_btn = 0;
static int g_prev_btn = 0;

// Menu toggle
static int g_menu_open = 0;
static uint32_t g_ticks = 0;
static int g_wm_ready = 0;

// Hardware Mouse MMIO read
void mouse_get_state(int *out_x, int *out_y, int *out_btn) {
    uint32_t scr, msr;
    asm volatile("lw %0, 7(%1)" : "=r"(scr) : "r"(UART0));
    asm volatile("lw %0, 6(%1)" : "=r"(msr) : "r"(UART0));

    int mx = (scr >> 16) & 0x3FF;
    int my = scr & 0x1FF;
    int btn = msr & 0x7;

    *out_x = (mx < 0) ? 0 : (mx >= SCREEN_W ? SCREEN_W - 1 : mx);
    *out_y = (my < 0) ? 0 : (my >= SCREEN_H ? SCREEN_H - 1 : my);
    *out_btn = btn;
}

window_t* wm_create_window(const char *title, int x, int y, int w, int h, int app_type) {
    if (g_num_windows >= MAX_WINDOWS) return 0;
    int id = g_num_windows++;
    window_t *win = &g_windows[id];

    win->id = id;
    safestrcpy(win->title, title, sizeof(win->title));
    win->x = x;
    win->y = y;
    win->w = w;
    win->h = h;
    win->flags = WIN_FLAG_VISIBLE | WIN_FLAG_FOCUSED;
    win->app_type = app_type;

    if (app_type == APP_TYPE_TERMINAL) app_terminal_init(win);
    else if (app_type == APP_TYPE_PIM) app_pim_init(win);
    else if (app_type == APP_TYPE_PAINT) app_paint_init(win);
    else if (app_type == APP_TYPE_SYSINFO) app_sysinfo_init(win);

    wm_focus_window(id);
    return win;
}

void wm_destroy_window(int id) {
    if (id >= 0 && id < g_num_windows) {
        g_windows[id].flags &= ~WIN_FLAG_VISIBLE;
    }
}

void wm_render_window_title(window_t *win) {
    if (!(win->flags & WIN_FLAG_VISIBLE)) return;

    int focused = (win->flags & WIN_FLAG_FOCUSED);
    uint16_t title_c1 = focused ? THEME_TITLE_ACTIVE : THEME_TITLE_INACTIVE;
    uint16_t title_c2 = focused ? 0x0125 : 0x0445;
    gfx_draw_gradient_v(win->x + 1, win->y + 1, win->w - 2, 14, title_c1, title_c2);
    gfx_draw_string(win->x + 4, win->y + 4, win->title, THEME_TITLE_TEXT, title_c1, 1);

    // Close button [X]
    int bx = win->x + win->w - 14;
    int by = win->y + 2;
    gfx_fill_rect(bx, by, 11, 11, GFX_COLOR_RED);
    gfx_draw_rect(bx, by, 11, 11, GFX_COLOR_DARK_RED);
    gfx_draw_string(bx + 2, by + 2, "x", GFX_COLOR_WHITE, GFX_COLOR_RED, 1);
}

void wm_focus_window(int id) {
    if (id < 0 || id >= g_num_windows) return;
    if (g_focused_id == id && (g_windows[id].flags & WIN_FLAG_VISIBLE)) return;

    int old_id = g_focused_id;
    for (int i = 0; i < g_num_windows; i++) {
        g_windows[i].flags &= ~WIN_FLAG_FOCUSED;
    }
    g_windows[id].flags |= WIN_FLAG_FOCUSED;
    g_windows[id].flags |= WIN_FLAG_VISIBLE;
    g_focused_id = id;

    if (!g_wm_ready) return;

    // Smooth focus switch:
    // Update old window title to inactive
    if (old_id >= 0 && old_id < g_num_windows && (g_windows[old_id].flags & WIN_FLAG_VISIBLE)) {
        wm_render_window_title(&g_windows[old_id]);
    }
    // Render newly focused window on top
    wm_render_single_window(&g_windows[id]);

    // Update taskbar
    wm_render_taskbar();
}

window_t* wm_get_focused(void) {
    if (g_focused_id >= 0 && g_focused_id < g_num_windows) {
        return &g_windows[g_focused_id];
    }
    return 0;
}

// ============================================================================
// Desktop & Taskbar Rendering
// ============================================================================
void wm_render_desktop_bg(void) {
    // Fast solid fill of deep slate navy (10x faster than per-line software division gradient)
    gfx_fill_rect(0, 16, SCREEN_W, SCREEN_H - 16, 0x0124);

    // Desktop Watermark / Brand Logo
    gfx_draw_string(SCREEN_W - 120, SCREEN_H - 24, "SPARK RISC-V", 0x0346, 0x0124, 1);
    gfx_draw_string(SCREEN_W - 120, SCREEN_H - 14, "MIT xv6 Desktop", 0x0235, 0x0124, 1);
}

void wm_render_taskbar(void) {
    // Taskbar bar
    gfx_fill_rect(0, 0, SCREEN_W, 16, THEME_TASKBAR_BG);
    gfx_fill_rect(0, 15, SCREEN_W, 1, 0x0334); // Bottom border line

    // Start Button
    gfx_draw_button_3d(2, 2, 48, 12, "SPARK", g_menu_open);

    // Active Window Title in middle
    if (g_drag_win_id >= 0 && g_drag_has_moved) {
        gfx_draw_string(56, 4, "[Moving Window]", 0x0FE2, THEME_TASKBAR_BG, 1);
    } else {
        window_t *focused = wm_get_focused();
        if (focused && (focused->flags & WIN_FLAG_VISIBLE)) {
            gfx_draw_string(56, 4, focused->title, 0x00EF, THEME_TASKBAR_BG, 1);
        }
    }

    // Hardware status: PIM Badge (Green = READY)
    gfx_fill_rect(SCREEN_W - 74, 4, 8, 8, GFX_COLOR_BRIGHT_GRN);
    gfx_draw_string(SCREEN_W - 62, 4, "PIM", 0x0FFF, THEME_TASKBAR_BG, 1);

    // Clock
    int secs = (g_ticks / 10) % 60;
    int mins = (g_ticks / 600) % 60;
    char time_buf[10];
    time_buf[0] = '1';
    time_buf[1] = '2';
    time_buf[2] = ':';
    time_buf[3] = '0' + (mins / 10);
    time_buf[4] = '0' + (mins % 10);
    time_buf[5] = ':';
    time_buf[6] = '0' + (secs / 10);
    time_buf[7] = '0' + (secs % 10);
    time_buf[8] = '\0';
    gfx_draw_string(SCREEN_W - 32, 4, time_buf + 3, 0x0EEE, THEME_TASKBAR_BG, 1);
}

void wm_render_icons(void) {
    // Icon 1: Terminal
    gfx_fill_rect(8, 24, 28, 24, 0x0112);
    gfx_draw_rect(8, 24, 28, 24, 0x00EF);
    gfx_draw_string(14, 32, ">_", 0x00F0, 0x0112, 1);
    gfx_draw_string(4, 50, "Terminal", 0x0FFF, 0x0123, 1);

    // Icon 2: PIM Studio
    gfx_fill_rect(8, 64, 28, 24, 0x0112);
    gfx_draw_rect(8, 64, 28, 24, 0x02D4);
    gfx_draw_string(14, 72, "SIMD", 0x00EF, 0x0112, 1);
    gfx_draw_string(8, 90, "PIM OS", 0x0FFF, 0x0123, 1);

    // Icon 3: Paint Pad
    gfx_fill_rect(8, 104, 28, 24, 0x0112);
    gfx_draw_rect(8, 104, 28, 24, 0x0FE0);
    gfx_draw_string(16, 112, "@", 0x0FE0, 0x0112, 1);
    gfx_draw_string(8, 130, "Paint", 0x0FFF, 0x0123, 1);

    // Icon 4: System Info
    gfx_fill_rect(8, 144, 28, 24, 0x0112);
    gfx_draw_rect(8, 144, 28, 24, 0x0CCC);
    gfx_draw_string(18, 152, "i", 0x0FFF, 0x0112, 1);
    gfx_draw_string(4, 170, "SysInfo", 0x0FFF, 0x0123, 1);
}

void wm_render_single_window(window_t *win) {
    if (!(win->flags & WIN_FLAG_VISIBLE)) return;

    int focused = (win->flags & WIN_FLAG_FOCUSED);
    gfx_draw_window_frame(win->x, win->y, win->w, win->h, win->title, focused);

    int bx = win->x + 2;
    int by = win->y + 16;
    int bw = win->w - 4;
    int bh = win->h - 18;

    if (win->app_type == APP_TYPE_TERMINAL) {
        // Fill entire body with 0x0001 so terminal background is 100% solid and opaque
        gfx_fill_rect(bx, by, bw, bh, 0x0001);
        app_terminal_invalidate(win);
    } else {
        uint16_t body_bg = THEME_WIN_BG;
        if (win->app_type == APP_TYPE_PIM) body_bg = 0x0EEE;
        else if (win->app_type == APP_TYPE_PAINT) body_bg = 0x0DDD;
        else if (win->app_type == APP_TYPE_SYSINFO) body_bg = 0x0EEE;
        gfx_fill_rect(bx, by, bw, bh, body_bg);
    }

    // Set clipping inside client area
    gfx_set_clip(bx, by, bx + bw - 1, by + bh - 1);

    // Call application drawing callback
    if (win->on_draw) {
        win->on_draw(win);
    }

    gfx_reset_clip();
}

void wm_render_window_client(window_t *win) {
    if (!(win->flags & WIN_FLAG_VISIBLE)) return;

    // Set clipping inside client area
    gfx_set_clip(win->x + 2, win->y + 16, win->x + win->w - 3, win->y + win->h - 3);

    // Call application drawing callback
    if (win->on_draw) {
        win->on_draw(win);
    }

    gfx_reset_clip();
}

void wm_render_all(void) {
    wm_render_desktop_bg();
    wm_render_icons();

    // Render unfocused windows first
    for (int i = 0; i < g_num_windows; i++) {
        if ((g_windows[i].flags & WIN_FLAG_VISIBLE) && !(g_windows[i].flags & WIN_FLAG_FOCUSED)) {
            wm_render_single_window(&g_windows[i]);
        }
    }

    // Render focused window on top
    window_t *focused = wm_get_focused();
    if (focused && (focused->flags & WIN_FLAG_VISIBLE)) {
        wm_render_single_window(focused);
    }

    // Render taskbar
    wm_render_taskbar();

    // Render Start Menu if open
    if (g_menu_open) {
        gfx_fill_rect(2, 16, 80, 68, 0x0223);
        gfx_draw_rect(2, 16, 80, 68, 0x0446);
        gfx_draw_string(6, 20, "Terminal", 0x0FFF, 0x0223, 1);
        gfx_draw_string(6, 34, "PIM Studio", 0x0FFF, 0x0223, 1);
        gfx_draw_string(6, 48, "Paint Pad", 0x0FFF, 0x0223, 1);
        gfx_draw_string(6, 62, "Sys Info", 0x0FFF, 0x0223, 1);
    }
}

void wm_open_menu(void) {
    g_menu_open = 1;
    gfx_draw_button_3d(2, 2, 48, 12, "SPARK", 1);
    gfx_fill_rect(2, 16, 80, 68, 0x0223);
    gfx_draw_rect(2, 16, 80, 68, 0x0446);
    gfx_draw_string(6, 20, "Terminal", 0x0FFF, 0x0223, 1);
    gfx_draw_string(6, 34, "PIM Studio", 0x0FFF, 0x0223, 1);
    gfx_draw_string(6, 48, "Paint Pad", 0x0FFF, 0x0223, 1);
    gfx_draw_string(6, 62, "Sys Info", 0x0FFF, 0x0223, 1);
}

void wm_close_menu(void) {
    g_menu_open = 0;
    gfx_draw_button_3d(2, 2, 48, 12, "SPARK", 0);
    gfx_fill_rect(2, 16, 80, 68, 0x0124);

    // Redraw icons under menu
    wm_render_icons();

    // Redraw any window that intersects menu area (2, 16, 80, 68)
    for (int i = 0; i < g_num_windows; i++) {
        window_t *w = &g_windows[i];
        if (w->flags & WIN_FLAG_VISIBLE) {
            if (!(w->x >= 82 || w->x + w->w <= 2 || w->y >= 84 || w->y + w->h <= 16)) {
                wm_render_single_window(w);
            }
        }
    }
}

void wm_close_window_repair(int id) {
    if (id < 0 || id >= g_num_windows) return;
    window_t *w = &g_windows[id];
    int cx = w->x, cy = w->y, cw = w->w + 2, ch = w->h + 2;
    wm_destroy_window(id);

    // Determine next focused window immediately
    int next_focus = -1;
    for (int i = 0; i < g_num_windows; i++) {
        if (g_windows[i].flags & WIN_FLAG_VISIBLE) {
            next_focus = i;
            break;
        }
    }

    // Update focus flags before redrawing
    g_focused_id = next_focus;
    for (int i = 0; i < g_num_windows; i++) {
        if (i == next_focus) g_windows[i].flags |= WIN_FLAG_FOCUSED;
        else g_windows[i].flags &= ~WIN_FLAG_FOCUSED;
    }

    // Erase the closed window bounding box with desktop background
    gfx_fill_rect(cx, cy, cw, ch, 0x0124);

    // Redraw watermark if in lower-right
    if (cx + cw >= SCREEN_W - 120 && cy + ch >= SCREEN_H - 24) {
        gfx_draw_string(SCREEN_W - 120, SCREEN_H - 24, "SPARK RISC-V", 0x0346, 0x0124, 1);
        gfx_draw_string(SCREEN_W - 120, SCREEN_H - 14, "MIT xv6 Desktop", 0x0235, 0x0124, 1);
    }

    // If icons overlap the closed area, redraw icons
    if (cx < 42) wm_render_icons();

    // Redraw non-focused visible windows that overlapped the closed area
    for (int i = 0; i < g_num_windows; i++) {
        if (i == next_focus) continue;
        window_t *rw = &g_windows[i];
        if (rw->flags & WIN_FLAG_VISIBLE) {
            if (!(rw->x >= cx + cw || rw->x + rw->w <= cx ||
                  rw->y >= cy + ch || rw->y + rw->h <= cy)) {
                wm_render_single_window(rw);
            }
        }
    }

    // Render newly focused window on top ONCE
    if (next_focus >= 0) {
        wm_render_single_window(&g_windows[next_focus]);
    }

    wm_render_taskbar();
}

// ============================================================================
// Event Processing (Mouse & Keyboard)
// ============================================================================
int wm_process_mouse(int mx, int my, int btn) {
    int left_press = (btn & 1) && !(g_prev_btn & 1);
    int left_release = !(btn & 1) && (g_prev_btn & 1);
    int left_held = (btn & 1);

    // 1. Handle Active Window Dragging (track target coordinates smoothly while held)
    if (g_drag_win_id >= 0) {
        if (left_held) {
            window_t *dwin = &g_windows[g_drag_win_id];
            int nx = mx - g_drag_offset_x;
            int ny = my - g_drag_offset_y;
            // Bound to desktop
            if (nx < 0) nx = 0;
            if (ny < 16) ny = 16;
            if (nx + dwin->w > SCREEN_W) nx = SCREEN_W - dwin->w;
            if (ny + dwin->h > SCREEN_H) ny = SCREEN_H - dwin->h;

            if (nx != g_drag_target_x || ny != g_drag_target_y) {
                g_drag_target_x = nx;
                g_drag_target_y = ny;
                if (!g_drag_has_moved) {
                    g_drag_has_moved = 1;
                    wm_render_taskbar();
                }
            }
            return 0; // Pure tracking during drag: zero VRAM writes, zero lag, zero flicker!
        }
    }

    // 2. Click Handling on Mouse Press
    if (left_press) {
        // Taskbar Start button click (x: 2..50, y: 0..16)
        if (my < 16) {
            if (mx >= 2 && mx <= 50) {
                if (g_menu_open) wm_close_menu();
                else wm_open_menu();
                return 0; // Localized menu toggle, NO full desktop wipe!
            }
        }

        // Start menu item clicks
        if (g_menu_open && mx >= 2 && mx <= 82 && my >= 16 && my <= 84) {
            int target_id = 0;
            if (my < 32) target_id = 0;      // Terminal
            else if (my < 46) target_id = 1; // PIM
            else if (my < 60) target_id = 2; // Paint
            else target_id = 3;             // SysInfo

            wm_close_menu();
            wm_focus_window(target_id);
            return 0; // Smoothly opened and focused, NO full desktop wipe!
        }
        if (g_menu_open) {
            wm_close_menu();
            return 0;
        }

        // Desktop Icons click (x: 4..42)
        if (mx >= 4 && mx <= 42) {
            int target_id = -1;
            if (my >= 24 && my <= 58) target_id = 0;      // Terminal
            else if (my >= 64 && my <= 98) target_id = 1; // PIM
            else if (my >= 104 && my <= 138) target_id = 2; // Paint
            else if (my >= 144 && my <= 178) target_id = 3; // SysInfo

            if (target_id >= 0) {
                if (g_focused_id == target_id && (g_windows[target_id].flags & WIN_FLAG_VISIBLE)) {
                    return 0; // Already focused!
                }
                wm_focus_window(target_id);
                return 0; // Smoothly focused, no full desktop wipe!
            }
        }

        // Check Windows (Focused window first)
        for (int step = 0; step < 2; step++) {
            for (int i = 0; i < g_num_windows; i++) {
                window_t *w = &g_windows[i];
                if (!(w->flags & WIN_FLAG_VISIBLE)) continue;
                if (step == 0 && !(w->flags & WIN_FLAG_FOCUSED)) continue;
                if (step == 1 && (w->flags & WIN_FLAG_FOCUSED)) continue;

                if (mx >= w->x && mx < w->x + w->w && my >= w->y && my < w->y + w->h) {
                    // Check Close button [X] FIRST (x: w->x + w->w - 14..w->x + w->w - 3, y: w->y+2..w->y+13)
                    if (mx >= w->x + w->w - 14 && my >= w->y + 2 && my <= w->y + 13) {
                        wm_close_window_repair(w->id);
                        return 0; // Localized repair, NO full desktop wipe!
                    }

                    if (g_focused_id != w->id) {
                        wm_focus_window(w->id);
                    }

                    // Check Title Bar Drag (y: w->y..w->y+15)
                    if (my < w->y + 15) {
                        g_drag_win_id = w->id;
                        g_drag_offset_x = mx - w->x;
                        g_drag_offset_y = my - w->y;
                        g_drag_target_x = w->x;
                        g_drag_target_y = w->y;
                        g_drag_has_moved = 0;
                        return 0;
                    }

                    // Client area click
                    if (w->on_click) {
                        w->on_click(w, mx - (w->x + 2), my - (w->y + 16), btn);
                        if (w->app_type == APP_TYPE_PAINT) {
                            return 0; // Pixels written directly to VRAM
                        }
                        return 1;
                    }
                    return 0; // Terminal or SysInfo has no on_click: 0 redraws!
                }
            }
        }
    }

    // Continuous dragging/clicking in Paint canvas
    if (left_held && g_drag_win_id < 0) {
        window_t *focused = wm_get_focused();
        if (focused && (focused->flags & WIN_FLAG_VISIBLE) && focused->app_type == APP_TYPE_PAINT) {
            int cx = focused->x + 2;
            int cy = focused->y + 16;
            if (mx >= cx + 4 && mx < cx + 4 + 80 && my >= cy + 18 && my < cy + 18 + 50) {
                if (focused->on_click) {
                    focused->on_click(focused, mx - cx, my - cy, btn);
                }
                return 0;
            }
        }
    }

    if (left_release) {
        if (g_drag_win_id >= 0) {
            window_t *dwin = &g_windows[g_drag_win_id];
            if (g_drag_has_moved && (dwin->x != g_drag_target_x || dwin->y != g_drag_target_y)) {
                int old_x = dwin->x;
                int old_y = dwin->y;
                int w = dwin->w + 2;
                int h = dwin->h + 2;

                dwin->x = g_drag_target_x;
                dwin->y = g_drag_target_y;

                // Erase old window bounding box
                gfx_fill_rect(old_x, old_y, w, h, 0x0124);
                if (old_x < 42) wm_render_icons();

                // Redraw any other visible window that intersected the old area
                for (int i = 0; i < g_num_windows; i++) {
                    if (i == g_drag_win_id) continue;
                    window_t *rw = &g_windows[i];
                    if (rw->flags & WIN_FLAG_VISIBLE) {
                        if (!(rw->x >= old_x + w || rw->x + rw->w <= old_x ||
                              rw->y >= old_y + h || rw->y + rw->h <= old_y)) {
                            wm_render_single_window(rw);
                        }
                    }
                }

                // Render dragged window at its new position on top
                wm_render_single_window(dwin);
            }
            g_drag_win_id = -1;
            g_drag_has_moved = 0;
            wm_render_taskbar();
            return 0;
        }
    }

    return 0; // Pure mouse motion: 0 VRAM redraws
}

void wm_process_key(int key) {
    window_t *focused = wm_get_focused();
    if (focused && (focused->flags & WIN_FLAG_VISIBLE)) {
        if (focused->on_key) {
            focused->on_key(focused, key);
        }
    }
}

// ============================================================================
// Initialization & Main Desktop Execution Loop
// ============================================================================
void wm_init(void) {
    gfx_init();
    g_num_windows = 0;
    g_focused_id = -1;
    g_drag_win_id = -1;

    // Create standard desktop application windows
    // 1. Terminal Window (Focused by default, center-left)
    wm_create_window("Shell Terminal", 50, 30, 180, 120, APP_TYPE_TERMINAL);

    // 2. PIM Accelerator Window (Right side)
    wm_create_window("PIM Studio", 140, 60, 170, 130, APP_TYPE_PIM);

    // 3. Paint Pad Window
    wm_create_window("Paint Pad", 60, 80, 170, 130, APP_TYPE_PAINT);

    // 4. System Info Window
    wm_create_window("System Info", 120, 40, 180, 110, APP_TYPE_SYSINFO);

    // Bring Terminal window to front initially
    wm_focus_window(0);
    g_wm_ready = 1;
}

void wm_run_desktop(void) {
    wm_init();

    int last_mx = -1, last_my = -1, last_btn = -1;
    int dirty = 2; // Initial full render

    for (;;) {
        g_ticks++;

        // 1. Poll hardware mouse coordinates & buttons
        int mx, my, btn;
        mouse_get_state(&mx, &my, &btn);
        g_mouse_x = mx;
        g_mouse_y = my;
        g_mouse_btn = btn;

        // Process mouse events if state changed
        if (mx != last_mx || my != last_my || btn != last_btn) {
            int m_dirty = wm_process_mouse(mx, my, btn);
            last_mx = mx;
            last_my = my;
            g_prev_btn = btn;
            last_btn = btn;
            if (m_dirty > dirty) dirty = m_dirty;
        }

        // 2. Poll hardware UART RX for typed keystrokes (drain all pending characters)
        int c;
        while ((c = uart_getc()) >= 0) {
            wm_process_key(c);
            if (dirty < 1) dirty = 1;
        }

        // 3. Render desktop compositor
        if (dirty == 2) {
            wm_render_all();
            dirty = 0;
        } else if (dirty == 1) {
            window_t *focused = wm_get_focused();
            if (focused) {
                wm_render_window_client(focused);
            }
            dirty = 0;
        } else if ((g_ticks & 0x7FFFF) == 0) {
            // Only update top taskbar (clock / LED) periodically, NEVER the full desktop!
            wm_render_taskbar();
        }
    }
}
