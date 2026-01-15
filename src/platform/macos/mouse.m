/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "macos.h"
#include <limits.h>
#include <mach/mach_time.h>

static NSTimer *hider_timer = NULL;
static int hide_depth = 0;
static int dragging = 0;

@interface CursorHider : NSObject
@end

@implementation CursorHider
- (void)hide
{
	CGDisplayHideCursor(kCGDirectMainDisplay);
	hide_depth++;
}
@end

static long get_time_ms()
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);

	return ts.tv_sec * 1E3 + ts.tv_nsec / 1E6;
}

static uint64_t monotonic_time_ns()
{
	static mach_timebase_info_data_t timebase = {0};
	uint64_t now = mach_absolute_time();

	if (timebase.denom == 0)
		mach_timebase_info(&timebase);

	return (now * timebase.numer) / timebase.denom;
}

static CGEventFlags get_active_mod_flags()
{
	CGEventFlags mask = 0;

	if (active_mods & PLATFORM_MOD_META)
		mask |= kCGEventFlagMaskCommand;
	if (active_mods & PLATFORM_MOD_ALT)
		mask |= kCGEventFlagMaskAlternate;
	if (active_mods & PLATFORM_MOD_CONTROL)
		mask |= kCGEventFlagMaskControl;
	if (active_mods & PLATFORM_MOD_SHIFT)
		mask |= kCGEventFlagMaskShift;

	return mask;
}

static void do_mouse_click(int btn, int pressed, int nclicks)
{
	CGEventRef ev = CGEventCreate(NULL);
	CGPoint current_pos = CGEventGetLocation(ev);
	CFRelease(ev);

	int down = kCGEventLeftMouseDown;
	int up = kCGEventLeftMouseUp;
	int button = kCGMouseButtonLeft;
	CGEventFlags mask = get_active_mod_flags();

	switch (btn) {
	case 3:
		down = kCGEventRightMouseDown;
		up = kCGEventRightMouseUp;
		button = kCGMouseButtonRight;
		break;
	case 1:
		down = kCGEventLeftMouseDown;
		up = kCGEventLeftMouseUp;
		button = kCGMouseButtonLeft;
		break;
	default:
		down = kCGEventOtherMouseDown;
		up = kCGEventOtherMouseUp;
		button = btn;
		break;
	}


	if (pressed) {
		ev = CGEventCreateMouseEvent(NULL, down, current_pos, button);

		CGEventSetFlags(ev, mask);

		CGEventSetIntegerValueField(ev, kCGMouseEventClickState,
					    nclicks);
		CGEventPost(kCGHIDEventTap, ev);
		CFRelease(ev);
	} else {
		ev = CGEventCreateMouseEvent(NULL, up, current_pos, button);

		CGEventSetFlags(ev, mask);

		CGEventSetIntegerValueField(ev, kCGMouseEventClickState,
					    nclicks);
		CGEventPost(kCGHIDEventTap, ev);
		CFRelease(ev);
	}
}

void osx_mouse_click(int btn)
{
	dispatch_sync(dispatch_get_main_queue(), ^{
		const int threshold = 300;
		dragging = 0;

		static long last_ts = 0;
		static int clicks = 1;

		/*
		 * Apparently quartz events accrete and encode the number of clicks
		 * rather than leaving this to the application, so we need this ugly
		 * workaround :/.
		 */

		if ((get_time_ms() - last_ts) < threshold)
			clicks++;
		else
			clicks = 1;

		do_mouse_click(btn, 1, clicks);
		do_mouse_click(btn, 0, clicks);

		last_ts = get_time_ms();
	});
}

void osx_mouse_up(int btn)
{
	if (btn == 1)
		dragging = 0;

	do_mouse_click(btn, 0, 1);
}

void osx_mouse_down(int btn)
{
	if (btn == 1)
		dragging = 1;

	do_mouse_click(btn, 1, 1);
}

