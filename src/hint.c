/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "warpd.h"

struct hint *hints;
struct hint matched[MAX_HINTS];

static size_t nr_hints;
static size_t nr_matched;
static int hint_selected;

char last_selected_hint[32];

static void filter(screen_t scr, const char *s)
{
	size_t i;

	nr_matched = 0;
	for (i = 0; i < nr_hints; i++) {
		if (strstr(hints[i].label, s) == hints[i].label)
			matched[nr_matched++] = hints[i];
	}

	platform->screen_clear(scr);
	platform->hint_draw(scr, matched, nr_matched);
	platform->commit();
}

static void get_hint_size(screen_t scr, int *w, int *h)
{
	int sw, sh;

	platform->screen_get_dimensions(scr, &sw, &sh);

	if (sw < sh) {
		int tmp = sw;
		sw = sh;
		sh = tmp;
	}

	*w = (sw * config_get_int("hint_size")) / 1000;
	*h = (sh * config_get_int("hint_size")) / 1000;
}

static int hint_label_length(size_t count, size_t alphabet_len)
{
	int length = 1;
	size_t capacity = alphabet_len;

	if (alphabet_len == 0)
		return 0;

	while (capacity < count && length < (int)(sizeof(hints[0].label) - 1)) {
		length++;
		capacity *= alphabet_len;
	}

	return length;
}

static void generate_hint_labels(struct hint *out_hints, size_t count,
				 const char *alphabet)
{
	size_t alphabet_len = strlen(alphabet);
	int label_len = hint_label_length(count, alphabet_len);

	if (!label_len)
		return;

	for (size_t i = 0; i < count; i++) {
		size_t value = i;
		for (int pos = label_len - 1; pos >= 0; pos--) {
			out_hints[i].label[pos] =
			    alphabet[value % alphabet_len];
			value /= alphabet_len;
		}
		out_hints[i].label[label_len] = 0;
	}
}

static size_t generate_fullscreen_hints(screen_t scr, struct hint *hints)
{
	int sw, sh;
	int w, h;
	int i, j;
	size_t n = 0;

	const char *chars = config_get("hint_chars");
	get_hint_size(scr, &w, &h);
	platform->screen_get_dimensions(scr, &sw, &sh);

	const int nr = strlen(chars);
	const int nc = strlen(chars);

	const int colgap = sw / nc - w;
	const int rowgap = sh / nr - h;

	const int x_offset = (sw - nc * w - (nc - 1) * colgap) / 2;
	const int y_offset = (sh - nr * h - (nr - 1) * rowgap) / 2;

	int x = x_offset;
	int y = y_offset;

	get_hint_size(scr, &w, &h);

	for (i = 0; i < nc; i++) {
		for (j = 0; j < nr; j++) {
			struct hint *hint = &hints[n++];

			hint->x = x;
			hint->y = y;

			hint->w = w;
			hint->h = h;

			hint->label[0] = chars[i];
			hint->label[1] = chars[j];
			hint->label[2] = 0;

			y += rowgap + h;
		}

		y = y_offset;
		x += colgap + w;
	}

	return n;
}

static int hint_selection(screen_t scr, struct hint *_hints, size_t _nr_hints)
{
	hints = _hints;
	nr_hints = _nr_hints;
	hint_selected = 0;

	filter(scr, "");

	int rc = 0;
	char buf[32] = {0};
	platform->input_grab_keyboard();

	platform->mouse_hide();

	const char *keys[] = {
	    "hint_exit",
	    "hint_undo_all",
	    "hint_undo",
	};

	config_input_whitelist(keys, sizeof keys / sizeof keys[0]);

	while (1) {
		struct input_event *ev;
		ssize_t len;

		ev = platform->input_next_event(0);

		if (!ev->pressed)
			continue;

		len = strlen(buf);

		if (config_input_match(ev, "hint_exit")) {
			rc = -1;
			break;
		} else if (config_input_match(ev, "hint_undo_all")) {
			buf[0] = 0;
		} else if (config_input_match(ev, "hint_undo")) {
			if (len)
				buf[len - 1] = 0;
		} else {
			/*
			 * Use keycode-to-QWERTY mapping instead of
			 * layout-dependent character names. This allows hint
			 * mode to work regardless of the current keyboard
			 * layout (e.g., Hebrew, Russian).
			 */
			char c = platform->input_code_to_qwerty(ev->code);

			if (!c)
				continue;

			buf[len++] = c;
		}

		filter(scr, buf);

		if (nr_matched == 1) {
			int nx, ny;
			struct hint *h = &matched[0];

			platform->screen_clear(scr);

			nx = h->x + h->w / 2;
			ny = h->y + h->h / 2;

			/*
			 * Wiggle the cursor a single pixel to accommodate
			 * text selection widgets which don't like spontaneous
			 * cursor warping.
			 */
			platform->mouse_move(scr, nx + 1, ny + 1);

			platform->mouse_move(scr, nx, ny);
			if (platform->trigger_ripple)
				platform->trigger_ripple(scr, nx, ny);
			strcpy(last_selected_hint, buf);
			hint_selected = 1;
			break;
		} else if (nr_matched == 0) {
			break;
		}
	}

	platform->input_ungrab_keyboard();
	platform->screen_clear(scr);
	platform->mouse_show();

	platform->commit();
	return rc;
}

