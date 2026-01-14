/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "warpd.h"

static void redraw(screen_t scr, int x, int y, int hide_cursor,
		   int show_rapid_indicator)
{
	int sw, sh;

	platform->screen_get_dimensions(scr, &sw, &sh);

	const int gap = 10;
	const int indicator_size =
	    (config_get_int("indicator_size") * sh) / 1080;
	const char *indicator_color = config_get("indicator_color");
	const char *curcol = config_get("cursor_color");
	const char *indicator = config_get("indicator");
	const int cursz = config_get_int("cursor_size");

	platform->screen_clear(scr);

	if (show_rapid_indicator) {
		const int border_width =
		    config_get_int("rapid_indicator_width");
		const char *border_color = config_get("rapid_indicator_color");

		if (border_width > 0 && border_width * 2 < sw &&
		    border_width * 2 < sh) {
			platform->screen_draw_box(scr, 0, 0, sw, border_width,
						  border_color);
			platform->screen_draw_box(scr, 0, sh - border_width, sw,
						  border_width, border_color);
			platform->screen_draw_box(scr, 0, 0, border_width, sh,
						  border_color);
			platform->screen_draw_box(scr, sw - border_width, 0,
						  border_width, sh,
						  border_color);
		}
	}

	if (!hide_cursor) {
		int drawn = 0;
		if (platform->screen_draw_cursor)
			drawn = platform->screen_draw_cursor(scr, x, y);
		if (!drawn)
			platform->screen_draw_box(scr, x + 1, y - cursz / 2,
						  cursz, cursz, curcol);
	}

	if (!strcmp(indicator, "bottomleft"))
		platform->screen_draw_box(scr, gap, sh - indicator_size - gap,
					  indicator_size, indicator_size,
					  indicator_color);
	else if (!strcmp(indicator, "topleft"))
		platform->screen_draw_box(scr, gap, gap, indicator_size,
					  indicator_size, indicator_color);
	else if (!strcmp(indicator, "topright"))
		platform->screen_draw_box(scr, sw - indicator_size - gap, gap,
					  indicator_size, indicator_size,
					  indicator_color);
	else if (!strcmp(indicator, "bottomright"))
		platform->screen_draw_box(
		    scr, sw - indicator_size - gap, sh - indicator_size - gap,
		    indicator_size, indicator_size, indicator_color);

	platform->commit();
}

static void move(screen_t scr, int x, int y, int hide_cursor,
		 int show_rapid_indicator)
{
	platform->mouse_move(scr, x, y);
	redraw(scr, x, y, hide_cursor, show_rapid_indicator);
}

struct input_event *normal_mode(struct input_event *start_ev, int oneshot)
{
	const int cursz = config_get_int("cursor_size");
	const int system_cursor = config_get_int("normal_system_cursor");
	const char *blink_interval = config_get("normal_blink_interval");

	int on_time, off_time;
	struct input_event *ev;
	screen_t scr;
	int sh, sw;
	int mx, my;
	int dragging = 0;
	int show_cursor = !system_cursor;
	int held_buttons[8] = {0};
	int rapid_mode = 0;
	int rapid_button = 0;
	uint64_t last_rapid_click = 0;

	int n = sscanf(blink_interval, "%d %d", &on_time, &off_time);
	assert(n > 0);
	if (n == 1)
		off_time = on_time;

	const char *keys[] = {
	    "accelerator",
	    "bottom",
	    "buttons",
	    "hold_buttons",
	    "rapid_mode",
	    "copy_and_exit",

	    "decelerator",
	    "down",
	    "drag",
	    "end",
	    "exit",
	    "grid",
	    "hint",
	    "hint2",
	    "hist_back",
	    "hist_forward",
	    "history",
	    "left",
	    "middle",
	    "oneshot_buttons",
	    "print",
	    "right",
	    "screen",
	    "scroll_down",
	    "scroll_end",
	    "scroll_home",
	    "scroll_left",
	    "scroll_page_down",
	    "scroll_page_up",
	    "scroll_right",
	    "scroll_up",
	    "start",
	    "top",
	    "up",
	};

	platform->input_grab_keyboard();

	platform->mouse_get_position(&scr, &mx, &my);
	platform->screen_get_dimensions(scr, &sw, &sh);

	if (!system_cursor)
		platform->mouse_hide();

	mouse_reset();
	redraw(scr, mx, my, !show_cursor, rapid_mode);