void osx_mouse_get_position(struct screen **_scr, int *_x, int *_y)
{
	size_t i;
	NSPoint loc = [NSEvent mouseLocation];
	int x = loc.x;
	int y = loc.y;

	/*
	 * First try exact screen match.
	 */
	for (i = 0; i < nr_screens; i++) {
		struct screen *scr = &screens[i];

		if (x >= scr->x &&
		    x <= scr->x+scr->w &&
		    y >= scr->y &&
		    y <= scr->y+scr->h) {
			x -= scr->x;
			y -= scr->y;

			y = scr->h - y;

			if (_x)
				*_x = x;
			if (_y)
				*_y = y;
			if (_scr)
				*_scr = scr;
			return;
		}
	}

	/*
	 * Cursor is outside all screen bounds (can happen with edge-push events
	 * for Dock triggering). Find the nearest screen and clamp coordinates.
	 */
	struct screen *nearest = &screens[0];
	int min_dist = INT_MAX;

	for (i = 0; i < nr_screens; i++) {
		struct screen *scr = &screens[i];
		int dx = 0, dy = 0;

		if (x < scr->x) dx = scr->x - x;
		else if (x > scr->x + scr->w) dx = x - (scr->x + scr->w);

		if (y < scr->y) dy = scr->y - y;
		else if (y > scr->y + scr->h) dy = y - (scr->y + scr->h);

		int dist = dx + dy;
		if (dist < min_dist) {
			min_dist = dist;
			nearest = scr;
		}
	}

	/* Clamp to nearest screen bounds */
	if (x < nearest->x) x = nearest->x;
	else if (x > nearest->x + nearest->w) x = nearest->x + nearest->w;

	if (y < nearest->y) y = nearest->y;
	else if (y > nearest->y + nearest->h) y = nearest->y + nearest->h;

	x -= nearest->x;
	y -= nearest->y;
	y = nearest->h - y;

	if (_x)
		*_x = x;
	if (_y)
		*_y = y;
	if (_scr)
		*_scr = nearest;
}

