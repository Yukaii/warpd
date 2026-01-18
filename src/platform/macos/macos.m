/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "macos.h"
#include "ax_helpers.h"
#include "ax_menu.h"
#include "ax_debug.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Declare get_time_us from warpd.c - avoid including warpd.h to prevent conflicts */
extern uint64_t get_time_us(void);

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

#define APP_FLAG_CHROMIUM 1
#define APP_FLAG_ELECTRON 2

/*
 * Enable accessibility for apps that require explicit attribute setting.
 *
 * From https://balatero.com/writings/hammerspoon/retrieving-input-field-values-and-cursor-position-with-hammerspoon/:
 * - Chrome/Chromium: requires AXEnhancedUserInterface = true
 * - Electron apps: require AXManualAccessibility = true
 *
 * These attributes signal to the app that an assistive technology is present,
 * causing them to populate their full accessibility trees.
 */
static int enable_app_accessibility(AXUIElementRef app)
{
	if (!app)
		return 0;

	pid_t pid;
	if (AXUIElementGetPid(app, &pid) != kAXErrorSuccess)
		return 0;

	NSRunningApplication *runningApp =
		[NSRunningApplication runningApplicationWithProcessIdentifier:pid];
	if (!runningApp)
		return 0;

	NSString *bundleId = [runningApp bundleIdentifier];
	if (!bundleId)
		return 0;

	CFBooleanRef value = kCFBooleanTrue;

	int is_chromium = 0;
	int is_electron = 0;
	int flags = 0;

	/* Chrome and Chromium-based browsers need AXEnhancedUserInterface */
	static NSArray *chromiumBundleIds = nil;
	if (!chromiumBundleIds) {
		chromiumBundleIds = @[
			@"com.google.Chrome",
			@"com.google.Chrome.canary",
			@"org.chromium.Chromium",
			@"com.brave.Browser",
			@"com.microsoft.edgemac",
			@"com.vivaldi.Vivaldi",
			@"com.operasoftware.Opera",
		];
	}

	for (NSString *chromiumId in chromiumBundleIds) {
		if ([bundleId hasPrefix:chromiumId]) {
			is_chromium = 1;
			break;
		}
	}

	/* Electron apps need AXManualAccessibility */
	static NSArray *electronBundleIds = nil;
	if (!electronBundleIds) {
		electronBundleIds = @[
			@"com.electron.",           /* Generic Electron apps */
			@"com.github.Electron",     /* Electron framework */
			@"com.microsoft.VSCode",    /* VS Code */
			@"com.hnc.Discord",         /* Discord */
			@"com.slack.Slack",         /* Slack */
			@"com.spotify.client",      /* Spotify */
			@"com.tinyspeck.slackmacgap", /* Slack (older) */
			@"com.figma.Desktop",       /* Figma */
			@"com.notion.Notion",       /* Notion */
			@"com.linear.Linear",       /* Linear */
			@"com.obsidian.Obsidian",   /* Obsidian - Electron-based */
		];
	}

	for (NSString *electronId in electronBundleIds) {
		if ([bundleId hasPrefix:electronId]) {
			is_electron = 1;
			break;
		}
	}

	if (is_chromium) {
		AXUIElementSetAttributeValue(app,
			CFSTR("AXEnhancedUserInterface"), value);
		ax_debug_log("Enabled AXEnhancedUserInterface for: %s\n",
			[bundleId UTF8String]);
		flags |= APP_FLAG_CHROMIUM;
	}

	if (is_electron) {
		AXUIElementSetAttributeValue(app,
			CFSTR("AXManualAccessibility"), value);
		ax_debug_log("Enabled AXManualAccessibility for Electron app: %s\n",
			[bundleId UTF8String]);
		flags |= APP_FLAG_ELECTRON;
	}

	if (is_chromium || is_electron) {
		ax_debug_log("Accessibility attributes set for: %s\n",
			[bundleId UTF8String]);
	}

	return flags;
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

static int ax_role_matches(CFStringRef role)
{
	return CFEqual(role, kAXButtonRole) ||
	       CFEqual(role, kAXCheckBoxRole) ||
	       CFEqual(role, kAXRadioButtonRole) ||
	       CFEqual(role, kAXPopUpButtonRole) ||
	       CFEqual(role, kAXMenuItemRole) ||
	       CFEqual(role, kAXMenuBarItemRole) ||
	       CFEqual(role, kAXTabGroupRole) ||
	       CFEqual(role, kAXRowRole) ||
	       CFEqual(role, kAXCellRole) ||
	       CFEqual(role, ax_list_item_role()) ||
	       CFEqual(role, ax_link_role()) ||
	       CFEqual(role, ax_image_role()) ||
	       CFEqual(role, kAXTextFieldRole) ||
	       CFEqual(role, kAXTextAreaRole) ||
	       CFEqual(role, kAXStaticTextRole);
}

static int ax_actions_match(CFArrayRef actions)
{
	if (!actions)
		return 0;

	CFIndex count = CFArrayGetCount(actions);
	for (CFIndex i = 0; i < count; i++) {
		CFTypeRef action_ref = CFArrayGetValueAtIndex(actions, i);
		if (!action_ref || CFGetTypeID(action_ref) != CFStringGetTypeID())
			continue;
		CFStringRef action = (CFStringRef)action_ref;
		/* Check common actions including web-specific ones */
		if (CFEqual(action, kAXPressAction) ||
		    CFEqual(action, kAXShowMenuAction) ||
		    CFEqual(action, kAXConfirmAction) ||
		    CFEqual(action, kAXRaiseAction) ||
		    CFEqual(action, kAXPickAction) ||
		    CFEqual(action, kAXIncrementAction) ||
		    CFEqual(action, kAXDecrementAction) ||
		    CFEqual(action, kAXShowAlternateUIAction) ||
		    CFEqual(action, kAXShowDefaultUIAction) ||
#ifdef kAXShowDetailsAction
		    CFEqual(action, kAXShowDetailsAction) ||
#else
		    CFEqual(action, CFSTR("AXShowDetails")) ||
#endif
#ifdef kAXJumpAction
		    CFEqual(action, kAXJumpAction) ||
#else
		    CFEqual(action, CFSTR("AXJump")) ||
#endif
#ifdef kAXOpenAction
		    CFEqual(action, kAXOpenAction) ||
#else
		    CFEqual(action, CFSTR("AXOpen")) ||
#endif
		    CFEqual(action, CFSTR("AXScrollToVisible"))) {
			return 1;
		}
	}

	return 0;
}

static int ax_element_supports_action(AXUIElementRef element);

static int ax_parent_is_actionable(AXUIElementRef element)
{
	AXUIElementRef parent = NULL;
	CFTypeRef role = NULL;
	int matches = 0;

	if (!element)
		return 0;

	if (AXUIElementCopyAttributeValue(element, kAXParentAttribute,
					  (CFTypeRef *)&parent) != kAXErrorSuccess ||
	    !parent)
		return 0;

	if (AXUIElementCopyAttributeValue(parent, kAXRoleAttribute, &role) ==
		    kAXErrorSuccess && role) {
		if (CFGetTypeID(role) == CFStringGetTypeID())
			matches = ax_role_matches((CFStringRef)role);
		CFRelease(role);
	}

	if (!matches)
		matches = ax_element_supports_action(parent);

	CFRelease(parent);
	return matches;
}

static int ax_element_supports_action(AXUIElementRef element)
{
	CFArrayRef actions = NULL;

	if (!element)
		return 0;

	if (AXUIElementCopyActionNames(element, &actions) == kAXErrorSuccess &&
	    actions) {
		int matches = ax_actions_match(actions);
		CFRelease(actions);
		return matches;
	}

	CFTypeRef actions_ref = NULL;
	if (AXUIElementCopyAttributeValue(element, ax_actions_attribute(),
				      &actions_ref) != kAXErrorSuccess ||
	    !actions_ref)
		return 0;

	/* Validate it's actually an array */
	if (CFGetTypeID(actions_ref) != CFArrayGetTypeID()) {
		CFRelease(actions_ref);
		return 0;
	}

	actions = (CFArrayRef)actions_ref;
	int matches = ax_actions_match(actions);
	CFRelease(actions);
	return matches;
}

static int ax_string_contains(CFStringRef haystack, const char *needle)
{
	if (!haystack || !needle)
		return 0;

	CFStringRef needle_ref = CFStringCreateWithCString(
		kCFAllocatorDefault, needle, kCFStringEncodingUTF8);
	if (!needle_ref)
		return 0;

	CFRange found = CFStringFind(haystack, needle_ref,
				    kCFCompareCaseInsensitive);
	CFRelease(needle_ref);
	return found.location != kCFNotFound;
}

static int ax_element_has_string_attr(AXUIElementRef element, CFStringRef attr)
{
	CFTypeRef raw = NULL;

	if (!element)
		return 0;

	if (AXUIElementCopyAttributeValue(element, attr, &raw) != kAXErrorSuccess ||
	    !raw)
		return 0;

	int matches = 0;
	if (CFGetTypeID(raw) == CFStringGetTypeID()) {
		matches = CFStringGetLength((CFStringRef)raw) > 0;
	} else if (CFGetTypeID(raw) == CFURLGetTypeID()) {
		matches = 1;
	}

	CFRelease(raw);
	return matches;
}

static int ax_role_description_matches(AXUIElementRef element)
{
	CFTypeRef desc = NULL;
	int matches = 0;

	if (!element)
		return 0;

	if (AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute,
				      &desc) != kAXErrorSuccess ||
	    !desc)
		return 0;

	if (CFGetTypeID(desc) == CFStringGetTypeID()) {
		CFStringRef desc_str = (CFStringRef)desc;
		matches = ax_string_contains(desc_str, "link") ||
			  ax_string_contains(desc_str, "text") ||
			  ax_string_contains(desc_str, "button") ||
			  ax_string_contains(desc_str, "menu") ||
			  ax_string_contains(desc_str, "tab") ||
			  ax_string_contains(desc_str, "リンク") ||
			  ax_string_contains(desc_str, "テキスト") ||
			  ax_string_contains(desc_str, "ボタン") ||
			  ax_string_contains(desc_str, "メニュー") ||
			  ax_string_contains(desc_str, "タブ");
	}

	CFRelease(desc);
	return matches;
}

