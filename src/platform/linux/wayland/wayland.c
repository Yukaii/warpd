/*
 * keyd - A key remapping daemon.
 *
 * © 2019 Raheman Vaiya (see also: LICENSE).
 */
#include <limits.h>
#include "wayland.h"

#define UNIMPLEMENTED { \
	fprintf(stderr, "FATAL: wayland: %s unimplemented\n", __func__); \
	exit(-1);							 \
}

static uint8_t btn_state[3] = {0};

static struct {
	const char *name;
	const char *xname;
} normalization_map[] = {
	{"esc", "Escape"},
	{",", "comma"},
	{".", "period"},
	{"-", "minus"},
	{"/", "slash"},
	{";", "semicolon"},
	{"$", "dollar"},
	{"backspace", "BackSpace"},
};

struct ptr ptr = {0};

/* Input */

uint8_t way_input_lookup_code(const char *name, int *shifted)
{
	size_t i;

	for (i = 0; i < sizeof normalization_map / sizeof normalization_map[0]; i++)
		if (!strcmp(normalization_map[i].name, name))
			name = normalization_map[i].xname;

	for (i = 0; i < 256; i++)
		if (!strcmp(keymap[i].name, name)) {
			*shifted = 0;
			return i;
		} else if (!strcmp(keymap[i].shifted_name, name)) {
			*shifted = 1;
			return i;
		}

	return 0;
}

const char *way_input_lookup_name(uint8_t code, int shifted)
{
	size_t i;
	const char *name = NULL;

	if (shifted && keymap[code].shifted_name[0])
		name = keymap[code].shifted_name;
	else if (!shifted && keymap[code].name[0])
		name = keymap[code].name;

	for (i = 0; i < sizeof normalization_map / sizeof normalization_map[0]; i++)
		if (name && !strcmp(normalization_map[i].xname, name))
			name = normalization_map[i].name;

	return name;
}

/*
 * Returns the QWERTY character for a keycode, independent of current layout.
 * This is used by hint mode to match keypresses regardless of keyboard layout.
 * Linux uses evdev keycodes which are hardware-based.
 */
char way_input_code_to_qwerty(uint8_t code)
{
	/* Map from evdev keycode to QWERTY character */
	static const char qwerty_map[256] = {
		[2]  = '1', [3]  = '2', [4]  = '3', [5]  = '4', [6]  = '5',
		[7]  = '6', [8]  = '7', [9]  = '8', [10] = '9', [11] = '0',
		[12] = '-', [13] = '=',
		[16] = 'q', [17] = 'w', [18] = 'e', [19] = 'r', [20] = 't',
		[21] = 'y', [22] = 'u', [23] = 'i', [24] = 'o', [25] = 'p',
		[26] = '[', [27] = ']',
		[30] = 'a', [31] = 's', [32] = 'd', [33] = 'f', [34] = 'g',
		[35] = 'h', [36] = 'j', [37] = 'k', [38] = 'l', [39] = ';',
		[40] = '\'', [41] = '`', [43] = '\\',
		[44] = 'z', [45] = 'x', [46] = 'c', [47] = 'v', [48] = 'b',
		[49] = 'n', [50] = 'm', [51] = ',', [52] = '.', [53] = '/',
		[57] = ' ',
	};

	return qwerty_map[code];
}

/*
 * Returns the keycode for a QWERTY character, independent of current layout.
 * This is the reverse of way_input_code_to_qwerty.
 */
