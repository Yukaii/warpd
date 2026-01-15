/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "macos.h"
#include <math.h>

static NSDictionary *get_font_attrs(const char *family, NSColor *color, int h)
{
	NSDictionary *attrs;

	int ptsz = h;
	CGSize size;
	do {
		NSFont *font =
		    [NSFont fontWithName:[NSString stringWithUTF8String:family]
				    size:ptsz];
		if (!font) {
			fprintf(stderr, "ERROR: %s is not a valid font\n",
				family);
			exit(-1);
		}
		attrs = @{
			NSFontAttributeName : font,
			NSForegroundColorAttributeName : color,
		};
		size = [@"m" sizeWithAttributes:attrs];
		ptsz--;
	} while (size.height > h);

	return attrs;
}

void macos_draw_text(struct screen *scr, NSColor *col, const char *font,
		     int x, int y, int w,
		     int h, const char *s)
{

	NSDictionary *attrs = get_font_attrs(font, col, h);
	NSString *str = [NSString stringWithUTF8String:s];
	CGSize size = [str sizeWithAttributes:attrs];

	x += (w - size.width)/2;

	y += size.height + (h - size.height)/2;

	/* Convert to LLO */
	y = scr->h - y;

	[str drawAtPoint:NSMakePoint((float)x, (float)y) withAttributes: attrs];
}

void macos_draw_box(struct screen *scr, NSColor *col, float x, float y, float w, float h, float r)
{
	[col setFill];

	/* Convert to LLO */
	y = scr->h - y - h;

	NSBezierPath *path = [NSBezierPath
	    bezierPathWithRoundedRect:NSMakeRect((float)x, (float)y, (float)w,
					 (float)h)
			      xRadius:(float)r
			      yRadius:(float)r];
	[path fill];
}

void macos_draw_box_outline(struct screen *scr, NSColor *col, float x, float y, float w, float h, float r, float line_width)
{
	[col setStroke];

	/* Convert to LLO */
	y = scr->h - y - h;

	NSBezierPath *path = [NSBezierPath
	    bezierPathWithRoundedRect:NSMakeRect((float)x, (float)y, (float)w,
					 (float)h)
			      xRadius:(float)r
			      yRadius:(float)r];
	[path setLineWidth:line_width];
	[path stroke];
}


void macos_draw_circle(struct screen *scr, NSColor *col, float x, float y, float radius, float lineWidth)
{
	[col setStroke];

	/* Convert to LLO - for circles we need to center correctly */
	y = scr->h - y;

	NSBezierPath *path = [NSBezierPath bezierPath];
	[path appendBezierPathWithOvalInRect:NSMakeRect(x - radius, y - radius, radius * 2, radius * 2)];
	[path setLineWidth:lineWidth];
	[path stroke];
}

NSColor *nscolor_from_hex(const char *str)
{
	ssize_t len;
	uint8_t r, g, b, a;
#define X2B(c) ((c >= '0' && c <= '9') ? (c & 0xF) : (((c | 0x20) - 'a') + 10))

	if (str == NULL)
		return 0;

	str = (*str == '#') ? str + 1 : str;
	len = strlen(str);

	if (len != 6 && len != 8) {
		fprintf(stderr, "Failed to parse %s, paint it black!\n", str);
		return NSColor.blackColor;
	}

	r = X2B(str[0]);
	r <<= 4;
	r |= X2B(str[1]);

	g = X2B(str[2]);
	g <<= 4;
	g |= X2B(str[3]);

	b = X2B(str[4]);
	b <<= 4;
	b |= X2B(str[5]);

	a = 255;
	if (len == 8) {
		a = X2B(str[6]);
		a <<= 4;
		a |= X2B(str[7]);
	}

	return [NSColor colorWithCalibratedRed:(float)r / 255
					 green:(float)g / 255
					  blue:(float)b / 255
					 alpha:(float)a / 255];
}

/* Returns the focused application. Caller must CFRelease the result. */
static AXUIElementRef get_focused_app(void)
{
	AXUIElementRef systemWideElement = AXUIElementCreateSystemWide();
	if (!systemWideElement)
		return NULL;

	AXUIElementRef focusedApp = NULL;
	AXUIElementCopyAttributeValue(
		systemWideElement, kAXFocusedApplicationAttribute, (CFTypeRef *)&focusedApp);
	CFRelease(systemWideElement);

	return focusedApp;
}