static int ax_element_is_interactable(AXUIElementRef element)
{
	CFTypeRef role = NULL;
	int enabled = 1;
	int hidden = 0;
	int matches = 0;
	int is_text_or_image = 0;
	int is_menu_container = 0;
	int menu_has_label = 0;

	if (!element)
		return 0;

	if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role) ==
		    kAXErrorSuccess && role) {
		if (CFGetTypeID(role) == CFStringGetTypeID()) {
			CFStringRef role_str = (CFStringRef)role;
			is_text_or_image =
				CFEqual(role_str, kAXStaticTextRole) ||
				CFEqual(role_str, ax_image_role());
			is_menu_container =
				CFEqual(role_str, ax_menu_role()) ||
				CFEqual(role_str, ax_menu_bar_role());
			matches = ax_role_matches((CFStringRef)role);
		}
		CFRelease(role);
	}

	if (!matches)
		matches = ax_element_supports_action(element);

	if (!matches)
		matches = ax_role_description_matches(element);

	if (!matches)
		matches = ax_element_has_string_attr(element, kAXValueAttribute) ||
			  ax_element_has_string_attr(element, kAXTitleAttribute) ||
			  ax_element_has_string_attr(element, kAXURLAttribute) ||
			  ax_element_has_string_attr(element, kAXHelpAttribute) ||
			  ax_element_has_string_attr(element, kAXDescriptionAttribute);

	if (!matches) {
		if (ax_debug_verbose())
			ax_debug_log_element(element, "SKIP", -1, -1);
		return 0;
	}

	if (is_menu_container) {
		menu_has_label =
			ax_element_has_string_attr(element, kAXTitleAttribute) ||
			ax_element_has_string_attr(element, kAXValueAttribute) ||
			ax_element_has_string_attr(element, kAXDescriptionAttribute) ||
			ax_element_has_string_attr(element, kAXHelpAttribute);
		if (!menu_has_label)
			return 0;
	}

	if (is_text_or_image && ax_parent_is_actionable(element))
		return 0;

	if (ax_get_bool_attr(element, kAXEnabledAttribute, &enabled) && !enabled)
		return 0;

	if (ax_get_bool_attr(element, kAXHiddenAttribute, &hidden) && hidden)
		return 0;

	return 1;
}

