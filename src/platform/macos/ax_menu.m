/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "ax_menu.h"
#include "ax_debug.h"
#include "ax_helpers.h"
#include "macos.h"
#include <ctype.h>
#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Declare get_time_us from warpd.c - avoid including warpd.h */
extern uint64_t get_time_us(void);

int ax_menu_bar_item_title(AXUIElementRef element, char *out, size_t out_len)
{
	CFTypeRef role = NULL;
	int is_menu_bar_item = 0;

	if (!element || !out || out_len == 0)
		return 0;

	out[0] = 0;
	if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role) ==
		    kAXErrorSuccess && role) {
		if (CFGetTypeID(role) == CFStringGetTypeID())
			is_menu_bar_item =
				CFEqual((CFStringRef)role, ax_menu_bar_item_role());
		CFRelease(role);
	}

	if (!is_menu_bar_item)
		return 0;

	if (ax_copy_string_attr(element, kAXTitleAttribute, out, out_len))
		return 1;

	if (ax_copy_string_attr(element, kAXValueAttribute, out, out_len))
		return 1;

	return 0;
}

int ax_menu_root_matches_title(AXUIElementRef menu_root, const char *title)
{
	char root_title[256];

	if (!menu_root || !title || !title[0])
		return 1;

	if (!ax_copy_string_attr(menu_root, kAXTitleAttribute,
				 root_title, sizeof root_title))
		return 1;

	if (strcmp(root_title, title) == 0)
		return 1;

	/* Fuzzy match to avoid missing menus with slightly different titles. */
	size_t root_len = strlen(root_title);
	size_t title_len = strlen(title);
	if (!root_len || !title_len)
		return 1;

	for (size_t i = 0; i + title_len <= root_len; i++) {
		size_t j = 0;
		for (; j < title_len; j++) {
			if (tolower((unsigned char)root_title[i + j]) !=
			    tolower((unsigned char)title[j]))
				break;
		}
		if (j == title_len)
			return 1;
	}

	for (size_t i = 0; i + root_len <= title_len; i++) {
		size_t j = 0;
		for (; j < root_len; j++) {
			if (tolower((unsigned char)title[i + j]) !=
			    tolower((unsigned char)root_title[j]))
				break;
		}
		if (j == root_len)
			return 1;
	}

	return 0;
}

int ax_element_is_menu_container(AXUIElementRef element)
{
	CFTypeRef role = NULL;
	int is_menu = 0;

	if (!element)
		return 0;

	if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role) ==
		    kAXErrorSuccess && role) {
		if (CFGetTypeID(role) == CFStringGetTypeID()) {
			CFStringRef role_str = (CFStringRef)role;
			is_menu = CFEqual(role_str, ax_menu_role()) ||
				  CFEqual(role_str, ax_menu_bar_role());
		}
		CFRelease(role);
	}

	return is_menu;
}

int ax_menu_has_children(AXUIElementRef menu)
{
	CFIndex count = 0;

	if (!menu)
		return 0;

	if (AXUIElementGetAttributeValueCount(menu, kAXChildrenAttribute, &count) !=
		    kAXErrorSuccess)
		return 0;

	return count > 0;
}

AXUIElementRef ax_menu_root_from_menu_bar_item(AXUIElementRef element)
{
	AXUIElementRef menu_root = NULL;

	if (!element)
		return NULL;

	if (AXUIElementCopyAttributeValue(element, ax_menu_attribute(),
					  (CFTypeRef *)&menu_root) == kAXErrorSuccess &&
	    menu_root) {
		if (CFGetTypeID(menu_root) == AXUIElementGetTypeID())
			return menu_root;
		CFRelease(menu_root);
		menu_root = NULL;
	}

	CFArrayRef children = ax_copy_child_array(element, kAXChildrenAttribute);
	if (!children)
		return NULL;

	CFIndex count = CFArrayGetCount(children);
	for (CFIndex i = 0; i < count; i++) {
		CFTypeRef child_ref = CFArrayGetValueAtIndex(children, i);
		if (!child_ref || CFGetTypeID(child_ref) != AXUIElementGetTypeID())
			continue;
		AXUIElementRef child = (AXUIElementRef)child_ref;
		CFTypeRef role = NULL;
		int is_menu = 0;
		if (AXUIElementCopyAttributeValue(child, kAXRoleAttribute, &role) ==
			    kAXErrorSuccess &&
		    role) {
			if (CFGetTypeID(role) == CFStringGetTypeID())
				is_menu = CFEqual((CFStringRef)role, ax_menu_role());
			CFRelease(role);
		}
		if (is_menu) {
			CFRetain(child);
			menu_root = child;
			break;
		}
	}

	CFRelease(children);
	return menu_root;
}

