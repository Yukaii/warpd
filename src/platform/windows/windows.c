
#define UNICODE 1
#include "windows.h"

static int keyboard_grabbed = 0;
static uint8_t active_mods = 0;

static struct input_event *grab_events;
static size_t ngrab_events;

static int is_grabbed_key(uint8_t code, uint8_t mods)
{
	size_t i;
	for (i = 0; i < ngrab_events; i++)
		if (grab_events[i].code == code && grab_events[i].mods == mods)
			return 1;

	return 0;
}

static const char *input_lookup_name(uint8_t code, int shifted);

static LRESULT CALLBACK keyboardHook(int nCode, WPARAM wParam, LPARAM lParam)
{
	KBDLLHOOKSTRUCT *ev = (KBDLLHOOKSTRUCT *)lParam;

	uint8_t code = ev->vkCode;
	uint8_t mods = 0;
	uint8_t pressed = 0;

	if (ev->flags & LLKHF_INJECTED)
		goto passthrough;

	// https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/ms644985(v=vs.85)
	switch (wParam) {
	case WM_KEYDOWN:
	case WM_SYSKEYDOWN:
		pressed = 1;
		break;
	case WM_KEYUP:
	case WM_SYSKEYUP:
		pressed = 0;
		break;
	default:
		goto passthrough;
	}

	mods =
	    (((GetKeyState(VK_SHIFT) & 0x8000) ? PLATFORM_MOD_SHIFT : 0) |
	     ((GetKeyState(VK_CONTROL) & 0x8000) ? PLATFORM_MOD_CONTROL : 0) |
	     ((GetKeyState(VK_MENU) & 0x8000) ? PLATFORM_MOD_ALT : 0) |
	     ((GetKeyState(VK_LWIN) & 0x8000 || GetKeyState(VK_RWIN) & 0x8000)
		  ? PLATFORM_MOD_META
		  : 0));

	active_mods = mods;
	PostMessage(NULL, WM_KEY_EVENT, pressed << 16 | mods << 8 | code, 0);

	if (is_grabbed_key(code, mods))
		return 1;

	if (keyboard_grabbed)
		return 1; // return non zero to consume the input

passthrough:
	return CallNextHookEx(NULL, nCode, wParam, lParam);
}

static COLORREF str_to_colorref(const char *s)
{

#define HEXVAL(c)                                                              \
	((c >= '0' && c <= '9')	  ? (c - '0')                                  \
	 : (c >= 'a' && c <= 'f') ? (c - 'a' + 10)                             \
				  : (c - 'A' + 10))

	if (s[0] == '#')
		s++;

	if (strlen(s) == 6 || strlen(s) == 8)
		return HEXVAL(s[5]) << 16 | HEXVAL(s[4]) << 20 |
		       HEXVAL(s[3]) << 8 | HEXVAL(s[2]) << 12 |
		       HEXVAL(s[1]) << 0 | HEXVAL(s[0]) << 4;

	return 0;
}

static void utf8_encode(const wchar_t *wstr, char *buf, size_t buf_sz)
{
	int nw =
	    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, buf, buf_sz, NULL, NULL);
	buf[nw] = 0;
}

/* Platform Implementation.  */

static void screen_clear(screen_t scr) { wn_screen_clear(scr); }

static void screen_draw_box(screen_t scr, int x, int y, int w, int h,
			    const char *color)
{
	wn_screen_add_box(scr, x, y, w, h, str_to_colorref(color));
}

static struct input_event *input_next_event(int timeout)
{
	MSG msg;
	static struct input_event ev;

	UINT_PTR timer = SetTimer(0, 0, timeout, 0);

	while (1) {
		GetMessage(&msg, 0, 0, 0);
		TranslateMessage(&msg);
		DispatchMessage(&msg);

		switch (msg.message) {
		case WM_KEY_EVENT:
			ev.code = msg.wParam & 0xFF;
			ev.mods = (msg.wParam >> 8) & 0xFF;
			ev.pressed = (msg.wParam >> 16) & 0xFF;

			KillTimer(0, timer);
			return &ev;
		case WM_TIMER:
			KillTimer(0, timer);
			if (timeout)
				return NULL;
			break;
		case WM_FILE_UPDATED:
			return NULL;
			break;
		}
	}
}

static void init_hint(const char *bg, const char *fg, int border_radius,
		      const char *border_color, int border_width,
		      const char *font_family)
{
	// TODO: handle font family and border radius.
	wn_screen_set_hintinfo(str_to_colorref(bg), str_to_colorref(fg),
			       str_to_colorref(border_color), border_width);
}

//====================================================================================

void screen_list(screen_t scr[MAX_SCREENS], size_t *n)
{
	printf("screen_list UNIMPLEMENTED\n");
}
//====================================================================================

