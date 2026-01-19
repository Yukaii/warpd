#include "warpd.h"
static const char *activation_keys[] = {
    "activation_key",	    "hint_activation_key", "find_activation_key",
    "grid_activation_key",  "hint_oneshot_key",	   "screen_activation_key",
    "hint2_activation_key", "hint2_oneshot_key",   "history_activation_key",
};

static struct input_event
    activation_events[sizeof activation_keys / sizeof activation_keys[0]];

static int activation_event_match(const struct input_event *ev,
				  const struct input_event *key)
{
	return ev && ev->code == key->code && ev->mods == key->mods;
}

static void reload_config(const char *path)
{
	int i;

	parse_config(path);

	init_hints();
	init_mouse();

	for (i = 0; i < sizeof activation_keys / sizeof activation_keys[0]; i++)
		input_parse_string(&activation_events[i],
				   config_get(activation_keys[i]));
}

void daemon_loop(const char *config_path)
{
	size_t i;

	platform->monitor_file(config_path);
	reload_config(config_path);

	while (1) {
		int mode = 0;
		struct input_event *ev = platform->input_wait(
		    activation_events,
		    sizeof(activation_events) / sizeof(activation_events[0]));

		if (!ev) {
			reload_config(config_path);
			continue;
		}

		config_input_whitelist(activation_keys,
				       sizeof activation_keys /
					   sizeof activation_keys[0]);

		if (activation_event_match(ev, &activation_events[0]))
			mode = MODE_NORMAL;
		else if (activation_event_match(ev, &activation_events[3]))
			mode = MODE_GRID;
		else if (activation_event_match(ev, &activation_events[1]))
			mode = MODE_HINT;
		else if (activation_event_match(ev, &activation_events[2]))
			mode = MODE_FIND;
		else if (activation_event_match(ev, &activation_events[6]))
			mode = MODE_HINT2;
		else if (activation_event_match(ev, &activation_events[5]))
			mode = MODE_SCREEN_SELECTION;
		else if (activation_event_match(ev, &activation_events[8]))
			mode = MODE_HISTORY;
		else if (activation_event_match(ev, &activation_events[7])) {
			full_hint_mode(1);
			continue;
		} else if (activation_event_match(ev, &activation_events[4])) {
			full_hint_mode(0);
			continue;
		}

		mode_loop(mode, 0, 1);
	}
}
