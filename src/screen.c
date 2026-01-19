#include "warpd.h"

static screen_t active_screen = NULL;

void screen_set_active(screen_t scr) { active_screen = scr; }

screen_t screen_get_active(void) { return active_screen; }

void screen_clear_active(void) { active_screen = NULL; }

void screen_get_cursor(screen_t *scr, int *x, int *y, int warp_to_active)
{
	screen_t active = screen_get_active();
	screen_t current = NULL;
	int cx = 0;
	int cy = 0;

	platform->mouse_get_position(&current, &cx, &cy);

	if (active) {
		if (current != active && warp_to_active) {
			int w, h;
			platform->screen_get_dimensions(active, &w, &h);
			cx = w / 2;
			cy = h / 2;
			platform->mouse_move(active, cx, cy);
			current = active;
		}
		if (!warp_to_active)
			current = active;
	}

	if (scr)
		*scr = current;
	if (x)
		*x = cx;
	if (y)
		*y = cy;
}

void screen_selection_mode()
{
	size_t i;
	size_t n;
	screen_t screens[MAX_SCREENS];
	struct input_event *ev;
	const char *screen_chars = config_get("screen_chars");

	platform->screen_list(screens, &n);
	assert(strlen(screen_chars) >= n);

	for (i = 0; i < n; i++) {
		struct hint hint;
		int w, h;
		platform->screen_get_dimensions(screens[i], &w, &h);

		hint.x = w / 2 - 25;
		hint.y = h / 2 - 25;
		hint.w = 50;
		hint.h = 50;

		hint.label[0] = screen_chars[i];
		hint.label[1] = 0;

		platform->hint_draw(screens[i], &hint, 1);
	}

	platform->commit();

	platform->input_grab_keyboard();
	while (1) {
		ev = platform->input_next_event(0);
		if (ev->pressed)
			break;
	}
	platform->input_ungrab_keyboard();

	for (i = 0; i < n; i++) {
		const char *key = input_event_tostr(ev);

		if (key[0] == screen_chars[i] && key[1] == 0) {
			int w, h;
			platform->screen_get_dimensions(screens[i], &w, &h);
			platform->mouse_move(screens[i], w / 2, h / 2);
			screen_set_active(screens[i]);
		}
	}

	for (i = 0; i < n; i++)
		platform->screen_clear(screens[i]);

	platform->commit();
}
