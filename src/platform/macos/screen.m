/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "macos.h"
#include "../../warpd.h"

struct screen screens[32];
size_t nr_screens;

static void draw_hook(void *arg, NSView *view)
{
	struct box *b = arg;
	macos_draw_box(b->scr, b->color, b->x, b->y, b->w, b->h, 0);
}

static void ripple_draw_hook(void *arg, NSView *view)
{
	struct ripple *r = arg;
	struct screen *scr = &screens[0]; // Get first screen for now

	// Find which screen this ripple belongs to
	for (size_t i = 0; i < nr_screens; i++) {
		if (r >= screens[i].ripples && r < screens[i].ripples + MAX_RIPPLES) {
			scr = &screens[i];
			break;
		}
	}

	uint64_t now = get_time_us() / 1000; // Convert to milliseconds
	uint64_t elapsed = now - r->start_time;
	int duration = config_get_int("ripple_duration");

	if (elapsed > duration) {
		r->active = 0;
		return;
	}

	// Calculate current radius based on elapsed time
	float progress = (float)elapsed / (float)duration;
	float max_radius = (float)config_get_int("ripple_max_radius");
	r->radius = progress * max_radius;

	// Calculate alpha based on progress (fade out)
	float alpha = 1.0 - progress;

	NSColor *color = nscolor_from_hex(config_get("ripple_color"));
	NSColor *fadedColor = [color colorWithAlphaComponent:alpha];
	float lineWidth = (float)config_get_int("ripple_line_width");

	macos_draw_circle(scr, fadedColor, (float)r->x, (float)r->y, r->radius, lineWidth);
}

void osx_screen_draw_box(struct screen *scr, int x, int y, int w, int h, const char *color)
{
	assert(scr->nr_boxes < MAX_BOXES);
	struct box *b = &scr->boxes[scr->nr_boxes++];

	b->x = x;
	b->y = y;
	b->w = w;
	b->h = h;
	b->scr = scr;
	b->color = nscolor_from_hex(color);

	window_register_draw_hook(scr->overlay, draw_hook, b);
}

void osx_screen_list(struct screen *rscreens[MAX_SCREENS], size_t *n)
{
	size_t i;

	for (i = 0; i < nr_screens; i++)
		rscreens[i] = &screens[i];

	*n = nr_screens;
}

void osx_screen_clear(struct screen *scr)
{
	scr->nr_boxes = 0;
	scr->overlay->nr_hooks = 0;

	// Keep active ripples and register their draw hooks
	if (config_get_int("ripple_enabled")) {
		for (size_t i = 0; i < scr->nr_ripples; i++) {
			if (scr->ripples[i].active) {
				window_register_draw_hook(scr->overlay, ripple_draw_hook, &scr->ripples[i]);
			}
		}
	}
}

void osx_trigger_ripple(struct screen *scr, int x, int y)
{
	if (!config_get_int("ripple_enabled"))
		return;

	// Find an inactive ripple slot or reuse the oldest one
	struct ripple *r = NULL;
	for (size_t i = 0; i < MAX_RIPPLES; i++) {
		if (!scr->ripples[i].active) {
			r = &scr->ripples[i];
			if (i >= scr->nr_ripples)
				scr->nr_ripples = i + 1;
			break;
		}
	}

	// If all slots are full, reuse the oldest one
	if (!r && scr->nr_ripples > 0) {
		r = &scr->ripples[0];
	}

	if (r) {
		r->x = x;
		r->y = y;
		r->radius = 0;
		r->start_time = get_time_us() / 1000; // milliseconds
		r->active = 1;
	}
}

void osx_screen_get_dimensions(struct screen *scr, int *w, int *h)
{
	*w = scr->w;
	*h = scr->h;
}

int osx_has_active_ripples(struct screen *scr)
{
	if (!config_get_int("ripple_enabled"))
		return 0;

	for (size_t i = 0; i < scr->nr_ripples; i++) {
		if (scr->ripples[i].active)
			return 1;
	}
	return 0;
}

void macos_init_screen()
{
	for (NSScreen *screen in NSScreen.screens) {
		struct screen *scr = &screens[nr_screens++];

		scr->x = screen.frame.origin.x;
		scr->y = screen.frame.origin.y;
		scr->w = screen.frame.size.width;
		scr->h = screen.frame.size.height;

		scr->overlay = create_overlay_window(scr->x, scr->y, scr->w, scr->h);
	}
}
