#include "macos.h"

static float border_radius;
static float border_width;

static NSColor *bgColor;
static NSColor *fgColor;
static NSColor *borderColor;
const char *font;


static void draw_hook(void *arg, NSView *view)
{
	size_t i;
	struct screen *scr = arg;

	for (i = 0; i < scr->nr_hints; i++) {
		struct hint *h = &scr->hints[i];
		macos_draw_box(scr, bgColor,
				h->x, h->y, h->w, h->h, border_radius);
		if (border_width > 0) {
			macos_draw_box_outline(scr, borderColor,
					h->x, h->y, h->w, h->h, border_radius, border_width);
		}

		macos_draw_text(scr, fgColor, font,
				h->x, h->y, h->w, h->h, h->label);
	}
}

void osx_hint_draw(struct screen *scr, struct hint *hints, size_t n)
{
	scr->nr_hints = n;
	memcpy(scr->hints, hints, sizeof(struct hint)*n);

	window_register_draw_hook(scr->overlay, draw_hook, scr);
}

void osx_init_hint(const char *bg, const char *fg, int _border_radius,
	       const char *border_color, int _border_width, const char *font_family)
{
	bgColor = nscolor_from_hex(bg);
	fgColor = nscolor_from_hex(fg);
	borderColor = nscolor_from_hex(border_color);

	border_radius = (float)_border_radius;
	border_width = (float)_border_width;
	font = font_family;
}

