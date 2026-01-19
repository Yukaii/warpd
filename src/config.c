#include "warpd.h"

#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct config_entry *config = NULL;

static struct {
	char *key;
	char *val;

	const char *description;
	enum option_type type;
} options[] = {
    {"hint_activation_key", "A-M-x", "Activates hint mode.", OPT_KEY},
    {"find_activation_key", "A-M-f", "Activate find mode (interactable hints).",
     OPT_KEY},
    {"hint2_activation_key", "A-M-X", "Activate two pass hint mode.", OPT_KEY},
    {"grid_activation_key", "A-M-g",
     "Activates grid mode and allows for further manipulation of the pointer "
     "using the mapped keys.",
     OPT_KEY},
    {"history_activation_key", "A-M-h", "Activate history mode.", OPT_KEY},
    {"screen_activation_key", "A-M-s", "Activate (s)creen selection mode.",
     OPT_KEY},
    {"activation_key", "A-M-c",
     "Activate normal movement mode (manual (c)ursor movement).", OPT_KEY},

    {"hint_oneshot_key", "A-M-l", "Activate hint mode and exit upon selection.",
     OPT_KEY},
    {"hint2_oneshot_key", "A-M-L",
     "Activate two pass hint mode and exit upon selection.", OPT_KEY},

    /* Normal mode keys */

    {"exit", "esc", "Exit the currently active warpd session.", OPT_KEY},
    {"drag", "v", "Toggle drag mode (mnemonic (v)isual mode).", OPT_KEY},
    {"copy_and_exit", "c",
     "Send the copy key and exit (useful in combination with v).", OPT_KEY},
    {"accelerator", "a", "Increase the acceleration of the pointer while held.",
     OPT_KEY},
    {"decelerator", "d", "Decrease the speed of the pointer while held.",
     OPT_KEY},
    {"buttons", "m , .",
     "A space separated list of mouse buttons (2 is middle click).",
     OPT_BUTTON},
    {"hold_buttons", "unbind",
     "Mouse buttons to hold while the key is pressed.", OPT_BUTTON},
    {"rapid_mode", "R", "Toggle rapid click mode (press a button to start).",
     OPT_KEY},

    {"rapid_click_interval", "40", "Milliseconds between rapid clicks.",
     OPT_INT},
    {"rapid_indicator_color", "#ff000080",
     "Rapid mode border color (RGBA hex).", OPT_STRING},
    {"rapid_indicator_width", "3", "Rapid mode border width in pixels.",
     OPT_INT},

    {"drag_button", "1", "The mouse buttton used for dragging.", OPT_INT},
    {"oneshot_buttons", "n - /", "Oneshot mouse buttons (deactivate on click).",
     OPT_BUTTON},

    {"print", "p",
     "Print the current mouse coordinates to stdout (useful for scripts).",
     OPT_KEY},
    {"history", ";", "Activate hint history mode while in normal mode.",
     OPT_KEY},
	{"hint", "x",
	 "Activate hint mode while in normal mode (mnemonic: x marks the spot?).",
	 OPT_KEY},
	{"hint2", "X", "Activate two pass hint mode.", OPT_KEY},
	{"find", "f", "Activate find mode for interactable hints.", OPT_KEY},
	{"find_sticky", "F",
	 "Activate sticky find mode for interactable hints (exit with esc).",
	 OPT_KEY},
	{"grid", "g", "Activate (g)rid mode while in normal mode.", OPT_KEY},
    {"screen", "s", "Activate (s)creen selection while in normal mode.",
     OPT_KEY},

    {"left", "h", "Move the cursor left in normal mode.", OPT_KEY},
    {"down", "j", "Move the cursor down in normal mode.", OPT_KEY},
    {"up", "k", "Move the cursor up in normal mode.", OPT_KEY},
    {"right", "l", "Move the cursor right in normal mode.", OPT_KEY},
    {"top", "H", "Moves the cursor to the top of the screen in normal mode.",
     OPT_KEY},
    {"middle", "M",
     "Moves the cursor to the middle of the screen in normal mode.", OPT_KEY},
    {"bottom", "L",
     "Moves the cursor to the bottom of the screen in normal mode.", OPT_KEY},
    {"start", "0",
     "Moves the cursor to the leftmost corner of the screen in normal mode.",
     OPT_KEY},
    {"end", "$",
     "Moves the cursor to the rightmost corner of the screen in normal mode.",
     OPT_KEY},

    {"scroll_down", "e", "Scroll down key.", OPT_KEY},
    {"scroll_up", "r", "Scroll up key.", OPT_KEY},
    {"scroll_left", "t", "Scroll left key.", OPT_KEY},
    {"scroll_right", "y", "Scroll right key.", OPT_KEY},
    {"scroll_page_down", "C-f", "Scroll down one page.", OPT_KEY},
    {"scroll_page_up", "C-b", "Scroll up one page.", OPT_KEY},
    {"scroll_home", "z", "Scroll to top of page.", OPT_KEY},
    {"scroll_end", "Z", "Scroll to bottom of page.", OPT_KEY},

    {"cursor_color", "#FF4500",
     "The color of the pointer in normal mode (rgba hex value).", OPT_STRING},

    {"cursor_size", "7", "The height of pointer in normal mode.", OPT_INT},
    {"cursor_pack", "none",
     "Cursor pack name or path for custom cursor (macOS .cursor, normal mode).",
     OPT_STRING},

    {"cursor_halo_enabled", "0",
     "Enable a subtle halo around the cursor when using non-default cursor.",
     OPT_INT},
    {"cursor_halo_color", "#ffffff20",
     "Color of the cursor halo (RGBA hex, last 2 digits = alpha).", OPT_STRING},
    {"cursor_halo_radius", "20", "Radius of the cursor halo in pixels.",
     OPT_INT},

    {"cursor_entry_effect", "0",
     "Enable a pulse effect when entering normal mode with non-default cursor.",
     OPT_INT},
    {"cursor_entry_color", "#00ff0060",
     "Color of the entry pulse effect (RGBA hex).", OPT_STRING},
    {"cursor_entry_duration", "200",
     "Duration of the entry pulse animation in milliseconds.", OPT_INT},
    {"cursor_entry_radius", "40",
     "Maximum radius of the entry pulse in pixels.", OPT_INT},

    {"repeat_interval", "20",
     "The number of milliseconds before repeating a movement event.", OPT_INT},
    {"speed", "220", "Pointer speed in pixels/second.", OPT_INT},
    {"max_speed", "1600", "The maximum pointer speed.", OPT_INT},
    {"decelerator_speed", "50", "Pointer speed while decelerator is depressed.",
     OPT_INT},
    {"acceleration", "700", "Pointer acceleration in pixels/second^2.",
     OPT_INT},
    {"accelerator_acceleration", "2900",
     "Pointer acceleration while the accelerator is depressed.", OPT_INT},
    {"oneshot_timeout", "300",
     "The length of time in milliseconds to wait for a second click after a "
     "oneshot key has been pressed.",
     OPT_INT},
    {"hist_hint_size", "2",
     "History hint size as a percentage of screen height.", OPT_INT},
    {"grid_nr", "2", "The number of rows in the grid.", OPT_INT},
    {"grid_nc", "2", "The number of columns in the grid.", OPT_INT},

    {"hist_back", "C-o", "Move to the last position in the history stack.",
     OPT_KEY},
    {"hist_forward", "C-i", "Move to the next position in the history stack.",
     OPT_KEY},

    {"grid_up", "w", "Move the grid up.", OPT_KEY},
    {"grid_left", "a", "Move the grid left.", OPT_KEY},
    {"grid_down", "s", "Move the grid down.", OPT_KEY},
    {"grid_right", "d", "Move the grid right.", OPT_KEY},
    {"grid_cut_up", "W", "Cut the grid up.", OPT_KEY},
    {"grid_cut_left", "A", "Cut the grid left.", OPT_KEY},
    {"grid_cut_down", "S", "Cut the grid down.", OPT_KEY},
    {"grid_cut_right", "D", "Cut the grid right.", OPT_KEY},
    {"grid_keys", "u i j k",
     "A sequence of comma delimited keybindings which are ordered bookwise "
     "with respect to grid position.",
     OPT_KEY},
    {"grid_exit", "c", "Exit grid mode and return to normal mode.", OPT_KEY},

    {"grid_size", "4", "The thickness of grid lines in pixels.", OPT_INT},
    {"grid_border_size", "0", "The thickness of the grid border in pixels.",
     OPT_INT},

    {"grid_color", "#1c1c1e", "The color of the grid.", OPT_STRING},
    {"grid_border_color", "#ffffff", "The color of the grid border.",
     OPT_STRING},

    {"hint_bgcolor", "#1c1c1e", "The background hint color.", OPT_STRING},
    {"hint_fgcolor", "#a1aba7", "The foreground hint color.", OPT_STRING},
    {"hint_chars", "abcdefghijklmnopqrstuvwxyz",
     "The character set from which hints are generated. The total number of "
     "hints is the square of the size of this string. It may be desirable to "
     "increase this for larger screens or trim it to increase gaps between "
     "hints.",
     OPT_STRING},
    {"hint_font", "Menlo-Regular",
     "The font name used by hints. Note: This is platform specific, in X it "
     "corresponds to a valid xft font name, on macos it corresponds to a "
     "postscript name.",
     OPT_STRING},

    {"hint_size", "20", "Hint size (range: 1-1000)", OPT_INT},
    {"hint_border_radius", "3", "Border radius.", OPT_INT},
    {"hint_border_color", "#ffffff", "Hint border color (RGBA hex).",
     OPT_STRING},
    {"hint_border_width", "0", "Hint border width in pixels.", OPT_INT},

    {"hint_exit", "esc", "The exit key used for hint mode.", OPT_KEY},
    {"hint_undo", "backspace",
     "undo last selection step in one of the hint based modes.", OPT_KEY},
    {"hint_undo_all", "C-u",
     "undo all selection steps in one of the hint based modes.", OPT_KEY},

    {"hint2_chars", "hjkl;asdfgqwertyuiopzxcvb",
     "The character set used for the second hint selection, should consist of "
     "at least hint2_grid_size^2 characters.",
     OPT_STRING},
    {"hint2_size", "20",
     "The size of hints in the secondary grid (range: 1-1000).", OPT_INT},
    {"hint2_gap_size", "1",
     "The spacing between hints in the secondary grid. (range: 1-1000)",
     OPT_INT},
    {"hint2_grid_size", "3", "The size of the secondary grid.", OPT_INT},

    {"screen_chars", "jkl;asdfg", "The characters used for screen selection.",
     OPT_STRING},

    {"scroll_speed", "300",
     "Initial scroll speed in units/second (unit varies by platform).",
     OPT_INT},
    {"scroll_max_speed", "9000", "Maximum scroll speed.", OPT_INT},
    {"scroll_acceleration", "1600", "Scroll acceleration in units/second^2.",
     OPT_INT},
    {"scroll_deceleration", "-3400", "Scroll deceleration.", OPT_INT},
    {"scroll_page_amount", "800", "Number of scroll units for page up/down.",
     OPT_INT},
    {"scroll_home_amount", "100000",
     "Number of scroll units for home/end (scroll to top/bottom).", OPT_INT},

    {"indicator", "none",
     "Specifies an optional visual indicator to be displayed while normal mode "
     "is active, must be one of: topright, topleft, bottomright, bottomleft, "
     "none",
     OPT_STRING},
    {"indicator_color", "#00ff00", "The color of the visual indicator color.",
     OPT_STRING},
    {"indicator_size", "12", "The size of the visual indicator in pixels.",
     OPT_INT},

    {"normal_system_cursor", "0",
     "If set to non-zero, use the system cursor instead of warpd's internal "
     "one.",
     OPT_INT},
    {"normal_blink_interval", "0",
     "If set to non-zero, the blink interval of the normal mode cursor in "
     "miliseconds. If two values are supplied, the first corresponds to the "
     "time the cursor is visible, and the second corresponds to the amount of "
     "time it is invisible",
     OPT_STRING},

    {"ripple_enabled", "1", "Enable visual ripple effect on clicks and jumps.",
     OPT_INT},
    {"ripple_color", "#00ff0060",
     "Color of the ripple effect (with alpha for transparency).", OPT_STRING},
    {"ripple_duration", "300", "Duration of ripple animation in milliseconds.",
     OPT_INT},
    {"ripple_max_radius", "50", "Maximum radius of ripple in pixels.", OPT_INT},
    {"ripple_line_width", "2", "Width of the ripple circle line.", OPT_INT},
};