static void collect_interactable_hints(AXUIElementRef element, struct screen *scr,
					const CGRect *window_frame,
					struct hint *hints,
					size_t max_hints, size_t *count,
					uint64_t deadline_us,
					CFMutableSetRef visited);

static void collect_interactable_children(AXUIElementRef element,
					  CFStringRef attribute,
					  struct screen *scr,
					  const CGRect *window_frame,
					  struct hint *hints,
					  size_t max_hints, size_t *count,
					  uint64_t deadline_us,
					  CFMutableSetRef visited)
{
	CFTypeRef children_ref = NULL;

	if (AXUIElementCopyAttributeValue(element, attribute, &children_ref) !=
		kAXErrorSuccess || !children_ref)
		return;

	/* Validate it's actually an array */
	if (CFGetTypeID(children_ref) != CFArrayGetTypeID()) {
		CFRelease(children_ref);
		return;
	}

	CFArrayRef children = (CFArrayRef)children_ref;
	CFIndex child_count = CFArrayGetCount(children);
	for (CFIndex i = 0; i < child_count && *count < max_hints; i++) {
		if (deadline_us > 0 && get_time_us() >= deadline_us)
			break;
		CFTypeRef child_ref = CFArrayGetValueAtIndex(children, i);
		if (!child_ref)
			continue;
		/* Validate it's an AXUIElement before casting */
		if (CFGetTypeID(child_ref) != AXUIElementGetTypeID())
			continue;
		AXUIElementRef child = (AXUIElementRef)child_ref;
		collect_interactable_hints(child, scr, window_frame,
					  hints, max_hints, count, deadline_us, visited);
		if (*count >= max_hints)
			break;
	}

	CFRelease(children);
}

