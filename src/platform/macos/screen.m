/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "macos.h"
#include "../../warpd.h"
#include <limits.h>
#include <string.h>

struct screen screens[32];
size_t nr_screens;

static NSImage *cursor_image = nil;
static NSPoint cursor_hotspot = {0, 0};
static char cursor_pack_path[PATH_MAX] = {0};

static void draw_hook(void *arg, NSView *view)
{
	struct box *b = arg;
	macos_draw_box(b->scr, b->color, b->x, b->y, b->w, b->h, 0);
}

static void cursor_draw_hook(void *arg, NSView *view)
{
	struct cursor_draw *cursor = arg;
	if (!cursor->image)
		return;

	NSSize size = [cursor->image size];
	float draw_x = cursor->x - cursor->hotspot.x;
	float draw_y = cursor->scr->h - cursor->y + cursor->hotspot.y - size.height;

	[cursor->image drawInRect:NSMakeRect(draw_x, draw_y, size.width, size.height)
				 fromRect:NSZeroRect
				operation:NSCompositingOperationSourceOver
				 fraction:1.0];
}

static NSString *resolve_cursor_pack_path(const char *cursor_pack)
{
	if (!cursor_pack || !cursor_pack[0] || !strcmp(cursor_pack, "none"))
		return nil;

	NSString *name = [NSString stringWithUTF8String:cursor_pack];
	name = [name stringByExpandingTildeInPath];

	NSFileManager *fm = [NSFileManager defaultManager];
	if ([name containsString:@"/"]) {
		if ([fm fileExistsAtPath:name])
			return name;
		return nil;
	}

	NSString *systemCursorPath =
	    @"/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors";
	NSArray<NSString *> *bases = @[
	    [@"~/Library/Cursors" stringByExpandingTildeInPath],
	    @"/Library/Cursors",
	    systemCursorPath,
	];
	NSArray<NSString *> *suffixes = @[
	    name,
	    [name stringByAppendingString:@".cursor"],
	];

	for (NSString *base in bases) {
		for (NSString *suffix in suffixes) {
			NSString *candidate = [base stringByAppendingPathComponent:suffix];
			if ([fm fileExistsAtPath:candidate])
				return candidate;
		}
	}

	return nil;
}

static int load_cursor_pack(const char *cursor_pack)
{
	NSString *bundle_path = resolve_cursor_pack_path(cursor_pack);
	if (!bundle_path) {
		cursor_image = nil;
		cursor_pack_path[0] = '\0';
		return 0;
	}

	const char *bundle_cstr = [bundle_path fileSystemRepresentation];
	if (cursor_image && strcmp(cursor_pack_path, bundle_cstr) == 0)
		return 1;

	strncpy(cursor_pack_path, bundle_cstr, sizeof(cursor_pack_path) - 1);
	cursor_pack_path[sizeof(cursor_pack_path) - 1] = '\0';

	NSString *plist_path = [bundle_path stringByAppendingPathComponent:@"info.plist"];
	NSDictionary *plist =
	    [NSDictionary dictionaryWithContentsOfFile:plist_path];
	NSNumber *hotx = plist[@"hotx-scaled"] ?: plist[@"hotx"];
	NSNumber *hoty = plist[@"hoty-scaled"] ?: plist[@"hoty"];
	cursor_hotspot = NSMakePoint(hotx ? hotx.floatValue : 0,
				     hoty ? hoty.floatValue : 0);

	NSArray<NSString *> *image_names = @[
	    @"cursor.pdf",
	    @"cursor.png",
	    @"cursor.tiff",
	];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *image_path = nil;
	for (NSString *image_name in image_names) {
		NSString *candidate =
		    [bundle_path stringByAppendingPathComponent:image_name];
		if ([fm fileExistsAtPath:candidate]) {
			image_path = candidate;
			break;
		}
	}

	if (!image_path) {
		cursor_image = nil;
		return 0;
	}

	cursor_image = [[NSImage alloc] initWithContentsOfFile:image_path];
	return cursor_image != nil;
}