void mouse_show() { SystemParametersInfo(SPI_SETCURSORS, 0, NULL, 0); }

void mouse_hide()
{
	static HANDLE hCursor = 0;
	static HANDLE cursor = 0;
	if (!hCursor) {
		uint8_t andmask[32 * 4];
		uint8_t xormask[32 * 4];

		memset(andmask, 0xFF, sizeof andmask);
		memset(xormask, 0x00, sizeof xormask);

		cursor = CreateCursor(GetModuleHandle(NULL), 0, 0, 32, 32,
				      andmask, xormask);
		assert(cursor);
	}

	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32512);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32513);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32514);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32515);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32516);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32640);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32641);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32642);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32643);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32644);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32645);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32646);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32648);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32649);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32650);
	hCursor = CopyImage(cursor, IMAGE_CURSOR, 0, 0, 0);
	SetSystemCursor(hCursor, 32651);
}

static void print_last_error()
{
	char *buf = NULL;

	FormatMessageA(
	    FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
		FORMAT_MESSAGE_IGNORE_INSERTS,
	    NULL, GetLastError(), MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
	    (LPSTR)&buf, 0, NULL);

	printf("ERROR: %s\n", buf);
}

static struct input_event *input_wait(struct input_event *events, size_t n)
{
	grab_events = events;
	ngrab_events = n;

	while (1) {
		size_t i;
		struct input_event *ev = input_next_event(0);

		if (!ev)
			return ev;

		for (i = 0; i < n; i++)
			if (ev->pressed && events[i].code == ev->code &&
			    events[i].mods == ev->mods) {
				grab_events = NULL;
				ngrab_events = 0;

				return ev;
			}
	}
}

static void scroll(int direction)
{
	DWORD delta = -(DWORD)((float)WHEEL_DELTA / 2.5);
	if (direction == SCROLL_UP)
		delta *= -1;
	if (active_mods & PLATFORM_MOD_SHIFT)
		keybd_event(VK_SHIFT, 0, 0, 0);
	if (active_mods & PLATFORM_MOD_CONTROL)
		keybd_event(VK_CONTROL, 0, 0, 0);
	if (active_mods & PLATFORM_MOD_META)
		keybd_event(VK_LWIN, 0, 0, 0);
	if (active_mods & PLATFORM_MOD_ALT)
		keybd_event(VK_MENU, 0, 0, 0);

	mouse_event(MOUSEEVENTF_WHEEL, 0, 0, delta, 0);

	if (active_mods & PLATFORM_MOD_SHIFT)
		keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, 0);
	if (active_mods & PLATFORM_MOD_CONTROL)
		keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0);
	if (active_mods & PLATFORM_MOD_META)
		keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, 0);
	if (active_mods & PLATFORM_MOD_ALT)
		keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);
}

static const char *input_lookup_name(uint8_t code, int shifted)
{
	static char *keymap[256];
	static char *shifted_keymap[256];
	static int init = 0;

	// FIXME: account for keymap changes.
	if (!init) {
		wchar_t buf[64];
		uint8_t state[256] = {0};
		int code;
		int ret;

		for (code = 0; code < 256; code++) {
			char *name = malloc(64);
			char *shifted_name = malloc(64);

			state[VK_SHIFT] = 0;
			ret = ToUnicode(code, 0, state, buf,
					sizeof buf / sizeof buf[0], 0);
			utf8_encode(buf, name, 64);
			if (!ret)
				strcpy(name, "UNKNOWN");

			state[VK_SHIFT] = 0xff;
			ret = ToUnicode(code, 0, state, buf,
					sizeof buf / sizeof buf[0], 0);
			utf8_encode(buf, shifted_name, 64);
			if (!ret)
				strcpy(shifted_name, "UNKNOWN");

			switch (name[0]) {
			case '\033':
				strcpy(name, "esc");
				break;
			case '\x08':
				strcpy(name, "backspace");
				break;
			case '\x0d':
				strcpy(name, "enter");
				break;
			case '\x20':
				strcpy(name, "space");
				break;
			}

			keymap[code] = name;
			shifted_keymap[code] = shifted_name;
		}

		// Fix up conflicting codes
		strcpy(keymap[0x6E],
		       "decimal"); // Avoid conflict with "." (0xBE)
		strcpy(shifted_keymap[0x6E],
		       "decimal"); // Avoid conflict with "." (0xBE)

		init++;
	}

	if (shifted)
		return shifted_keymap[code];
	else
		return keymap[code];
}

/*
 * Returns the QWERTY character for a keycode, independent of current layout.
 * This is used by hint mode to match keypresses regardless of keyboard layout.
 * Windows uses virtual key codes where letters A-Z are 0x41-0x5A.
 */