AXUIElementRef ax_menu_root_for_element(AXUIElementRef element)
{
	AXUIElementRef current = NULL;

	if (!element)
		return NULL;

	CFRetain(element);
	current = element;

	for (int i = 0; i < 6 && current; i++) {
		CFTypeRef role = NULL;
		int is_menu = 0;

		if (AXUIElementCopyAttributeValue(current, kAXRoleAttribute, &role) ==
			    kAXErrorSuccess && role) {
			if (CFGetTypeID(role) == CFStringGetTypeID())
				is_menu = CFEqual((CFStringRef)role, ax_menu_role());
			CFRelease(role);
		}

		if (is_menu) {
			return current;
		}

		AXUIElementRef parent = NULL;
		if (AXUIElementCopyAttributeValue(current, kAXParentAttribute,
						  (CFTypeRef *)&parent) != kAXErrorSuccess ||
		    !parent) {
			CFRelease(current);
			break;
		}

		CFRelease(current);
		current = parent;
	}

	return NULL;
}

AXUIElementRef ax_menu_from_menu_bar_item(AXUIElementRef element)
{
	CFTypeRef role = NULL;
	AXUIElementRef menu = NULL;
	int is_menu_bar_item = 0;

	if (!element)
		return NULL;

	if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role) ==
		    kAXErrorSuccess && role) {
		if (CFGetTypeID(role) == CFStringGetTypeID())
			is_menu_bar_item =
				CFEqual((CFStringRef)role, ax_menu_bar_item_role());
		CFRelease(role);
	}

	if (!is_menu_bar_item)
		return NULL;

	if (AXUIElementCopyAttributeValue(element, ax_menu_attribute(),
					  (CFTypeRef *)&menu) != kAXErrorSuccess)
		return NULL;

	if (!menu || CFGetTypeID(menu) != AXUIElementGetTypeID()) {
		if (menu)
			CFRelease(menu);
		return NULL;
	}

	return menu;
}

int ax_press_menu_bar_item(AXUIElementRef element)
{
	if (!element)
		return 0;

	AXError err = AXUIElementPerformAction(element, kAXPressAction);
	if (err == kAXErrorSuccess)
		return 1;

	err = AXUIElementPerformAction(element, kAXShowMenuAction);
	return err == kAXErrorSuccess;
}

int ax_hint_position_exists(struct hint *hints, size_t count, int x, int y)
{
	/* Use a small tolerance to avoid near-duplicates */
	int tolerance = ax_env_int("WARPD_AX_DEDUP_PX", 5);
	if (tolerance < 0)
		tolerance = 0;
	for (size_t i = 0; i < count; i++) {
		int dx = hints[i].x - x;
		int dy = hints[i].y - y;
		if (dx >= -tolerance && dx <= tolerance &&
		    dy >= -tolerance && dy <= tolerance)
			return 1;
	}
	return 0;
}