uint8_t way_input_qwerty_to_code(char c)
{
	/* Map from QWERTY character to evdev keycode */
	static const uint8_t reverse_qwerty_map[128] = {
		['1'] = 2,  ['2'] = 3,  ['3'] = 4,  ['4'] = 5,  ['5'] = 6,
		['6'] = 7,  ['7'] = 8,  ['8'] = 9,  ['9'] = 10, ['0'] = 11,
		['-'] = 12, ['='] = 13,
		['q'] = 16, ['w'] = 17, ['e'] = 18, ['r'] = 19, ['t'] = 20,
		['y'] = 21, ['u'] = 22, ['i'] = 23, ['o'] = 24, ['p'] = 25,
		['['] = 26, [']'] = 27,
		['a'] = 30, ['s'] = 31, ['d'] = 32, ['f'] = 33, ['g'] = 34,
		['h'] = 35, ['j'] = 36, ['k'] = 37, ['l'] = 38, [';'] = 39,
		['\''] = 40, ['`'] = 41, ['\\'] = 43,
		['z'] = 44, ['x'] = 45, ['c'] = 46, ['v'] = 47, ['b'] = 48,
		['n'] = 49, ['m'] = 50, [','] = 51, ['.'] = 52, ['/'] = 53,
		[' '] = 57,
	};

	if (c < 0 || c > 127)
		return 0;

	return reverse_qwerty_map[(int)c];
}

/*
 * Returns the keycode for special keys, independent of current layout.
 * These are evdev keycodes which are hardware-based.
 */
uint8_t way_input_special_to_code(const char *name)
{
	/* evdev keycodes for special keys */
	if (!strcmp(name, "esc")) return 1;
	if (!strcmp(name, "backspace")) return 14;
	if (!strcmp(name, "space")) return 57;
	if (!strcmp(name, "enter") || !strcmp(name, "return")) return 28;
	if (!strcmp(name, "tab")) return 15;
	if (!strcmp(name, "delete")) return 111;
	if (!strcmp(name, "leftarrow") || !strcmp(name, "left")) return 105;
	if (!strcmp(name, "rightarrow") || !strcmp(name, "right")) return 106;
	if (!strcmp(name, "uparrow") || !strcmp(name, "up")) return 103;
	if (!strcmp(name, "downarrow") || !strcmp(name, "down")) return 108;

	return 0;
}

void way_mouse_move(struct screen *scr, int x, int y)
{
	size_t i;
	int maxx = INT_MIN;
	int maxy = INT_MIN;
	int minx = INT_MAX;
	int miny = INT_MAX;

	ptr.x = x;
	ptr.y = y;
	ptr.scr = scr;

	for (i = 0; i < nr_screens; i++) {
		int x = screens[i].x + screens[i].w;
		int y = screens[i].y + screens[i].h;

		if (screens[i].y < miny)
			miny = screens[i].y;
		if (screens[i].x < minx)
			minx = screens[i].x;

		if (y > maxy)
			maxy = y;
		if (x > maxx)
			maxx = x;
	}

	/*
	 * Virtual pointer space always beings at 0,0, while global compositor
	 * space may have a negative real origin :/.
	 */
	zwlr_virtual_pointer_v1_motion_absolute(wl.ptr, 0,
						wl_fixed_from_int(x+scr->x-minx),
						wl_fixed_from_int(y+scr->y-miny),
						wl_fixed_from_int(maxx-minx),
						wl_fixed_from_int(maxy-miny));
	zwlr_virtual_pointer_v1_frame(wl.ptr);

	wl_display_flush(wl.dpy);
}

#define normalize_btn(btn) \
	switch (btn) { \
		case 1: btn = 272;break; \
		case 2: btn = 274;break; \
		case 3: btn = 273;break; \
	}

void way_mouse_down(int btn)
{
	assert(btn < (int)(sizeof btn_state / sizeof btn_state[0]));
	btn_state[btn-1] = 1;
	normalize_btn(btn);
	zwlr_virtual_pointer_v1_button(wl.ptr, 0, btn, 1);
}

void way_mouse_up(int btn)
{
	assert(btn < (int)(sizeof btn_state / sizeof btn_state[0]));
	btn_state[btn-1] = 0;
	normalize_btn(btn);
	zwlr_virtual_pointer_v1_button(wl.ptr, 0, btn, 0);
}