	uint64_t time = 0;
	uint64_t last_blink_update = 0;
	while (1) {
		config_input_whitelist(keys, sizeof keys / sizeof keys[0]);
		if (start_ev == NULL) {
			ev = platform->input_next_event(10);
			time += 10;
		} else {
			ev = start_ev;
			start_ev = NULL;
		}

		platform->mouse_get_position(&scr, &mx, &my);

		if (!system_cursor && on_time) {
			if (show_cursor &&
			    (time - last_blink_update) >= on_time) {
				show_cursor = 0;
				redraw(scr, mx, my, !show_cursor, rapid_mode);
				last_blink_update = time;
			} else if (!show_cursor &&
				   (time - last_blink_update) >= off_time) {
				show_cursor = 1;
				redraw(scr, mx, my, !show_cursor, rapid_mode);
				last_blink_update = time;
			}
		}

		scroll_tick();
		if (mouse_process_key(ev, "up", "down", "left", "right")) {
			redraw(scr, mx, my, !show_cursor, rapid_mode);
			continue;
		}

		const int skip_rapid =
		    ev && ev->pressed && config_input_match(ev, "exit");

		if (rapid_mode && rapid_button && !skip_rapid) {
			const int interval =
			    config_get_int("rapid_click_interval");
			if ((time - last_rapid_click) >= (uint64_t)interval) {
				if (platform->trigger_ripple)
					platform->trigger_ripple(scr, mx, my);
				platform->mouse_click(rapid_button);
				last_rapid_click = time;
			}
		}

		if (!ev) {
			// Force redraw if ripples are active (for animation)
			if (platform->has_active_ripples &&
			    platform->has_active_ripples(scr)) {
				redraw(scr, mx, my, !show_cursor, rapid_mode);
			}
			continue;
		} else if (config_input_match(ev, "scroll_down")) {

			redraw(scr, mx, my, 1, rapid_mode);

			if (ev->pressed) {
				scroll_stop();
				scroll_accelerate(SCROLL_DOWN);
			} else
				scroll_decelerate();
		} else if (config_input_match(ev, "scroll_up")) {
			redraw(scr, mx, my, 1, rapid_mode);

			if (ev->pressed) {
				scroll_stop();
				scroll_accelerate(SCROLL_UP);
			} else
				scroll_decelerate();
		} else if (config_input_match(ev, "scroll_left")) {
			redraw(scr, mx, my, 1, rapid_mode);

			if (ev->pressed) {
				scroll_stop();
				scroll_accelerate(SCROLL_LEFT);
			} else
				scroll_decelerate();
		} else if (config_input_match(ev, "scroll_right")) {
			redraw(scr, mx, my, 1, rapid_mode);

			if (ev->pressed) {
				scroll_stop();
				scroll_accelerate(SCROLL_RIGHT);
			} else
				scroll_decelerate();
		} else if (config_input_match(ev, "scroll_page_down")) {
			if (ev->pressed) {
				int amount =
				    config_get_int("scroll_page_amount");
				scroll_stop();
				redraw(scr, mx, my, 1, rapid_mode);
				platform->scroll_amount(SCROLL_DOWN, amount);
			}
		} else if (config_input_match(ev, "scroll_page_up")) {
			if (ev->pressed) {
				int amount =
				    config_get_int("scroll_page_amount");
				scroll_stop();
				redraw(scr, mx, my, 1, rapid_mode);
				platform->scroll_amount(SCROLL_UP, amount);
			}
		} else if (config_input_match(ev, "scroll_home")) {
			if (ev->pressed) {
				int amount =
				    config_get_int("scroll_home_amount");
				scroll_stop();
				redraw(scr, mx, my, 1, rapid_mode);
				platform->scroll_amount(SCROLL_UP, amount);
			}
		} else if (config_input_match(ev, "scroll_end")) {
			if (ev->pressed) {
				int amount =
				    config_get_int("scroll_home_amount");
				scroll_stop();
				redraw(scr, mx, my, 1, rapid_mode);
				platform->scroll_amount(SCROLL_DOWN, amount);
			}
		} else if (config_input_match(ev, "accelerator")) {
			if (ev->pressed)
				mouse_fast();
			else
				mouse_normal();
		} else if (config_input_match(ev, "decelerator")) {
			mouse_slow();
		}

		if (config_input_match(ev, "rapid_mode") && ev->pressed) {
			rapid_mode = !rapid_mode;
			if (!rapid_mode)
				rapid_button = 0;
			redraw(scr, mx, my, !show_cursor, rapid_mode);
			goto next;
		}

		if (rapid_mode && ev->pressed) {
			int btn = config_input_match(ev, "buttons");
			if (!btn)
				btn = config_input_match(ev, "hold_buttons");
			if (!btn)
				btn = config_input_match(ev, "oneshot_buttons");
			if (btn) {
				rapid_button = btn;
				if (platform->trigger_ripple)
					platform->trigger_ripple(scr, mx, my);
				platform->mouse_click(btn);
				last_rapid_click = time;
				goto next;
			}
		}

		{
			int btn = config_input_match(ev, "hold_buttons");
			if (btn) {
				if (rapid_mode)
					goto next;
				const int drag_button =
				    config_get_int("drag_button");
				if (dragging && btn == drag_button)
					goto next;
				if (btn < (int)(sizeof(held_buttons) /
						sizeof(held_buttons[0]))) {
					if (ev->pressed) {
						if (!held_buttons[btn]) {
							held_buttons[btn] = 1;
							platform->mouse_down(
							    btn);
						}
					} else if (held_buttons[btn]) {
						held_buttons[btn] = 0;
						platform->mouse_up(btn);
						if (platform->trigger_ripple)
							platform
							    ->trigger_ripple(
								scr, mx, my);
					}
				}
				goto next;
			}
		}

		if (!ev->pressed) {
			goto next;
		}

		if (config_input_match(ev, "top")) {
			move(scr, mx, cursz / 2, !show_cursor, rapid_mode);
			if (platform->trigger_ripple)
				platform->trigger_ripple(scr, mx, cursz / 2);
		} else if (config_input_match(ev, "bottom")) {
			move(scr, mx, sh - cursz / 2, !show_cursor, rapid_mode);
			if (platform->trigger_ripple)
				platform->trigger_ripple(scr, mx,
							 sh - cursz / 2);
		} else if (config_input_match(ev, "middle")) {
			move(scr, mx, sh / 2, !show_cursor, rapid_mode);
			if (platform->trigger_ripple)
				platform->trigger_ripple(scr, mx, sh / 2);
		} else if (config_input_match(ev, "start")) {
			move(scr, 1, my, !show_cursor, rapid_mode);
			if (platform->trigger_ripple)
				platform->trigger_ripple(scr, 1, my);
		} else if (config_input_match(ev, "end")) {
			move(scr, sw - cursz, my, !show_cursor, rapid_mode);
			if (platform->trigger_ripple)
				platform->trigger_ripple(scr, sw - cursz, my);
		} else if (config_input_match(ev, "hist_back")) {
			hist_add(mx, my);
			hist_prev();
			hist_get(&mx, &my);

			move(scr, mx, my, !show_cursor, rapid_mode);
			if (platform->trigger_ripple)
				platform->trigger_ripple(scr, mx, my);
		} else if (config_input_match(ev, "hist_forward")) {
			hist_next();
			hist_get(&mx, &my);

			move(scr, mx, my, !show_cursor, rapid_mode);
			if (platform->trigger_ripple)
				platform->trigger_ripple(scr, mx, my);
		} else if (config_input_match(ev, "drag")) {
			dragging = !dragging;
			if (dragging)
				platform->mouse_down(
				    config_get_int("drag_button"));
			else
				platform->mouse_up(
				    config_get_int("drag_button"));
		} else if (config_input_match(ev, "copy_and_exit")) {
			platform->mouse_up(config_get_int("drag_button"));
			platform->copy_selection();
			ev = NULL;
			goto exit;
		} else if (config_input_match(ev, "exit") ||
			   config_input_match(ev, "grid") ||
			   config_input_match(ev, "screen") ||
			   config_input_match(ev, "history") ||
			   config_input_match(ev, "hint2") ||
			   config_input_match(ev, "hint")) {
			rapid_mode = 0;
			rapid_button = 0;
			goto exit;
		} else if (config_input_match(ev, "print")) {
			printf("%d %d %s\n", mx, my, input_event_tostr(ev));
			fflush(stdout);
		} else { /* Mouse Buttons. */
			int btn;

			if ((btn = config_input_match(ev, "buttons"))) {
				if (oneshot) {
					printf("%d %d\n", mx, my);
					exit(btn);
				}

				hist_add(mx, my);
				histfile_add(mx, my);
				if (platform->trigger_ripple)
					platform->trigger_ripple(scr, mx, my);
				platform->mouse_click(btn);
			} else if ((btn = config_input_match(
					ev, "oneshot_buttons"))) {
				hist_add(mx, my);
				if (platform->trigger_ripple)
					platform->trigger_ripple(scr, mx, my);
				platform->mouse_click(btn);

				const int timeout =
				    config_get_int("oneshot_timeout");

				while (1) {
					struct input_event *ev =
					    platform->input_next_event(timeout);

					if (!ev)
						break;

					if (ev && ev->pressed &&
					    config_input_match(
						ev, "oneshot_buttons")) {
						platform->mouse_click(btn);
					}
				}

				goto exit;
			}
		}
	next:
		platform->mouse_get_position(&scr, &mx, &my);

		platform->commit();
	}

exit:
	rapid_mode = 0;
	rapid_button = 0;
	if (platform->screen_clear_ripples)
		platform->screen_clear_ripples(scr);
	for (size_t i = 1; i < sizeof(held_buttons) / sizeof(held_buttons[0]);
	     i++) {

		if (held_buttons[i])
			platform->mouse_up(i);
	}
	platform->mouse_show();
	platform->screen_clear(scr);

	platform->input_ungrab_keyboard();

	platform->commit();
	return ev;
}