static void halo_draw_hook(void *arg, NSView *view)
{
	struct halo *h = arg;
	if (!h->color || h->radius <= 0)
		return;

	// Draw filled circle (halo) behind cursor
	float x = h->x;
	float y = h->scr->h - h->y;  // Convert ULO to LLO

	NSBezierPath *path = [NSBezierPath bezierPath];
	[path appendBezierPathWithOvalInRect:NSMakeRect(x - h->radius, y - h->radius,
							h->radius * 2, h->radius * 2)];
	[h->color setFill];
	[path fill];
}

static void entry_pulse_draw_hook(void *arg, NSView *view)
{
	struct entry_pulse *ep = arg;
	struct screen *scr = &screens[0];

	// Find which screen this entry pulse belongs to
	for (size_t i = 0; i < nr_screens; i++) {
		if (&screens[i].entry_pulse == ep) {
			scr = &screens[i];
			break;
		}
	}

	uint64_t now = get_time_us() / 1000;
	uint64_t elapsed = now - ep->start_time;
	int duration = config_get_int("cursor_entry_duration");

	if (elapsed > duration) {
		ep->active = 0;
		return;
	}

	// Calculate current radius based on elapsed time
	float progress = (float)elapsed / (float)duration;
	float max_radius = (float)config_get_int("cursor_entry_radius");
	ep->radius = progress * max_radius;

	// Calculate alpha based on progress (fade out)
	float alpha = 1.0 - progress;

	NSColor *color = nscolor_from_hex(config_get("cursor_entry_color"));
	NSColor *fadedColor = [color colorWithAlphaComponent:alpha];
	float lineWidth = 2.0;  // Entry pulse uses fixed line width

	macos_draw_circle(scr, fadedColor, (float)ep->x, (float)ep->y, ep->radius, lineWidth);
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

int osx_screen_draw_cursor(struct screen *scr, int x, int y)
{
	const char *cursor_pack = config_get("cursor_pack");
	if (!cursor_pack || !cursor_pack[0] || !strcmp(cursor_pack, "none"))
		return 0;

	if (!load_cursor_pack(cursor_pack))
		return 0;

	scr->cursor.scr = scr;
	scr->cursor.x = x;
	scr->cursor.y = y;
	scr->cursor.image = cursor_image;
	scr->cursor.hotspot = cursor_hotspot;

	window_register_draw_hook(scr->overlay, cursor_draw_hook, &scr->cursor);
	return 1;
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

	// Overlay may be NULL during initialization
	if (!scr->overlay)
		return;

	scr->overlay->nr_hooks = 0;

	// Keep active ripples and register their draw hooks
	if (config_get_int("ripple_enabled")) {
		for (size_t i = 0; i < scr->nr_ripples; i++) {
			if (scr->ripples[i].active) {
				window_register_draw_hook(scr->overlay, ripple_draw_hook, &scr->ripples[i]);
			}
		}
	}

	// Keep active entry pulse and register its draw hook
	if (config_get_int("cursor_entry_effect") && scr->entry_pulse.active) {
		window_register_draw_hook(scr->overlay, entry_pulse_draw_hook, &scr->entry_pulse);
	}
}

void osx_screen_clear_ripples(struct screen *scr)
{
	for (size_t i = 0; i < scr->nr_ripples; i++)
		scr->ripples[i].active = 0;
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

void osx_screen_draw_halo(struct screen *scr, int x, int y)
{
	if (!config_get_int("cursor_halo_enabled"))
		return;

	scr->halo.scr = scr;
	scr->halo.x = x;
	scr->halo.y = y;
	scr->halo.radius = (float)config_get_int("cursor_halo_radius");
	scr->halo.color = nscolor_from_hex(config_get("cursor_halo_color"));

	// Register halo draw hook (drawn before cursor so it appears behind)
	window_register_draw_hook(scr->overlay, halo_draw_hook, &scr->halo);
}

void osx_trigger_entry_pulse(struct screen *scr, int x, int y)
{
	if (!config_get_int("cursor_entry_effect"))
		return;

	scr->entry_pulse.x = x;
	scr->entry_pulse.y = y;
	scr->entry_pulse.radius = 0;
	scr->entry_pulse.start_time = get_time_us() / 1000;
	scr->entry_pulse.active = 1;
}

int osx_has_active_entry_pulse(struct screen *scr)
{
	if (!config_get_int("cursor_entry_effect"))
		return 0;

	return scr->entry_pulse.active;
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