static int is_focused_app_kitty(void)
{
	AXUIElementRef focusedApp = get_focused_app();
	if (!focusedApp)
		return 0;

	pid_t pid;
	AXError error = AXUIElementGetPid(focusedApp, &pid);
	CFRelease(focusedApp);

	if (error != kAXErrorSuccess)
		return 0;

	NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
	if (!app)
		return 0;

	NSString *bundleId = [app bundleIdentifier];
	if (bundleId && [bundleId isEqualToString:@"net.kovidgoyal.kitty"])
		return 1;

	return 0;
}

static CFStringRef get_selected_text_via_accessibility(void)
{
	AXUIElementRef focusedApp = get_focused_app();
	if (!focusedApp)
		return NULL;

	AXUIElementRef focusedElement = NULL;
	AXError error = AXUIElementCopyAttributeValue(
		focusedApp, kAXFocusedUIElementAttribute, (CFTypeRef *)&focusedElement);
	CFRelease(focusedApp);

	if (error != kAXErrorSuccess || !focusedElement)
		return NULL;

	CFStringRef selectedText = NULL;
	error = AXUIElementCopyAttributeValue(
		focusedElement, kAXSelectedTextAttribute, (CFTypeRef *)&selectedText);
	CFRelease(focusedElement);

	if (error != kAXErrorSuccess)
		return NULL;

	return selectedText;
}

static int write_to_clipboard(CFStringRef text)
{
	if (!text)
		return 0;

	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard clearContents];

	NSString *nsText = (__bridge NSString *)text;
	return [pasteboard setString:nsText forType:NSPasteboardTypeString] ? 1 : 0;
}

static int copy_via_accessibility(void)
{
	CFStringRef selectedText = get_selected_text_via_accessibility();
	if (!selectedText || CFStringGetLength(selectedText) == 0) {
		if (selectedText) CFRelease(selectedText);
		return 0;
	}

	int result = write_to_clipboard(selectedText);
	CFRelease(selectedText);
	return result;
}

void osx_copy_selection()
{
	/*
	 * For Kitty terminal with non-Latin keyboard layouts:
	 * Kitty's keyboard protocol interprets keycodes based on current layout,
	 * causing synthetic Cmd+C to produce wrong characters. Use Accessibility
	 * API to read selected text directly and write to clipboard.
	 */
	if (is_focused_app_kitty()) {
		if (copy_via_accessibility())
			return;
		fprintf(stderr, "warpd: Accessibility-based copy failed, falling back\n");
	}

	/* Standard approach for non-Kitty terminals */
	send_key(56, 1);  /* Command down */
	send_key(9, 1);   /* 'c' down */
	send_key(56, 0);  /* Command up (released before 'c' to match original) */
	send_key(9, 0);   /* 'c' up */
}

static int ax_get_bool_attr(AXUIElementRef element, CFStringRef attr, int *value)
{
	CFTypeRef raw = NULL;
	AXError error = AXUIElementCopyAttributeValue(element, attr, &raw);

	if (error != kAXErrorSuccess || !raw)
		return 0;

	if (CFGetTypeID(raw) == CFBooleanGetTypeID()) {
		*value = CFBooleanGetValue((CFBooleanRef)raw);
		CFRelease(raw);
		return 1;
	}

	CFRelease(raw);
	return 0;
}

static CFStringRef ax_link_role(void)
{
#ifdef kAXLinkRole
	return kAXLinkRole;
#else
	return CFSTR("AXLink");
#endif
}

static int ax_role_matches(CFStringRef role)
{
	return CFEqual(role, kAXButtonRole) ||
	       CFEqual(role, kAXCheckBoxRole) ||
	       CFEqual(role, kAXRadioButtonRole) ||
	       CFEqual(role, kAXPopUpButtonRole) ||
	       CFEqual(role, ax_link_role()) ||
	       CFEqual(role, kAXTextFieldRole) ||
	       CFEqual(role, kAXTextAreaRole) ||
	       CFEqual(role, kAXStaticTextRole);
}

static int ax_element_is_interactable(AXUIElementRef element)
{
	CFTypeRef role = NULL;
	int enabled = 1;
	int hidden = 0;

	if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role) !=
		    kAXErrorSuccess ||
	    !role) {
		return 0;
	}

	int matches = ax_role_matches((CFStringRef)role);
	CFRelease(role);

	if (!matches)
		return 0;

	if (ax_get_bool_attr(element, kAXEnabledAttribute, &enabled) && !enabled)
		return 0;

	if (ax_get_bool_attr(element, kAXHiddenAttribute, &hidden) && hidden)
		return 0;

	return 1;
}

