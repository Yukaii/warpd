#ifndef _WINDOWS_H
#define _WINDOWS_H
#include "../../platform.h"
#include <assert.h>
#include <stdio.h>
#include <windows.h>

#define WM_CONFIG_UPDATE WM_USER
#define WM_KEY_EVENT	 (WM_USER + 1)
#define WM_FILE_UPDATED	 (WM_USER + 2)

struct screen;

void wn_init_screen();

void wn_screen_redraw(struct screen *scr);
void wn_screen_add_box(struct screen *scr, int x, int y, int w, int h,
		       COLORREF color);
void wn_screen_clear(struct screen *scr);

struct screen *wn_get_screen_at(int x, int y);
void wn_screen_get_dimensions(struct screen *scr, int *xoff, int *yoff, int *w,
			      int *h);
void wn_screen_set_hints(struct screen *scr, struct hint *hints, size_t nhints);
void wn_screen_set_hintinfo(COLORREF _hint_bgcol, COLORREF _hint_fgcol,
			    COLORREF _hint_border_col, int _hint_border_width);
void wn_monitor_file(const char *path);

#endif