static void collect_interactable_hints(AXUIElementRef element, struct screen *scr,
					const CGRect *window_frame,
					struct hint *hints,
					size_t max_hints, size_t *count,
					uint64_t deadline_us,
					CFMutableSetRef visited)
{
	if (!element)
		return;

	if (*count >= max_hints)
		return;

	if (deadline_us > 0 && get_time_us() >= deadline_us)
		return;

	if (visited) {
		if (CFSetContainsValue(visited, element))
			return;
		CFSetAddValue(visited, element);
	}

	/* Log ALL elements when verbose mode is enabled */
	if (ax_debug_verbose())
		ax_debug_log_element(element, "VISIT", -1, -1);

	if (ax_element_is_interactable(element)) {
		int x;
		int y;

		if (ax_element_center_for_screen(element, scr, window_frame, &x, &y)) {
			/* Skip duplicate positions */
			if (ax_hint_position_exists(hints, *count, x, y)) {
				ax_debug_log_element(element, "DUP", x, y);
			} else {
				hints[*count].x = x;
				hints[*count].y = y;
				(*count)++;
				ax_debug_log_element(element, "HINT", x, y);
				if (*count >= max_hints)
					return;
			}
		} else {
			ax_debug_log_element(element, "OFFSCREEN", -1, -1);
		}
	}

	collect_interactable_children(element, kAXChildrenAttribute, scr,
					 window_frame, hints, max_hints, count, deadline_us, visited);
	if (*count >= max_hints)
		return;
	collect_interactable_children(element, ax_visible_children_attribute(), scr,
					 window_frame, hints, max_hints, count, deadline_us, visited);
	if (*count >= max_hints)
		return;
	collect_interactable_children(element, ax_children_in_navigation_order_attribute(),
					 scr, window_frame, hints, max_hints, count, deadline_us, visited);
	if (*count >= max_hints)
		return;
	collect_interactable_children(element, ax_contents_attribute(), scr,
					 window_frame, hints, max_hints, count, deadline_us, visited);
	if (*count >= max_hints)
		return;
	/* Try to collect tabs if the element has an AXTabs attribute (e.g., browser tabs) */
	collect_interactable_children(element, ax_tabs_attribute(), scr,
					 window_frame, hints, max_hints, count, deadline_us, visited);
}

/*
 * BFS version of hint collection - better for menu bars and web content
 * where we want breadth-first traversal to find items at similar depths.
 */
#define BFS_QUEUE_SIZE 4096