void osx_mouse_move(struct screen *scr, int x, int y)
{
	const int type = dragging ? kCGEventLeftMouseDragged : kCGEventMouseMoved;
	int cgx, cgy;
	int intended_x = x;
	int intended_y = y;
	int clamped_x = x;
	int clamped_y = y;

	int max_x = scr->w - 1;
	int max_y = scr->h - 1;

	if (clamped_x < 0)
		clamped_x = 0;
	else if (clamped_x > max_x)
		clamped_x = max_x;

	if (clamped_y < 0)
		clamped_y = 0;
	else if (clamped_y > max_y)
		clamped_y = max_y;

	int global_x = clamped_x + scr->x;
	int global_y = scr->y + max_y - clamped_y;
	int intended_global_x = intended_x + scr->x;
	int intended_global_y = scr->y + max_y - intended_y;

	int min_global_y = scr->y;
	int max_global_y = scr->y + max_y;
	int min_global_x = scr->x;
	int max_global_x = scr->x + max_x;

	if (intended_global_x < min_global_x)
		intended_global_x = min_global_x;
	else if (intended_global_x > max_global_x)
		intended_global_x = max_global_x;

	if (intended_global_y < min_global_y)
		intended_global_y = min_global_y;
	else if (intended_global_y > max_global_y)
		intended_global_y = max_global_y;

	/*
	 * CGEvents use a different coordinate system, so we have to convert between the
	 * two.
	 */

	NSPoint nspos = [NSEvent mouseLocation]; //LLO global coordinate system
	CGEventRef CGEv = CGEventCreate(NULL);
	CGPoint cgpos = CGEventGetLocation(CGEv); //ULO global coordinate system :(
	CFRelease(CGEv);

	cgx = global_x - nspos.x + cgpos.x;
	cgy = cgpos.y - (global_y - nspos.y);

	/*
	 * Calculate delta from actual cursor position to target position.
	 * This is crucial for edge-push detection (e.g., triggering auto-hide Dock).
	 */
	int64_t delta_x = intended_global_x - (int)nspos.x;
	int64_t delta_y = (int)nspos.y - intended_global_y;  /* Invert: LLO to CG delta direction */
	int edge_delta_x = 0;
	int edge_delta_y = 0;

	if (clamped_x == 0)
		edge_delta_x = -1;
	else if (clamped_x == max_x)
		edge_delta_x = 1;

	if (clamped_y == 0)
		edge_delta_y = -1;
	else if (clamped_y == max_y)
		edge_delta_y = 1;

	if (edge_delta_x)
		delta_x = edge_delta_x;
	if (edge_delta_y)
		delta_y = edge_delta_y;

	/*
	 * Create event source that mimics HID hardware events.
	 * This may help with system UI triggers like Dock auto-show.
	 */
	CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);

	CGPoint target = CGPointMake(cgx, cgy);
	CGPoint warp_target = target;
	uint64_t timestamp = monotonic_time_ns();

	CGWarpMouseCursorPosition(warp_target);

	CGEventRef ev = CGEventCreateMouseEvent(source, type, target, 0);

	CGEventSetFlags(ev, get_active_mod_flags());
	CGEventSetIntegerValueField(ev, kCGMouseEventDeltaX, delta_x);
	CGEventSetIntegerValueField(ev, kCGMouseEventDeltaY, delta_y);
	CGEventSetTimestamp(ev, timestamp);

	CGEventPost(kCGHIDEventTap, ev);
	CFRelease(ev);

	for (int i = 0; i < 3; i++) {
		CGEventRef settle =
		    CGEventCreateMouseEvent(source, type, target, 0);
		CGEventSetFlags(settle, get_active_mod_flags());
		CGEventSetIntegerValueField(settle, kCGMouseEventDeltaX, 0);
		CGEventSetIntegerValueField(settle, kCGMouseEventDeltaY, 0);
		CGEventSetTimestamp(settle, timestamp + 1000 + (i * 1000));
		CGEventPost(kCGHIDEventTap, settle);
		CFRelease(settle);
	}

	if (source) CFRelease(source);
}

void osx_mouse_hide()
{
	dispatch_sync(dispatch_get_main_queue(), ^{
		if (hider_timer)
			return;

		/*
		 * Our kludge only works until the mouse is placed over the dock
		 * or system toolbar, so we have to keep hiding the cursor :(.
		 */
		hider_timer =
		    [NSTimer scheduledTimerWithTimeInterval:0.001
						     target:[CursorHider alloc]
						   selector:@selector(hide)
						   userInfo:nil
						    repeats:true];
	});
}

void osx_mouse_show()
{
	dispatch_sync(dispatch_get_main_queue(), ^{
		int i;

		if (!hider_timer)
			return;

		[hider_timer invalidate];
		hider_timer = NULL;

		/* :( */
		for (i = 0; i < hide_depth; i++)
			CGDisplayShowCursor(kCGDirectMainDisplay);

		hide_depth = 0;
	});
}

void macos_init_mouse()
{
	/*
	 * Kludge to make background cursor setting work.
	 *
	 * Adapted from
	 * http://web.archive.org/web/20150609013355/http://lists.apple.com:80/archives/carbon-dev/2006/Jan/msg00555.html
	 */

	void CGSSetConnectionProperty(int, int, CFStringRef, CFBooleanRef);
	int _CGSDefaultConnection();
	CFStringRef propertyString;

	propertyString = CFStringCreateWithCString(
	    NULL, "SetsCursorInBackground", kCFStringEncodingUTF8);
	CGSSetConnectionProperty(_CGSDefaultConnection(),
				 _CGSDefaultConnection(), propertyString,
				 kCFBooleanTrue);
	CFRelease(propertyString);
}