int ax_element_center_for_screen(AXUIElementRef element, struct screen *scr,
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

void ax_collect_menu_bar_hints(AXUIElementRef menu_bar, struct screen *scr,
			       struct hint *hints, size_t max_hints,
			       size_t *count, uint64_t deadline_us)
{
	CFArrayRef children = NULL;

	if (!menu_bar || *count >= max_hints)
		return;

	children = ax_copy_child_array(menu_bar, kAXChildrenAttribute);
	if (!children)
		return;

	CFIndex child_count = CFArrayGetCount(children);
	for (CFIndex i = 0; i < child_count && *count < max_hints; i++) {
		if (deadline_us > 0 && get_time_us() >= deadline_us)
			break;

		CFTypeRef child_ref = CFArrayGetValueAtIndex(children, i);
		if (!child_ref || CFGetTypeID(child_ref) != AXUIElementGetTypeID())
			continue;

		AXUIElementRef menu_item = (AXUIElementRef)child_ref;
		CFTypeRef role = NULL;
		int is_menu_bar_item = 0;
		int x = 0;
		int y = 0;

		if (AXUIElementCopyAttributeValue(menu_item, kAXRoleAttribute,
						  &role) == kAXErrorSuccess &&
		    role) {
			if (CFGetTypeID(role) == CFStringGetTypeID())
				is_menu_bar_item =
					CFEqual((CFStringRef)role,
						ax_menu_bar_item_role());
			CFRelease(role);
		}

		if (!is_menu_bar_item)
			continue;

		if (!ax_element_center_for_screen(menu_item, scr, NULL, &x, &y))
			continue;

		if (ax_hint_position_exists(hints, *count, x, y)) {
			ax_debug_log_element(menu_item, "MENU_BAR_DUP", x, y);
			continue;
		}

		hints[*count].x = x;
		hints[*count].y = y;
		(*count)++;
		ax_debug_log_element(menu_item, "MENU_BAR", x, y);
	}

	CFRelease(children);
}

AXUIElementRef ax_menu_bar_item_nearest(AXUIElementRef app, double mouse_x,
					int *scan_result)
{
	AXUIElementRef menu_bar = NULL;
	CFTypeRef children_ref = NULL;
	AXUIElementRef best_menu_item = NULL;
	double best_distance = DBL_MAX;

	if (scan_result)
		*scan_result = AX_MENU_SCAN_OK;

	if (!app) {
		if (scan_result)
			*scan_result = AX_MENU_SCAN_NO_APP;
		return NULL;
	}

	if (AXUIElementCopyAttributeValue(app, ax_menu_bar_attribute(),
					  (CFTypeRef *)&menu_bar) != kAXErrorSuccess ||
	    !menu_bar) {
		if (scan_result)
			*scan_result = AX_MENU_SCAN_NO_MENU_BAR;
		return NULL;
	}

	if (AXUIElementCopyAttributeValue(menu_bar, kAXChildrenAttribute,
					  &children_ref) != kAXErrorSuccess ||
	    !children_ref) {
		CFRelease(menu_bar);
		if (scan_result)
			*scan_result = AX_MENU_SCAN_NO_CHILDREN;
		return NULL;
	}

	if (CFGetTypeID(children_ref) != CFArrayGetTypeID()) {
		CFRelease(children_ref);
		CFRelease(menu_bar);
		if (scan_result)
			*scan_result = AX_MENU_SCAN_CHILDREN_BAD_TYPE;
		return NULL;
	}

	CFArrayRef children = (CFArrayRef)children_ref;
	CFIndex child_count = CFArrayGetCount(children);
	for (CFIndex i = 0; i < child_count; i++) {
		CFTypeRef child_ref = CFArrayGetValueAtIndex(children, i);
		AXUIElementRef menu_item = NULL;
		CFTypeRef role = NULL;
		int is_menu_bar_item = 0;
		CGPoint position = CGPointZero;
		CGSize size = CGSizeZero;

		if (!child_ref || CFGetTypeID(child_ref) != AXUIElementGetTypeID())
			continue;

		menu_item = (AXUIElementRef)child_ref;

		if (AXUIElementCopyAttributeValue(menu_item, kAXRoleAttribute,
						  &role) == kAXErrorSuccess &&
		    role) {
			if (CFGetTypeID(role) == CFStringGetTypeID())
				is_menu_bar_item =
					CFEqual((CFStringRef)role,
						ax_menu_bar_item_role());
			CFRelease(role);
		}

		if (!is_menu_bar_item)
			continue;

		if (!ax_get_position_size(menu_item, &position, &size) ||
		    size.width < 5 || size.height < 5)
			continue;

		double left = position.x;
		double right = position.x + size.width;
		double distance = 0.0;
		if (mouse_x < left)
			distance = left - mouse_x;
		else if (mouse_x > right)
			distance = mouse_x - right;

		if (distance < best_distance) {
			if (best_menu_item)
				CFRelease(best_menu_item);
			CFRetain(menu_item);
			best_menu_item = menu_item;
			best_distance = distance;
		}
	}

	CFRelease(children_ref);
	CFRelease(menu_bar);

	if (!best_menu_item && scan_result)
		*scan_result = AX_MENU_SCAN_NO_ITEM;

	return best_menu_item;
}