static int ax_get_position_size(AXUIElementRef element, CGPoint *position,
					CGSize *size)
{
	AXValueRef position_value = NULL;
	AXValueRef size_value = NULL;

	if (AXUIElementCopyAttributeValue(element, kAXPositionAttribute,
				      (CFTypeRef *)&position_value) != kAXErrorSuccess ||
	    !position_value)
		return 0;

	if (!AXValueGetValue(position_value, kAXValueCGPointType, position)) {
		CFRelease(position_value);
		return 0;
	}

	CFRelease(position_value);

	if (AXUIElementCopyAttributeValue(element, kAXSizeAttribute,
				      (CFTypeRef *)&size_value) != kAXErrorSuccess ||
	    !size_value)
		return 0;

	if (!AXValueGetValue(size_value, kAXValueCGSizeType, size)) {
		CFRelease(size_value);
		return 0;
	}

	CFRelease(size_value);
	return 1;
}

static int ax_element_center_for_screen(AXUIElementRef element, struct screen *scr,
					const CGRect *window_frame,
					int *center_x, int *center_y)
{
	CGPoint position = CGPointZero;
	CGSize size = CGSizeZero;
	float local_x;
	float local_y;

	if (!ax_get_position_size(element, &position, &size))
		return 0;

	if (size.width <= 0 || size.height <= 0)
		return 0;

	float global_x = position.x + size.width / 2.0f;
	float global_y = position.y + size.height / 2.0f;

	if (window_frame) {
		if (global_x < window_frame->origin.x ||
		    global_x > (window_frame->origin.x + window_frame->size.width) ||
		    global_y < window_frame->origin.y ||
		    global_y > (window_frame->origin.y + window_frame->size.height))
			return 0;
	}

	if (global_x < scr->x || global_x > (scr->x + scr->w) ||
	    global_y < scr->y || global_y > (scr->y + scr->h))
		return 0;

	local_x = global_x - scr->x;
	local_y = global_y - scr->y;

	*center_x = (int)lroundf(local_x);
	*center_y = (int)lroundf(local_y);
	return 1;
}

