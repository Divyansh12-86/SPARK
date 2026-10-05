#ifndef GUI_WM_H
#define GUI_WM_H

#include "types.h"

#define MAX_WINDOWS 6

// Window flags
#define WIN_FLAG_VISIBLE   (1 << 0)
#define WIN_FLAG_FOCUSED   (1 << 1)
#define WIN_FLAG_MINIMIZED (1 << 2)

// App types
#define APP_TYPE_TERMINAL  1
#define APP_TYPE_PIM       2
#define APP_TYPE_PAINT     3
#define APP_TYPE_SYSINFO   4

struct window;

typedef void (*win_draw_fn)(struct window *win);
typedef void (*win_click_fn)(struct window *win, int lx, int ly, int btn);
typedef void (*win_key_fn)(struct window *win, int key);

typedef struct window {
    int id;
    char title[32];
    int x, y, w, h;
    int flags;
    int app_type;

    win_draw_fn  on_draw;
    win_click_fn on_click;
    win_key_fn   on_key;
    void        *app_data;
} window_t;

// Window Manager API
void      wm_init(void);
window_t* wm_create_window(const char *title, int x, int y, int w, int h, int app_type);
void      wm_destroy_window(int id);
void      wm_focus_window(int id);
window_t* wm_get_focused(void);

void      wm_render_all(void);
void      wm_render_desktop_bg(void);
void      wm_render_taskbar(void);
void      wm_render_icons(void);
void      wm_render_single_window(window_t *win);
void      wm_render_window_title(window_t *win);
void      wm_render_window_client(window_t *win);
void      wm_close_window_repair(int id);
void      wm_open_menu(void);
void      wm_close_menu(void);

int       wm_process_mouse(int mx, int my, int btn);
void      wm_process_key(int key);
void      wm_run_desktop(void);

// Hardware Mouse MMIO
void      mouse_get_state(int *out_x, int *out_y, int *out_btn);

#endif