static void collect_hints_bfs(AXUIElementRef root, struct screen *scr,
			      const CGRect *window_frame,
			      struct hint *hints, size_t max_hints,
			      size_t *count, uint64_t deadline_us,
			      int skip_menu_containers,
			      int include_menu_attr)
{
	AXUIElementRef queue[BFS_QUEUE_SIZE];
	size_t queue_head = 0;
	size_t queue_tail = 0;

	if (!root)
		return;

	/* Enqueue root */
	CFRetain(root);
	queue[queue_tail++] = root;

	while (queue_head < queue_tail && *count < max_hints) {
		if (deadline_us > 0 && get_time_us() >= deadline_us)
			break;

		/* Dequeue */
		AXUIElementRef element = queue[queue_head++];

		/* Check if interactable */
		if (ax_element_is_interactable(element)) {
			int x, y;
			int add_hint = 1;

			if (skip_menu_containers &&
			    ax_element_is_menu_container(element))
				add_hint = 0;

			if (add_hint) {
				if (ax_element_center_for_screen(element, scr, window_frame,
								 &x, &y)) {
					/* Skip duplicate positions */
					if (ax_hint_position_exists(hints, *count, x, y)) {
						ax_debug_log_element(element, "MENU_DUP", x, y);
					} else {
						hints[*count].x = x;
						hints[*count].y = y;
						(*count)++;
						ax_debug_log_element(element, "MENU", x, y);
					}
				} else {
					ax_debug_log_element(element, "MENU_OFFSCREEN", -1, -1);
				}
			}
		}

		/* Enqueue children from multiple attributes */
		CFStringRef child_attrs[4];
		size_t attr_count = 3;

		child_attrs[0] = kAXChildrenAttribute;
		child_attrs[1] = ax_visible_children_attribute();
		child_attrs[2] = ax_children_in_navigation_order_attribute();
		if (include_menu_attr) {
			child_attrs[3] = ax_menu_attribute();
			attr_count = 4;
		}

		for (size_t attr_idx = 0; attr_idx < attr_count; attr_idx++) {
			CFTypeRef children_ref = NULL;
			if (AXUIElementCopyAttributeValue(element, child_attrs[attr_idx],
							  &children_ref) == kAXErrorSuccess &&
			    children_ref) {
				if (CFGetTypeID(children_ref) == CFArrayGetTypeID()) {
					CFArrayRef children = (CFArrayRef)children_ref;
					CFIndex child_count = CFArrayGetCount(children);
					for (CFIndex i = 0; i < child_count; i++) {
						if (queue_tail >= BFS_QUEUE_SIZE)
							break;
						CFTypeRef child_ref = CFArrayGetValueAtIndex(children, i);
						if (child_ref &&
						    CFGetTypeID(child_ref) == AXUIElementGetTypeID()) {
							CFRetain(child_ref);
							queue[queue_tail++] = (AXUIElementRef)child_ref;
						}
					}
				}
				CFRelease(children_ref);
			}
			if (queue_tail >= BFS_QUEUE_SIZE)
				break;
		}

		CFRelease(element);
	}

	/* Release remaining queued elements */
	while (queue_head < queue_tail) {
		CFRelease(queue[queue_head++]);
	}
}