const char *config_get(const char *key)
{
	struct config_entry *ent;

	for (ent = config; ent; ent = ent->next)
		if (!strcmp(ent->key, key))
			return ent->value;

	fprintf(stderr, "FATAL: unrecognized config entry: %s\n", key);
	exit(-1);
}

int config_get_int(const char *key) { return atoi(config_get(key)); }

enum option_type get_option_type(const char *key)
{
	size_t i;

	for (i = 0; i < sizeof(options) / sizeof(options[0]); i++) {
		if (!strcmp(options[i].key, key))
			return options[i].type;
	}

	return 0;
}

static void validate_key_option(const char *s)
{
	struct input_event ev;
	char *tok;
	char buf[1024];

	strncpy(buf, s, sizeof buf);

	if (!strcmp(s, "unbind"))
		return;

	for (tok = strtok(buf, " "); tok; tok = strtok(NULL, " ")) {
		if (input_parse_string(&ev, tok)) {
			fprintf(stderr, "ERROR: %s is not a valid key name\n",
				tok);
			return;
		}
	}
}

static int is_valid_key_option(const char *s)
{
	struct input_event ev;
	char *tok;
	char buf[1024];
	size_t len;

	len = strlen(s);
	if (len >= sizeof buf)
		return 0;
	strncpy(buf, s, sizeof buf);
	buf[sizeof buf - 1] = 0;

	if (!strcmp(s, "unbind"))
		return 1;

	for (tok = strtok(buf, " "); tok; tok = strtok(NULL, " ")) {
		if (input_parse_string(&ev, tok))
			return 0;
	}

	return 1;
}