static int sift()
{
	int gap = config_get_int("hint2_gap_size");
	int hint_sz = config_get_int("hint2_size");

	const char *chars = config_get("hint2_chars");
	size_t chars_len = strlen(chars);

	int grid_sz = config_get_int("hint2_grid_size");

	int x, y;
	int sh, sw;

	int col;
	int row;
	size_t n = 0;
	screen_t scr;

	struct hint hints[MAX_HINTS];

	screen_get_cursor(&scr, &x, &y, 1);
	platform->screen_get_dimensions(scr, &sw, &sh);

	gap = (gap * sh) / 1000;
	hint_sz = (hint_sz * sh) / 1000;

	x -= ((hint_sz + (gap - 1)) * grid_sz) / 2;
	y -= ((hint_sz + (gap - 1)) * grid_sz) / 2;

	for (col = 0; col < grid_sz; col++)
		for (row = 0; row < grid_sz; row++) {
			size_t idx = (row * grid_sz) + col;

			if (idx < chars_len) {
				hints[n].x = x + (hint_sz + gap) * col;
				hints[n].y = y + (hint_sz + gap) * row;

				hints[n].w = hint_sz;
				hints[n].h = hint_sz;
				hints[n].label[0] = chars[idx];
				hints[n].label[1] = 0;

				n++;
			}
		}

	return hint_selection(scr, hints, n);
}

void init_hints()
{
	platform->init_hint(
	    config_get("hint_bgcolor"), config_get("hint_fgcolor"),
	    config_get_int("hint_border_radius"),
	    config_get("hint_border_color"),
	    config_get_int("hint_border_width"), config_get("hint_font"));
}

int hintspec_mode()
{
	screen_t scr;
	int sw, sh;
	int w, h;

	int n = 0;
	struct hint hints[MAX_HINTS];

	screen_get_cursor(&scr, NULL, NULL, 0);
	platform->screen_get_dimensions(scr, &sw, &sh);

	get_hint_size(scr, &w, &h);

	n = platform->collect_interactable_hints(scr, hints, MAX_HINTS);
	if (!n)
		return -1;

	for (size_t i = 0; i < n; i++) {
		int max_x = sw - w;
		int max_y = sh - h;
		int x = hints[i].x - w / 2;
		int y = hints[i].y - h / 2;

		if (max_x < 0)
			max_x = 0;
		if (max_y < 0)
			max_y = 0;

		hints[i].w = w;
		hints[i].h = h;
		hints[i].x = MIN(max_x, x < 0 ? 0 : x);
		hints[i].y = MIN(max_y, y < 0 ? 0 : y);
	}

	generate_hint_labels(hints, n, config_get("hint_chars"));

	return hint_selection(scr, hints, n);
}

int full_hint_mode(int second_pass)
{
	int mx, my;
	screen_t scr;
	struct hint hints[MAX_HINTS];

	screen_get_cursor(&scr, &mx, &my, 0);
	hist_add(mx, my);

	nr_hints = generate_fullscreen_hints(scr, hints);

	if (hint_selection(scr, hints, nr_hints))
		return -1;

	if (second_pass)
		return sift();
	else
		return 0;
}

static int find_hint_mode_once()
{
	int w, h;
	int sw, sh;
	size_t n = 0;
	screen_t scr;
	struct hint hints[MAX_HINTS];

	if (!platform->collect_interactable_hints)
		return -1;

	screen_t prev_screen = screen_get_active();
	screen_clear_active();
	screen_get_cursor(&scr, NULL, NULL, 0);
	platform->screen_get_dimensions(scr, &sw, &sh);
	get_hint_size(scr, &w, &h);

	n = platform->collect_interactable_hints(scr, hints, MAX_HINTS);
	if (!n) {
		screen_set_active(prev_screen);
		return -1;
	}

	for (size_t i = 0; i < n; i++) {
		int max_x = sw - w;
		int max_y = sh - h;
		int x = hints[i].x - w / 2;
		int y = hints[i].y - h / 2;

		if (max_x < 0)
			max_x = 0;
		if (max_y < 0)
			max_y = 0;

		hints[i].w = w;
		hints[i].h = h;
		hints[i].x = MIN(max_x, x < 0 ? 0 : x);
		hints[i].y = MIN(max_y, y < 0 ? 0 : y);
	}

	screen_set_active(prev_screen);
	generate_hint_labels(hints, n, config_get("hint_chars"));

	return hint_selection(scr, hints, n);
}

int find_hint_mode() { return find_hint_mode_once(); }

int find_hint_mode_sticky()
{
	while (1) {
		if (find_hint_mode_once() < 0)
			return -1;
		if (hint_selected) {
			screen_t scr;
			int x, y;

			screen_get_cursor(&scr, &x, &y, 1);

			hist_add(x, y);
			histfile_add(x, y);
			if (platform->trigger_ripple)
				platform->trigger_ripple(scr, x, y);
			platform->mouse_click(1);
		}
	}

	return 0;
}

int history_hint_mode()
{
	struct hint hints[MAX_HINTS];
	struct histfile_ent *ents;
	screen_t scr;
	int w, h;
	int sw, sh;
	size_t n, i;

	screen_get_cursor(&scr, NULL, NULL, 0);
	platform->screen_get_dimensions(scr, &sw, &sh);

	n = histfile_read(&ents);

	get_hint_size(scr, &w, &h);

	for (i = 0; i < n; i++) {
		hints[i].w = w;
		hints[i].h = h;

		hints[i].x = ents[i].x - w / 2;
		hints[i].y = ents[i].y - h / 2;

		hints[i].label[0] = 'a' + i;
		hints[i].label[1] = 0;
	}

	return hint_selection(scr, hints, n);
}