static size_t collect_menu_phase(AXUIElementRef focused_app, struct screen *scr,
				 struct hint *hints, size_t max_hints,
				 int is_electron, int should_dump)
{
	size_t count = 0;
	int menu_deadline_ms = ax_env_int("WARPD_AX_MENU_DEADLINE_MS",
					  is_electron ? 200 : 100);
	int menu_open_deadline_ms =
		ax_env_int("WARPD_AX_MENU_OPEN_DEADLINE_MS", 300);
	int menu_retries = ax_env_int("WARPD_AX_MENU_RETRIES", 3);
	int menu_retry_delay_ms = ax_env_int("WARPD_AX_MENU_RETRY_DELAY_MS", 30);
	uint64_t menu_bar_deadline_us =
		get_time_us() + (uint64_t)menu_deadline_ms * 1000;
	uint64_t menu_deadline_us = menu_bar_deadline_us;

	if (menu_open_deadline_ms > menu_deadline_ms)
		menu_deadline_us =
			get_time_us() + (uint64_t)menu_open_deadline_ms * 1000;

	ax_debug_log("\n--- PHASE 1: Menu Bars (BFS, %dms deadline) ---\n",
		     menu_deadline_ms);

	/* App menu bar - traverse AXMenuBar items explicitly */
	AXUIElementRef menu_bar = NULL;
	if (AXUIElementCopyAttributeValue(focused_app, ax_menu_bar_attribute(),
				  (CFTypeRef *)&menu_bar) == kAXErrorSuccess &&
	    menu_bar) {
		if (should_dump)
			ax_debug_dump_tree(menu_bar, "app_menu_bar");
		ax_collect_menu_bar_hints(menu_bar, scr, hints, max_hints, &count,
					  menu_bar_deadline_us);
		CFRelease(menu_bar);
	}

	/* System menu bar (Apple menu, status items) - explicit traversal */
	if (count < max_hints && get_time_us() < menu_bar_deadline_us) {
		AXUIElementRef system = AXUIElementCreateSystemWide();
		if (system) {
			menu_bar = NULL;
			if (AXUIElementCopyAttributeValue(system, ax_menu_bar_attribute(),
						  (CFTypeRef *)&menu_bar) == kAXErrorSuccess &&
			    menu_bar) {
				if (should_dump)
					ax_debug_dump_tree(menu_bar, "system_menu_bar");
				ax_collect_menu_bar_hints(menu_bar, scr, hints, max_hints,
							  &count, menu_bar_deadline_us);
				CFRelease(menu_bar);
			}
			CFRelease(system);
		}
	}

	size_t menu_bar_count = count;
	struct hint *menu_bar_hints = NULL;
	struct hint *best_menu_hints = NULL;
	size_t best_menu_count = menu_bar_count;

	menu_bar_hints = ax_alloc_hints(max_hints);
	best_menu_hints = ax_alloc_hints(max_hints);
	if (!menu_bar_hints || !best_menu_hints) {
		free(menu_bar_hints);
		free(best_menu_hints);
		return count;
	}

	memcpy(menu_bar_hints, hints, sizeof(struct hint) * menu_bar_count);
	memcpy(best_menu_hints, hints, sizeof(struct hint) * menu_bar_count);

	for (int attempt = 0;
	     attempt < menu_retries && best_menu_count < max_hints &&
	     get_time_us() < menu_deadline_us;
	     attempt++) {
		size_t candidate_count = 0;
		struct hint *candidate_hints = NULL;
		int saw_menu = 0;
		size_t bar_candidate_count = 0;
		struct hint *bar_candidate_hints = NULL;

		candidate_hints = ax_alloc_hints(max_hints);
		bar_candidate_hints = ax_alloc_hints(max_hints);
		if (!candidate_hints || !bar_candidate_hints) {
			free(candidate_hints);
			free(bar_candidate_hints);
			break;
		}

		if (attempt > 0 && menu_retry_delay_ms > 0)
			usleep((useconds_t)menu_retry_delay_ms * 1000);

		if (get_time_us() < menu_deadline_us) {
			AXUIElementRef temp_focused = NULL;
			AXUIElementRef temp_menu_root = NULL;
			AXUIElementRef temp_menu_direct = NULL;
			char focused_title[256];
			focused_title[0] = 0;
			if (AXUIElementCopyAttributeValue(
				focused_app, ax_focused_ui_element_attribute(),
				(CFTypeRef *)&temp_focused) == kAXErrorSuccess &&
			    temp_focused) {
				ax_menu_bar_item_title(temp_focused, focused_title,
						       sizeof focused_title);
				temp_menu_direct = ax_menu_from_menu_bar_item(temp_focused);
				temp_menu_root = temp_menu_direct ?
					temp_menu_direct :
					ax_menu_root_for_element(temp_focused);
				if (temp_menu_root) {
					size_t local_count = menu_bar_count;
					struct hint *local_hints = NULL;
					saw_menu = 1;
					local_hints = ax_alloc_hints(max_hints);
					if (!local_hints) {
						CFRelease(temp_menu_root);
						CFRelease(temp_focused);
						free(candidate_hints);
						free(bar_candidate_hints);
						goto menu_loop_cleanup;
					}
					if (!ax_menu_root_matches_title(temp_menu_root,
								        focused_title)) {
						CFRelease(temp_menu_root);
						CFRelease(temp_focused);
						free(local_hints);
						continue;
					}
					if (menu_open_deadline_ms > menu_deadline_ms) {
						uint64_t extended =
							get_time_us() + (uint64_t)menu_open_deadline_ms * 1000;
						if (extended > menu_deadline_us)
							menu_deadline_us = extended;
					}
					if (should_dump)
						ax_debug_dump_tree(temp_menu_root, temp_menu_direct ?
								  "menu_root_focus_direct" : "menu_root");
					memcpy(local_hints, menu_bar_hints,
					       sizeof(struct hint) * menu_bar_count);
					ax_collect_menu_hints_with_poll(
					    temp_menu_root, scr, local_hints, max_hints,
					    &local_count, menu_deadline_us,
					    collect_hints_bfs);
					if (local_count >= candidate_count) {
						memcpy(candidate_hints, local_hints,
						       sizeof(struct hint) * local_count);
						candidate_count = local_count;
					}
					free(local_hints);
				}
				if (temp_menu_root)
					CFRelease(temp_menu_root);
				CFRelease(temp_focused);
			}
		}

		if (get_time_us() < menu_deadline_us) {
			AXUIElementRef system = AXUIElementCreateSystemWide();
			if (system) {
				AXUIElementRef sys_focused = NULL;
				AXUIElementRef sys_menu_root = NULL;
				AXUIElementRef sys_menu_direct = NULL;
				char sys_focused_title[256];
				sys_focused_title[0] = 0;
				if (AXUIElementCopyAttributeValue(
					system, ax_focused_ui_element_attribute(),
					(CFTypeRef *)&sys_focused) == kAXErrorSuccess &&
				    sys_focused) {
					ax_menu_bar_item_title(sys_focused, sys_focused_title,
							       sizeof sys_focused_title);
					sys_menu_direct = ax_menu_from_menu_bar_item(sys_focused);
					sys_menu_root = sys_menu_direct ?
						sys_menu_direct :
						ax_menu_root_for_element(sys_focused);
					if (sys_menu_root) {
						size_t local_count = menu_bar_count;
						struct hint *local_hints = NULL;
						saw_menu = 1;
						local_hints = ax_alloc_hints(max_hints);
						if (!local_hints) {
							CFRelease(sys_menu_root);
							CFRelease(sys_focused);
							free(candidate_hints);
							free(bar_candidate_hints);
							goto menu_loop_cleanup;
						}
						if (!ax_menu_root_matches_title(sys_menu_root,
									        sys_focused_title)) {
							CFRelease(sys_menu_root);
							CFRelease(sys_focused);
							free(local_hints);
							continue;
						}
						if (menu_open_deadline_ms > menu_deadline_ms) {
							uint64_t extended =
								get_time_us() + (uint64_t)menu_open_deadline_ms * 1000;
							if (extended > menu_deadline_us)
								menu_deadline_us = extended;
						}
						if (should_dump)
							ax_debug_dump_tree(sys_menu_root, sys_menu_direct ?
									  "menu_root_system_direct" :
									  "menu_root_system");
						memcpy(local_hints, menu_bar_hints,
						       sizeof(struct hint) * menu_bar_count);
						ax_collect_menu_hints_with_poll(
						    sys_menu_root, scr, local_hints, max_hints,
						    &local_count, menu_deadline_us,
						    collect_hints_bfs);
						if (local_count > candidate_count) {
							memcpy(candidate_hints, local_hints,
							       sizeof(struct hint) * local_count);
							candidate_count = local_count;
						}
						free(local_hints);
					}
				}
				if (sys_menu_root)
					CFRelease(sys_menu_root);
				if (sys_focused)
					CFRelease(sys_focused);
				CFRelease(system);
			}
		}

		if (get_time_us() < menu_deadline_us) {
			bar_candidate_count = ax_collect_menu_hints_from_menu_bar(
				focused_app, scr, menu_bar_hints, menu_bar_count,
				max_hints, bar_candidate_hints, menu_deadline_us,
				collect_hints_bfs);
			if (bar_candidate_count > 0) {
				saw_menu = 1;
				if (bar_candidate_count > candidate_count) {
					memcpy(candidate_hints, bar_candidate_hints,
					       sizeof(struct hint) * bar_candidate_count);
					candidate_count = bar_candidate_count;
				}
			}
		}

		if (candidate_count > best_menu_count) {
			memcpy(best_menu_hints, candidate_hints,
			       sizeof(struct hint) * candidate_count);
			best_menu_count = candidate_count;
		}

menu_loop_cleanup:
		free(candidate_hints);
		free(bar_candidate_hints);

		if (saw_menu && candidate_count == best_menu_count)
			break;
	}

	if (best_menu_count != menu_bar_count) {
		memcpy(hints, best_menu_hints, sizeof(struct hint) * best_menu_count);
		count = best_menu_count;
	}

	free(menu_bar_hints);
	free(best_menu_hints);

	return count;
}

