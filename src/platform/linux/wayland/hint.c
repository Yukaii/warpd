/*
 * keyd - A key remapping daemon.
 *
 * © 2019 Raheman Vaiya (see also: LICENSE).
 */
#include "wayland.h"

static char bgcolor[16];
static char fgcolor[16];
static char border_color[16];
static int border_width;
static const char *font_family;

static int calculate_font_size(cairo_t *cr, int w, int h)
{
	cairo_text_extents_t extents;
	size_t sz = 100;

	cairo_select_font_face(cr, font_family, CAIRO_FONT_SLANT_NORMAL,
			       CAIRO_FONT_WEIGHT_NORMAL);

	do {
		cairo_set_font_size(cr, sz);
		cairo_text_extents(cr, "WW", &extents);
		sz--;
	} while (extents.height > h || extents.width > w);

	return sz;
}

static void cairo_draw_text(cairo_t *cr, const char *s, int x, int y, int w,
			    int h)
{
	int ptsz = calculate_font_size(cr, w, h);

	cairo_select_font_face(cr, font_family, CAIRO_FONT_SLANT_NORMAL,
			       CAIRO_FONT_WEIGHT_NORMAL);

	cairo_text_extents_t extents;
	cairo_set_font_size(cr, ptsz);

	cairo_text_extents(cr, s, &extents);

	cairo_move_to(cr, x + (w - extents.width) / 2,
		      y - extents.y_bearing + (h - extents.height) / 2);
	cairo_show_text(cr, s);
}

void way_hint_draw(struct screen *scr, struct hint *hints, size_t n)
{
	size_t i;
	uint8_t r, g, b, a;

	cairo_t *cr = scr->cr;

	if (scr->hints)
		destroy_surface(scr->hints);

	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_rgba(cr, 0, 0, 0, 0);
	cairo_paint(cr);

	for (i = 0; i < n; i++) {
		way_hex_to_rgba(bgcolor, &r, &g, &b, &a);
		cairo_set_source_rgba(cr, r / 255.0, g / 255.0, b / 255.0,
				      a / 255.0);
		cairo_rectangle(cr, hints[i].x, hints[i].y, hints[i].w,
				hints[i].h);
		cairo_fill(cr);

		if (border_width > 0) {
			way_hex_to_rgba(border_color, &r, &g, &b, &a);
			cairo_set_source_rgba(cr, r / 255.0, g / 255.0,
					      b / 255.0, a / 255.0);
			cairo_set_line_width(cr, border_width);
			cairo_rectangle(cr, hints[i].x, hints[i].y, hints[i].w,
					hints[i].h);
			cairo_stroke(cr);
		}

		way_hex_to_rgba(fgcolor, &r, &g, &b, &a);
		cairo_set_source_rgba(cr, r / 255.0, g / 255.0, b / 255.0,
				      a / 255.0);

		cairo_draw_text(cr, hints[i].label, hints[i].x, hints[i].y,
				hints[i].w, hints[i].h);
	}

	scr->hints = create_surface(scr, 0, 0, scr->w, scr->h, 0);
}

void way_init_hint(const char *bg, const char *fg, int border_radius,
		   const char *border_col, int _border_width, const char *font)
{
	strncpy(bgcolor, bg, sizeof bgcolor);
	strncpy(fgcolor, fg, sizeof fgcolor);
	strncpy(border_color, border_col, sizeof border_color);
	border_width = _border_width;

	// TODO: handle border radius

	font_family = font;
}