int config_set_value(const char *key, const char *value)
{
	struct config_entry *ent;
	enum option_type type;
	size_t len;
	int i;
	size_t value_cap = sizeof(((struct config_entry *)0)->value);

	if (!key || !value)
		return 0;

	type = get_option_type(key);
	if (!type)
		return 0;

	len = strlen(value);
	if (len >= value_cap)
		return 0;

	switch (type) {
	case OPT_INT:
		for (i = 0; value[i]; i++)
			if (!isdigit((unsigned char)value[i]) &&
			    !(i == 0 && value[0] == '-'))
				return 0;
		break;
	case OPT_BUTTON:
	case OPT_KEY:
		if (!is_valid_key_option(value))
			return 0;
		break;
	default:
		break;
	}

	for (ent = config; ent; ent = ent->next) {
		if (!strcmp(ent->key, key)) {
			strncpy(ent->value, value, sizeof ent->value);
			ent->value[sizeof ent->value - 1] = 0;
			return 1;
		}
	}

	return 0;
}

struct strbuf {
	char *data;
	size_t len;
	size_t cap;
};

static void sb_init(struct strbuf *sb)
{
	sb->cap = 1024;
	sb->len = 0;
	sb->data = calloc(1, sb->cap);
}

static void sb_reserve(struct strbuf *sb, size_t extra)
{
	if (sb->len + extra + 1 <= sb->cap)
		return;

	while (sb->len + extra + 1 > sb->cap)
		sb->cap *= 2;

	sb->data = realloc(sb->data, sb->cap);
}