void way_mouse_click(int btn)
{
	normalize_btn(btn);

	zwlr_virtual_pointer_v1_button(wl.ptr, 0, btn, 1);
	zwlr_virtual_pointer_v1_button(wl.ptr, 0, btn, 0);
	zwlr_virtual_pointer_v1_frame(wl.ptr);

	wl_display_flush(wl.dpy);
}

void way_mouse_get_position(struct screen **scr, int *x, int *y)
{
	if (scr)
		*scr = ptr.scr;
	if (x)
		*x = ptr.x;
	if (y)
		*y = ptr.y;
}

void way_mouse_show()
{
}

void way_mouse_hide()
{
	fprintf(stderr, "wayland: mouse hiding not implemented\n");
}

void way_scroll(int direction)
{
	//TODO: add horizontal scroll
	direction = direction == SCROLL_DOWN ? 1 : -1;

	zwlr_virtual_pointer_v1_axis_discrete(wl.ptr, 0, 0,
					      wl_fixed_from_int(15*direction),
					      direction);

	zwlr_virtual_pointer_v1_frame(wl.ptr);

	wl_display_flush(wl.dpy);
}

void way_scroll_amount(int direction, int amount)
{
	//TODO: add horizontal scroll
	direction = direction == SCROLL_DOWN ? 1 : -1;

	zwlr_virtual_pointer_v1_axis_discrete(wl.ptr, 0, 0,
					      wl_fixed_from_int(15*direction*amount),
					      direction*amount);

	zwlr_virtual_pointer_v1_frame(wl.ptr);

	wl_display_flush(wl.dpy);
}

void way_copy_selection() { UNIMPLEMENTED }
struct input_event *way_input_wait(struct input_event *events, size_t sz) { UNIMPLEMENTED }

void way_screen_list(struct screen *scr[MAX_SCREENS], size_t *n)
{
	size_t i;
	for (i = 0; i < nr_screens; i++)
		scr[i] = &screens[i];

	*n = nr_screens;
}

void way_monitor_file(const char *path) { UNIMPLEMENTED }

void way_commit()
{
}

static void cleanup()
{
	if (btn_state[0])
		zwlr_virtual_pointer_v1_button(wl.ptr, 0, 272, 0);
	if (btn_state[1])
		zwlr_virtual_pointer_v1_button(wl.ptr, 0, 274, 0);
	if (btn_state[2])
		zwlr_virtual_pointer_v1_button(wl.ptr, 0, 273, 0);
	wl_display_flush(wl.dpy);
}

void wayland_init(struct platform *platform)
{
	way_init();

	platform->monitor_file = way_monitor_file;

	atexit(cleanup);

	platform->commit = way_commit;
	platform->copy_selection = way_copy_selection;
	platform->hint_draw = way_hint_draw;
	platform->init_hint = way_init_hint;
	platform->input_grab_keyboard = way_input_grab_keyboard;
	platform->input_lookup_code = way_input_lookup_code;
	platform->input_lookup_name = way_input_lookup_name;
	platform->input_code_to_qwerty = way_input_code_to_qwerty;
	platform->input_qwerty_to_code = way_input_qwerty_to_code;
	platform->input_special_to_code = way_input_special_to_code;
	platform->input_next_event = way_input_next_event;
	platform->input_ungrab_keyboard = way_input_ungrab_keyboard;
	platform->input_wait = way_input_wait;
	platform->mouse_click = way_mouse_click;
	platform->mouse_down = way_mouse_down;
	platform->mouse_get_position = way_mouse_get_position;
	platform->mouse_hide = way_mouse_hide;
	platform->mouse_move = way_mouse_move;
	platform->mouse_show = way_mouse_show;
	platform->mouse_up = way_mouse_up;
	platform->screen_clear = way_screen_clear;
	platform->screen_draw_box = way_screen_draw_box;
	platform->screen_get_dimensions = way_screen_get_dimensions;
	platform->screen_list = way_screen_list;
	platform->scroll = way_scroll;
	platform->scroll_amount = way_scroll_amount;
}