static void collect_interactable_hints(AXUIElementRef element, struct screen *scr,
					const CGRect *window_frame,
					struct hint *hints,
					size_t max_hints, size_t *count)
{
	if (*count >= max_hints)
		return;

	if (ax_element_is_interactable(element)) {
		int x;
		int y;

		if (ax_element_center_for_screen(element, scr, window_frame, &x, &y)) {
			hints[*count].x = x;
			hints[*count].y = y;
			(*count)++;
			if (*count >= max_hints)
				return;
		}
	}

	CFArrayRef children = NULL;
	if (AXUIElementCopyAttributeValue(element, kAXChildrenAttribute,
					 (CFTypeRef *)&children) == kAXErrorSuccess && children) {
		CFIndex child_count = CFArrayGetCount(children);
		for (CFIndex i = 0; i < child_count && *count < max_hints; i++) {
			AXUIElementRef child =
			    (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
			collect_interactable_hints(child, scr, window_frame,
						  hints, max_hints, count);
		}
		CFRelease(children);
	}
}

size_t osx_collect_interactable_hints(struct screen *scr, struct hint *hints,
				      size_t max_hints)
{
	if (!AXIsProcessTrusted())
		return 0;

	AXUIElementRef focused_app = get_focused_app();
	if (!focused_app)
		return 0;

	size_t count = 0;
	AXUIElementRef focused_window = NULL;
	AXError error = AXUIElementCopyAttributeValue(
		focused_app, kAXFocusedWindowAttribute, (CFTypeRef *)&focused_window);

	if (error == kAXErrorSuccess && focused_window) {
		CGRect window_frame = CGRectZero;
		CGPoint position = CGPointZero;
		CGSize size = CGSizeZero;
		const CGRect *frame_ptr = NULL;

		if (ax_get_position_size(focused_window, &position, &size)) {
			window_frame = CGRectMake(position.x, position.y, size.width, size.height);
			frame_ptr = &window_frame;
		}

		collect_interactable_hints(focused_window, scr, frame_ptr,
					  hints, max_hints, &count);
		CFRelease(focused_window);
	} else {
		CFArrayRef windows = NULL;
		error = AXUIElementCopyAttributeValue(
			focused_app, kAXWindowsAttribute, (CFTypeRef *)&windows);
		if (error == kAXErrorSuccess && windows) {
			CFIndex window_count = CFArrayGetCount(windows);
			for (CFIndex i = 0; i < window_count && count < max_hints; i++) {
				AXUIElementRef window =
				    (AXUIElementRef)CFArrayGetValueAtIndex(windows, i);
				CGRect window_frame = CGRectZero;
				CGPoint position = CGPointZero;
				CGSize size = CGSizeZero;
				const CGRect *frame_ptr = NULL;

				if (ax_get_position_size(window, &position, &size)) {
					window_frame = CGRectMake(position.x, position.y,
								 size.width, size.height);
					frame_ptr = &window_frame;
				}

				collect_interactable_hints(window, scr, frame_ptr,
							  hints, max_hints, &count);
			}
			CFRelease(windows);
		}
	}

	CFRelease(focused_app);
	return count;
}

void osx_scroll(int direction)
{
	int y = 0;
	int x = 0;

	switch (direction) {
	case SCROLL_UP:
		y = 1;
		break;
	case SCROLL_DOWN:
		y = -1;
		break;
	case SCROLL_RIGHT:
		x = -1;
		break;
	case SCROLL_LEFT:
		x = 1;
		break;
	}

	CGEventRef ev = CGEventCreateScrollWheelEvent(
	    NULL, kCGScrollEventUnitPixel, 2, y, x);
	CGEventPost(kCGHIDEventTap, ev);
}

void osx_scroll_amount(int direction, int amount)
{
	int y = 0;
	int x = 0;

	switch (direction) {
	case SCROLL_UP:
		y = amount;
		break;
	case SCROLL_DOWN:
		y = -amount;
		break;
	case SCROLL_RIGHT:
		x = -amount;
		break;
	case SCROLL_LEFT:
		x = amount;
		break;
	}

	CGEventRef ev = CGEventCreateScrollWheelEvent(
	    NULL, kCGScrollEventUnitPixel, 2, y, x);
	CGEventPost(kCGHIDEventTap, ev);
}

void osx_commit()
{
	dispatch_sync(dispatch_get_main_queue(), ^{
		size_t i;
		for (i = 0; i < nr_screens; i++) {
			struct window *win = screens[i].overlay;

			if (win->nr_hooks)
				window_show(win);
			else
				window_hide(win);
		}
	});
}

static void *mainloop(void *arg)
{
	int (*main)(struct platform *platform) = (int (*)(struct platform *platform)) arg;
	struct platform platform = {
		.commit = osx_commit,
		.copy_selection = osx_copy_selection,
		.hint_draw = osx_hint_draw,
		.collect_interactable_hints = osx_collect_interactable_hints,
		.init_hint = osx_init_hint,
		.input_grab_keyboard = osx_input_grab_keyboard,
		.input_lookup_code = osx_input_lookup_code,
		.input_lookup_name = osx_input_lookup_name,
		.input_code_to_qwerty = osx_input_code_to_qwerty,
		.input_qwerty_to_code = osx_input_qwerty_to_code,
		.input_special_to_code = osx_input_special_to_code,
		.input_next_event = osx_input_next_event,
		.input_ungrab_keyboard = osx_input_ungrab_keyboard,
		.input_wait = osx_input_wait,
		.mouse_click = osx_mouse_click,
		.mouse_down = osx_mouse_down,
		.mouse_get_position = osx_mouse_get_position,
		.mouse_hide = osx_mouse_hide,
		.mouse_move = osx_mouse_move,
		.mouse_show = osx_mouse_show,
		.mouse_up = osx_mouse_up,
		.screen_clear = osx_screen_clear,
		.screen_clear_ripples = osx_screen_clear_ripples,
		.screen_draw_box = osx_screen_draw_box,
		.screen_draw_cursor = osx_screen_draw_cursor,
		.screen_get_dimensions = osx_screen_get_dimensions,
		.screen_list = osx_screen_list,
		.scroll = osx_scroll,
		.scroll_amount = osx_scroll_amount,
		.key_tap = osx_key_tap,
		.trigger_ripple = osx_trigger_ripple,
		.has_active_ripples = osx_has_active_ripples,
		.screen_draw_halo = osx_screen_draw_halo,
		.trigger_entry_pulse = osx_trigger_entry_pulse,
		.has_active_entry_pulse = osx_has_active_entry_pulse,
		.monitor_file = osx_monitor_file,
	};

	main(&platform);
	exit(0);
}


void platform_run(int (*main)(struct platform *platform))
{
	pthread_t thread;

	[NSApplication sharedApplication];
	[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

	macos_init_input();
	macos_init_mouse();
	macos_init_screen();

	pthread_create(&thread, NULL, mainloop, (void *)main);

	[NSApp run];
}