static void sb_append(struct strbuf *sb, const char *fmt, ...)
{
	va_list ap;
	int needed;

	va_start(ap, fmt);
	needed = vsnprintf(NULL, 0, fmt, ap);
	va_end(ap);

	if (needed < 0)
		return;

	sb_reserve(sb, (size_t)needed);

	va_start(ap, fmt);
	vsnprintf(sb->data + sb->len, sb->cap - sb->len, fmt, ap);
	va_end(ap);
	sb->len += (size_t)needed;
}

static void sb_append_char(struct strbuf *sb, char c)
{
	sb_reserve(sb, 1);
	sb->data[sb->len++] = c;
	sb->data[sb->len] = '\0';
}

static void sb_append_escaped(struct strbuf *sb, const char *s)
{
	for (; s && *s; s++) {
		if (*s == '"' || *s == '\\')
			sb_append_char(sb, '\\');
		sb_append_char(sb, *s);
	}
}

char *config_schema_json(void)
{
	struct strbuf sb;
	size_t i;
	int first = 1;

	sb_init(&sb);
	sb_append(&sb, "{\"entries\":[");

	for (i = 0; i < sizeof(options) / sizeof(options[0]); i++) {
		if (!first)
			sb_append_char(&sb, ',');
		first = 0;

		sb_append(&sb, "{\"key\":\"");
		sb_append_escaped(&sb, options[i].key);
		sb_append(&sb, "\",\"default\":\"");
		sb_append_escaped(&sb, options[i].val);
		sb_append(&sb, "\",\"type\":\"%s\",\"description\":\"",
			  options[i].type == OPT_STRING ? "string" :
			  options[i].type == OPT_INT ? "int" :
			  options[i].type == OPT_KEY ? "key" :
			  options[i].type == OPT_BUTTON ? "button" : "unknown");
		sb_append_escaped(&sb, options[i].description);
		sb_append(&sb, "\"}");
	}

	sb_append(&sb, "]}");
	return sb.data;
}
static void config_add(const char *key, const char *val)
{
	struct config_entry *ent;
	ent = malloc(sizeof(struct config_entry));

	assert(strlen(key) < sizeof ent->key);
	assert(strlen(val) < sizeof ent->value);

	strcpy(ent->key, key);
	strcpy(ent->value, val);

	ent->type = get_option_type(key);
	if (!ent->type) {
		free(ent);
		return;
	}

	switch (ent->type) {
		int i;

	case OPT_INT:
		for (i = 0; ent->value[i]; i++)
			if (!isdigit(ent->value[i]) &&
			    !(i == 0 && ent->value[0] == '-')) {
				fprintf(stderr,
					"ERROR: %s must be a valid int\n",
					ent->value);
				exit(-1);
			}
		break;
	case OPT_BUTTON:
	case OPT_KEY:
		validate_key_option(ent->value);

		break;

	default:
		break;
	}

	ent->next = config;

	config = ent;
}

