/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "warpd.h"

static uint8_t cached_mods[256];

int input_parse_string(struct input_event *ev, const char *s)
{
	if (!s || s[0] == 0)
		return 0;

	ev->mods = 0;
	ev->pressed = 1;
	ev->code = 0;

	while (s[1] == '-') {
		switch (s[0]) {
		case 'A':
			ev->mods |= PLATFORM_MOD_ALT;
			break;
		case 'M':
			ev->mods |= PLATFORM_MOD_META;
			break;
		case 'S':
			ev->mods |= PLATFORM_MOD_SHIFT;
			break;
		case 'C':
			ev->mods |= PLATFORM_MOD_CONTROL;
			break;
		default:
			fprintf(stderr, "%s is not a valid modifier\n", s);
			exit(-1);
		}

		s += 2;
	}

	if (s[0]) {
		int shifted = 0;

		/*
		 * For single printable characters, use layout-independent QWERTY
		 * mapping. This ensures key bindings work regardless of the current
		 * keyboard layout (e.g., Hebrew, Russian, Arabic).
		 */
		if (s[1] == 0 && s[0] >= ' ' && s[0] <= '~') {
			ev->code = platform->input_qwerty_to_code(s[0]);
			/* Handle uppercase letters - map to lowercase and set shift */
			if (!ev->code && s[0] >= 'A' && s[0] <= 'Z') {
				ev->code = platform->input_qwerty_to_code(s[0] - 'A' + 'a');
				shifted = 1;
			}
		}

		/* Try layout-independent lookup for special keys (esc, backspace, etc.) */
		if (!ev->code)
			ev->code = platform->input_special_to_code(s);

		/* Fall back to layout-dependent lookup as last resort */
		if (!ev->code)
			ev->code = platform->input_lookup_code(s, &shifted);

		if (shifted)
			ev->mods |= PLATFORM_MOD_SHIFT;

		if (!ev->code)
			return -1;
	}

	return 0;
}

const char *input_event_tostr(struct input_event *ev)
{
	static char s[64];
	const char *name = platform->input_lookup_name(ev->code, ev->mods & PLATFORM_MOD_SHIFT ? 1 : 0);
	int n = 0;

	if (!ev)
		return "NULL";

	if (ev->mods & PLATFORM_MOD_CONTROL) {
		s[n++] = 'C';
		s[n++] = '-';
	}

	if (ev->mods & PLATFORM_MOD_ALT) {
		s[n++] = 'A';
		s[n++] = '-';
	}

	if (ev->mods & PLATFORM_MOD_META) {
		s[n++] = 'M';
		s[n++] = '-';
	}

	strcpy(s + n, name ? name : "UNDEFINED");

	return s;
}

/*
 * Returns:
 * 0 on no match
 * 1 on code match
 * 2 on full match
 */
int input_eq(struct input_event *ev, const char *str)
{
	uint8_t mods;
	struct input_event ev1;

	if (!ev)
		return 0;

	/*
	 * Cache mods on key down so we can properly detect the
	 * corresponding key up event in the case of intermittent
	 * modifier changes.
	 */
	if (ev->pressed) {
		mods = ev->mods;
		cached_mods[ev->code] = ev->mods;
	} else {
		mods = cached_mods[ev->code];
	}

	if (input_parse_string(&ev1, str) < 0)
		return 0;

	if (ev1.code != ev->code)
		return 0;
	else if (ev1.mods != mods)
		return 1;
	else
		return 2;
}