static char input_code_to_qwerty(uint8_t code)
{
	/* Letters: A-Z are VK codes 0x41-0x5A */
	if (code >= 'A' && code <= 'Z')
		return code - 'A' + 'a';

	/* Numbers: 0-9 are VK codes 0x30-0x39 */
	if (code >= '0' && code <= '9')
		return code;

	/* Space: VK_SPACE is 0x20 */
	if (code == 0x20)
		return ' ';

	/* OEM keys (QWERTY specific positions) */
	switch (code) {
	case 0xBA:
		return ';'; /* VK_OEM_1 */
	case 0xBB:
		return '='; /* VK_OEM_PLUS */
	case 0xBC:
		return ','; /* VK_OEM_COMMA */
	case 0xBD:
		return '-'; /* VK_OEM_MINUS */
	case 0xBE:
		return '.'; /* VK_OEM_PERIOD */
	case 0xBF:
		return '/'; /* VK_OEM_2 */
	case 0xC0:
		return '`'; /* VK_OEM_3 */
	case 0xDB:
		return '['; /* VK_OEM_4 */
	case 0xDC:
		return '\\'; /* VK_OEM_5 */
	case 0xDD:
		return ']'; /* VK_OEM_6 */
	case 0xDE:
		return '\''; /* VK_OEM_7 */
	}

	return 0;
}

/*
 * Returns the keycode for a QWERTY character, independent of current layout.
 * This is the reverse of input_code_to_qwerty.
 */
static uint8_t input_qwerty_to_code(char c)
{
	/* Letters: a-z map to VK codes 0x41-0x5A (uppercase) */
	if (c >= 'a' && c <= 'z')
		return c - 'a' + 'A';

	/* Numbers: 0-9 are VK codes 0x30-0x39 */
	if (c >= '0' && c <= '9')
		return c;

	/* Space: VK_SPACE is 0x20 */
	if (c == ' ')
		return 0x20;

	/* OEM keys (QWERTY specific positions) */
	switch (c) {
	case ';':
		return 0xBA; /* VK_OEM_1 */
	case '=':
		return 0xBB; /* VK_OEM_PLUS */
	case ',':
		return 0xBC; /* VK_OEM_COMMA */
	case '-':
		return 0xBD; /* VK_OEM_MINUS */
	case '.':
		return 0xBE; /* VK_OEM_PERIOD */
	case '/':
		return 0xBF; /* VK_OEM_2 */
	case '`':
		return 0xC0; /* VK_OEM_3 */
	case '[':
		return 0xDB; /* VK_OEM_4 */
	case '\\':
		return 0xDC; /* VK_OEM_5 */
	case ']':
		return 0xDD; /* VK_OEM_6 */
	case '\'':
		return 0xDE; /* VK_OEM_7 */
	}

	return 0;
}

/*
 * Returns the keycode for special keys, independent of current layout.
 */
static uint8_t input_special_to_code(const char *name)
{
	/* Windows virtual key codes for special keys */
	if (!strcmp(name, "esc"))
		return 0x1B; /* VK_ESCAPE */
	if (!strcmp(name, "backspace"))
		return 0x08; /* VK_BACK */
	if (!strcmp(name, "space"))
		return 0x20; /* VK_SPACE */
	if (!strcmp(name, "enter") || !strcmp(name, "return"))
		return 0x0D; /* VK_RETURN */
	if (!strcmp(name, "tab"))
		return 0x09; /* VK_TAB */
	if (!strcmp(name, "delete"))
		return 0x2E; /* VK_DELETE */
	if (!strcmp(name, "leftarrow") || !strcmp(name, "left"))
		return 0x25; /* VK_LEFT */
	if (!strcmp(name, "rightarrow") || !strcmp(name, "right"))
		return 0x27; /* VK_RIGHT */
	if (!strcmp(name, "uparrow") || !strcmp(name, "up"))
		return 0x26; /* VK_UP */
	if (!strcmp(name, "downarrow") || !strcmp(name, "down"))
		return 0x28; /* VK_DOWN */

	return 0;
}

static void send_key(uint8_t code, int pressed)
{
	INPUT input;

	input.type = INPUT_KEYBOARD;
	input.ki.wVk = code;
	input.ki.dwFlags = pressed ? 0 : KEYEVENTF_KEYUP;

	SendInput(1, &input, sizeof(INPUT));
}

static void copy_selection()
{
	send_key(VK_CONTROL, 1);
	send_key('C', 1);
	send_key('C', 0);
	send_key(VK_CONTROL, 0);
}

static uint8_t input_lookup_code(const char *name, int *shifted)
{
	// TODO: fixme (eliminate input_lookup_code in platform.h and move
	// reverse lookups into the calling code)

	for (int i = 0; i < 256; i++) {
		if (!strcmp(input_lookup_name(i, 0), name)) {
			*shifted = 0;
			return i;
		} else if (!strcmp(input_lookup_name(i, 1), name)) {
			*shifted = 1;
			return i;
		}
	}

	return 0;
}

