#ifndef GUI_APPS_H
#define GUI_APPS_H

#include "gui_wm.h"

void app_terminal_init(window_t *win);
void app_terminal_invalidate(window_t *win);
void app_pim_init(window_t *win);
void app_paint_init(window_t *win);
void app_sysinfo_init(window_t *win);

#endif