void parse_config(const char *path)
{
	size_t i;

	FILE *fh = (path[0] == '-' && path[1] == 0) ? stdin : fopen(path, "r");

	struct config_entry *ent = config;
	while (ent) {
		struct config_entry *tmp = ent;
		ent = ent->next;
		free(tmp);
	}
	config = NULL;

	for (i = 0; i < sizeof(options) / sizeof(options[0]); i++)
		config_add(options[i].key, options[i].val);

	if (fh) {
		char line[1024];
		while (1) {
			char *delim;
			size_t len;

			if (!fgets(line, sizeof line, fh))
				break;

			delim = strchr(line, ':');

			if (!delim || line[0] == '#')
				continue;

			*delim = 0;
			while (*++delim == ' ')
				;

			len = strlen(delim);
			while (delim[len - 1] == '\n' || delim[len - 1] == '\r')
				len--;

			delim[len] = 0;

			config_add(line, delim);
		}

		fclose(fh);
	}
}

static int token_has_mods(const char *tok)
{
	while (tok[1] == '-') {
		switch (tok[0]) {
		case 'A':
		case 'C':
		case 'M':
		case 'S':
			return 1;
		default:
			return 0;
		}

		tok += 2;
	}

	return 0;
}

static int keyidx(const char *key_list, struct input_event *ev, int *exact)
{
	const char *tok;
	char buf[1024];
	int idx = 1;
	int fallback = 0;

	*exact = 0;

	snprintf(buf, sizeof buf, "%s", key_list);

	for (tok = strtok(buf, " "); tok; tok = strtok(NULL, " ")) {
		int ret = input_eq(ev, tok);
		if (!ret) {
			idx++;
			continue;
		}

		if (ret == 1 && token_has_mods(tok)) {
			idx++;
			continue;
		}

		if (ret == 2) {
			*exact = 1;
			return idx;
		}

		if (!fallback)
			fallback = idx;

		idx++;
	}

	if (fallback) {
		*exact = 0;
		return fallback;
	}

	return 0;
}

void config_input_whitelist(const char *names[], size_t n)
{
	struct config_entry *ent;

	for (ent = config; ent; ent = ent->next) {
		ent->whitelisted = 0;

		if (ent->type != OPT_KEY && ent->type != OPT_BUTTON)
			continue;

		if (names == NULL) {
			ent->whitelisted = 1;
		} else {
			size_t i;

			for (i = 0; i < n; i++)
				if (!strcmp(names[i], ent->key)) {
					ent->whitelisted = 1;
					break;
				}
		}
	}
}

/*
 * Consumes an input event and the name of a config option corresponding
 * to a set of keys and returns the 1-based index of the most recent
 * matching key (if any). The supplied config_key may be shadowed by
 * another key with the same option_type as the supplied key (in which
 * case this function will return 0).

 * NOTE: This is horribly inefficient (albeit fast enough). A better solution
 * would be to consume the event and type and return the corresponding
 * option for subsequent matching, but that would require
 * modifying all calling code.
 */

int config_input_match(struct input_event *ev, const char *config_key)
{
	struct config_entry *ent;

	for (ent = config; ent; ent = ent->next) {
		int idx;
		int exact;

		if (!strcmp(ent->key, config_key) &&
		    !strcmp(ent->value, "unbind"))
			return 0;

		if (ent->whitelisted &&
		    (idx = keyidx(ent->value, ev, &exact))) {
			if ((ent->type == OPT_KEY && exact) ||
			    ent->type == OPT_BUTTON) {
				if (!strcmp(ent->key, config_key))
					return idx;
				else
					return 0;
			}
		}
	}

	return 0;
}

void config_print_options()
{
	size_t i;
	for (i = 0; i < sizeof(options) / sizeof(options[0]); i++)
		printf("%s: %s (default: %s)\n", options[i].key,
		       options[i].description, options[i].val);
}