static size_t collect_window_phase(AXUIElementRef focused_app, struct screen *scr,
				   struct hint *hints, size_t max_hints,
				   size_t count, int is_electron,
				   int should_dump)
{
	AXError error;
	AXUIElementRef focused_element = NULL;

	if (AXUIElementCopyAttributeValue(
		focused_app, ax_focused_ui_element_attribute(),
		(CFTypeRef *)&focused_element) != kAXErrorSuccess) {
		focused_element = NULL;
	}

	/*
	 * Now scan window content with DFS and a longer deadline.
	 * DFS works better for deep trees like web content.
	 */
	int window_deadline_ms = ax_env_int("WARPD_AX_WINDOW_DEADLINE_MS",
					    is_electron ? 1500 : 500);
	int window_bfs_deadline_ms = ax_env_int("WARPD_AX_WINDOW_BFS_DEADLINE_MS",
						is_electron ? 250 : 0);
	uint64_t deadline_us =
		get_time_us() + (uint64_t)window_deadline_ms * 1000;

	ax_debug_log("\n--- PHASE 2: Window Content (DFS, %dms deadline) ---\n",
		     window_deadline_ms);

	CFMutableSetRef visited =
		CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks);

	AXUIElementRef focused_window = NULL;
	error = AXUIElementCopyAttributeValue(
		focused_app, kAXFocusedWindowAttribute, (CFTypeRef *)&focused_window);

	if (error == kAXErrorSuccess && focused_window) {
		/*
		 * NOTE: We pass NULL for window_frame to avoid clipping tabs and other
		 * title bar elements. Some apps (like Chrome) have tabs in the unified
		 * title bar area, which may be reported outside the window's content
		 * frame. Screen bounds clipping still applies.
		 */
		if (should_dump)
			ax_debug_dump_tree(focused_window, "focused_window");
		if (window_bfs_deadline_ms > 0) {
			uint64_t bfs_deadline_us =
				get_time_us() + (uint64_t)window_bfs_deadline_ms * 1000;
			ax_debug_log("\n--- PHASE 2.1: Window Content (BFS, %dms deadline) ---\n",
				     window_bfs_deadline_ms);
			collect_hints_bfs(focused_window, scr, NULL,
					  hints, max_hints, &count, bfs_deadline_us, 0, 0);
		}
		collect_interactable_hints(focused_window, scr, NULL,
				  hints, max_hints, &count, deadline_us, visited);
		CFRelease(focused_window);

	} else {
		/* Fallback: scan all windows if no focused window */
		CFArrayRef windows = NULL;
		error = AXUIElementCopyAttributeValue(
			focused_app, kAXWindowsAttribute, (CFTypeRef *)&windows);
		if (error == kAXErrorSuccess && windows) {
			CFIndex window_count = CFArrayGetCount(windows);
			for (CFIndex i = 0; i < window_count && count < max_hints; i++) {
				AXUIElementRef window =
				    (AXUIElementRef)CFArrayGetValueAtIndex(windows, i);
				/* No frame clipping - screen bounds still apply */
				if (should_dump)
					ax_debug_dump_tree(window, "window");
				collect_interactable_hints(window, scr, NULL,
						  hints, max_hints, &count,
						  deadline_us, visited);
			}

			CFRelease(windows);
		}
	}

	/* Also check focused UI element for additional hints */
	if (count < max_hints && get_time_us() < deadline_us) {
		if (focused_element) {
			if (should_dump)
				ax_debug_dump_tree(focused_element, "focused_element");
			collect_interactable_hints(focused_element, scr, NULL,
					  hints, max_hints, &count,
					  deadline_us, visited);
		}
	}

	if (focused_element)
		CFRelease(focused_element);

	if (visited)
		CFRelease(visited);

	return count;
}

size_t osx_collect_interactable_hints(struct screen *scr, struct hint *hints,
				      size_t max_hints)
{
	if (!AXIsProcessTrusted())
		return 0;

	AXUIElementRef focused_app = get_focused_app();
	if (!focused_app)
		return 0;

	/* Initialize debug logging if enabled */
	ax_debug_open();

	/* Enable accessibility for apps that need explicit attribute setting */
	int app_flags = enable_app_accessibility(focused_app);
	int is_electron = (app_flags & APP_FLAG_ELECTRON) != 0;

	ax_debug_log("=== Starting hint collection (max=%zu) ===\n", max_hints);

	size_t count = 0;
	int should_dump = ax_debug_dump_enabled();

	/*
	 * Scan menu bars FIRST using BFS - this ensures we get all top-level
	 * menu items (File, Edit, View, etc.) before diving into submenus.
	 */
	count = collect_menu_phase(focused_app, scr, hints, max_hints,
				   is_electron, should_dump);

	count = collect_window_phase(focused_app, scr, hints, max_hints, count,
				     is_electron, should_dump);

	CFRelease(focused_app);

	ax_debug_log("=== Hint collection complete: %zu hints found ===\n\n", count);
	ax_debug_close();

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