static void mouse_get_position(screen_t *_scr, int *x, int *y)
{
	int sx, sy;

	POINT p;
	GetCursorPos(&p);

	struct screen *scr = wn_get_screen_at(p.x, p.y);
	assert(scr);

	wn_screen_get_dimensions(scr, &sx, &sy, NULL, NULL);

	if (_scr)
		*_scr = scr;
	if (x)
		*x = p.x - sx;
	if (y)
		*y = p.y - sy;
}

static void screen_get_dimensions(screen_t scr, int *w, int *h)
{
	wn_screen_get_dimensions(scr, NULL, NULL, w, h);
}

static void mouse_move(screen_t scr, int x, int y)
{
	int sx, sy;

	wn_screen_get_dimensions(scr, &sx, &sy, NULL, NULL);
	SetCursorPos(sx + x, sy + y);
}

static void input_grab_keyboard()
{
	int i;
	for (i = 0; i < 256; i++)
		if (GetKeyState(i))
			send_key(i, 0);

	keyboard_grabbed = 1;
}

static void input_ungrab_keyboard() { keyboard_grabbed = 0; }

void hint_draw(screen_t scr, struct hint *hints, size_t nhints)
{
	wn_screen_set_hints(scr, hints, nhints);
}

static void get_button_flags(int btn, DWORD *_up, DWORD *_down)
{
	DWORD up = MOUSEEVENTF_LEFTUP;
	DWORD down = MOUSEEVENTF_LEFTDOWN;
	switch (btn) {
	case 1:
		up = MOUSEEVENTF_LEFTUP;
		down = MOUSEEVENTF_LEFTDOWN;
		break;
	case 2:
		up = MOUSEEVENTF_MIDDLEUP;
		down = MOUSEEVENTF_MIDDLEDOWN;
		break;
	case 3:
		up = MOUSEEVENTF_RIGHTUP;
		down = MOUSEEVENTF_RIGHTDOWN;
		break;
	}

	if (_down)
		*_down = down;
	if (_up)
		*_up = up;
}

static void mouse_click(int btn)
{
	INPUT inputs[2] = {0};
	DWORD up, down;

	get_button_flags(btn, &up, &down);

	inputs[0].type = INPUT_MOUSE;
	inputs[0].mi.dwFlags = down;

	inputs[1].type = INPUT_MOUSE;
	inputs[1].mi.dwFlags = up;

	SendInput(2, inputs, sizeof(INPUT));
}

static void mouse_down(int btn)
{
	INPUT input = {0};

	input.type = INPUT_MOUSE;
	get_button_flags(btn, NULL, &input.mi.dwFlags);

	SendInput(1, &input, sizeof(INPUT));
}

static void mouse_up(int btn)
{
	INPUT input = {0};

	input.type = INPUT_MOUSE;
	get_button_flags(btn, &input.mi.dwFlags, NULL);

	SendInput(1, &input, sizeof(INPUT));
}

static void commit()
{
	screen_t scr;
	mouse_get_position(&scr, NULL, NULL);
	wn_screen_redraw(scr);
}

void platform_run(int (*main)(struct platform *platform))
{
	SetWindowsHookEx(WH_KEYBOARD_LL, keyboardHook, GetModuleHandle(NULL),
			 0);
	wn_init_screen();

	static struct platform platform;

	platform.init_hint = init_hint;
	platform.hint_draw = hint_draw;
	platform.collect_interactable_hints = NULL;
	platform.screen_draw_box = screen_draw_box;
	platform.screen_draw_cursor = NULL;
	platform.input_next_event = input_next_event;
	platform.input_wait = input_wait;
	platform.screen_clear = screen_clear;
	platform.screen_clear_ripples = NULL;

	platform.screen_get_dimensions = screen_get_dimensions;
	platform.screen_list = screen_list;
	platform.scroll = scroll;
	platform.mouse_click = mouse_click;
	platform.mouse_down = mouse_down;
	platform.mouse_get_position = mouse_get_position;
	platform.mouse_hide = mouse_hide;
	platform.mouse_move = mouse_move;
	platform.mouse_show = mouse_show;
	platform.mouse_up = mouse_up;
	platform.input_ungrab_keyboard = input_ungrab_keyboard;
	platform.commit = commit;
	platform.copy_selection = copy_selection;
	platform.input_grab_keyboard = input_grab_keyboard;
	platform.input_lookup_code = input_lookup_code;
	platform.input_lookup_name = input_lookup_name;
	platform.input_code_to_qwerty = input_code_to_qwerty;
	platform.input_qwerty_to_code = input_qwerty_to_code;
	platform.input_special_to_code = input_special_to_code;
	platform.monitor_file = wn_monitor_file;

	exit(main(&platform));
}
