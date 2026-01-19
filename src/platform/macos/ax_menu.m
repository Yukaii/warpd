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

static int ax_menu_has_visible_children(AXUIElementRef menu)
{
	CFTypeRef children_ref = NULL;
	int visible = 0;

	if (!menu)
		return 0;

	if (AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute,
					  &children_ref) != kAXErrorSuccess ||
	    !children_ref)
		return 0;

	if (CFGetTypeID(children_ref) == CFArrayGetTypeID()) {
		CFArrayRef children = (CFArrayRef)children_ref;
		CFIndex count = CFArrayGetCount(children);
		for (CFIndex i = 0; i < count; i++) {
			CFTypeRef child_ref = CFArrayGetValueAtIndex(children, i);
			if (!child_ref ||
			    CFGetTypeID(child_ref) != AXUIElementGetTypeID())
				continue;
			AXUIElementRef child = (AXUIElementRef)child_ref;
			CGPoint position = CGPointZero;
			CGSize size = CGSizeZero;
			if (ax_get_position_size(child, &position, &size) &&
			    size.width > 0 && size.height > 0) {
				visible = 1;
				break;
			}
		}
	}

	CFRelease(children_ref);
	return visible;
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

	float raw_global_x = position.x + size.width / 2.0f;
	float raw_global_y = position.y + size.height / 2.0f;
	float local_x_candidate = raw_global_x;
	float local_y_candidate = raw_global_y;
	int using_local = 0;

	if (local_x_candidate < 0) {
		float wrapped_x = scr->w + local_x_candidate;
		if (wrapped_x >= 0 && wrapped_x <= scr->w)
			local_x_candidate = wrapped_x;
	}

	if (local_y_candidate < 0) {
		float wrapped_y = scr->h + local_y_candidate;
		if (wrapped_y >= 0 && wrapped_y <= scr->h)
			local_y_candidate = wrapped_y;
	}

	if (local_x_candidate >= 0 && local_x_candidate <= scr->w &&
	    local_y_candidate >= 0 && local_y_candidate <= scr->h) {
		using_local = 1;
		local_x = local_x_candidate;
		local_y = local_y_candidate;
	} else {
		float global_x = raw_global_x;
		float global_y = raw_global_y;
		float alt_global_x = global_x + scr->x;
		float alt_global_y = global_y + scr->y;
		int in_screen = !(global_x < scr->x || global_x > (scr->x + scr->w) ||
				  global_y < scr->y || global_y > (scr->y + scr->h));
		int alt_in_screen = !(alt_global_x < scr->x || alt_global_x > (scr->x + scr->w) ||
				      alt_global_y < scr->y || alt_global_y > (scr->y + scr->h));

		if (!in_screen && alt_in_screen) {
			global_x = alt_global_x;
			global_y = alt_global_y;
			in_screen = 1;
		}

		if (window_frame && in_screen) {
			if (global_x < window_frame->origin.x ||
			    global_x > (window_frame->origin.x + window_frame->size.width) ||
			    global_y < window_frame->origin.y ||
			    global_y > (window_frame->origin.y + window_frame->size.height)) {
				float frame_dx = window_frame->origin.x - scr->x;
				float frame_dy = window_frame->origin.y - scr->y;
				float shifted_x = global_x - frame_dx;
				float shifted_y = global_y - frame_dy;

				if (shifted_x >= scr->x && shifted_x <= (scr->x + scr->w) &&
				    shifted_y >= scr->y && shifted_y <= (scr->y + scr->h)) {
					global_x = shifted_x;
					global_y = shifted_y;
				} else {
					return 0;
				}
			}
		}

		if (!in_screen)
			return 0;

		local_x = global_x - scr->x;
		local_y = global_y - scr->y;
	}

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

void ax_collect_menu_hints_with_poll(AXUIElementRef menu_root,
				     struct screen *scr,
				     struct hint *hints, size_t max_hints,
				     size_t *count, uint64_t deadline_us,
				     ax_collect_bfs_fn collect_bfs)
{
	int poll_ms = ax_env_int("WARPD_AX_MENU_POLL_MS", 200);
	int poll_interval_ms = ax_env_int("WARPD_AX_MENU_POLL_INTERVAL_MS", 30);
	int stable_runs_needed = ax_env_int("WARPD_AX_MENU_STABLE_RUNS", 2);
	int min_runs = ax_env_int("WARPD_AX_MENU_POLL_MIN_RUNS", 2);
	uint64_t poll_deadline_us =
		get_time_us() + (uint64_t)poll_ms * 1000;
	int stable_runs = 0;
	int runs = 0;
	size_t last_temp_count = 0;
	size_t base_count = *count;
	size_t best_count = *count;
	struct hint *base_hints = NULL;
	struct hint *best_hints = NULL;
	struct hint *temp_hints = NULL;
	CGRect menu_frame = CGRectZero;
	const CGRect *menu_frame_ptr = NULL;
	int clip_to_menu_frame = ax_env_int("WARPD_AX_MENU_CLIP_FRAME", 0);

	if (!menu_root || !collect_bfs)
		return;

	if (clip_to_menu_frame > 0 &&
	    ax_get_position_size(menu_root, &menu_frame.origin,
				 &menu_frame.size) &&
	    menu_frame.size.width >= 20 &&
	    menu_frame.size.height >= 20)
		menu_frame_ptr = &menu_frame;

	if (base_count >= max_hints)
		return;

	if (poll_deadline_us > deadline_us)
		poll_deadline_us = deadline_us;

	base_hints = ax_alloc_hints(max_hints);
	best_hints = ax_alloc_hints(max_hints);
	temp_hints = ax_alloc_hints(max_hints);
	if (!base_hints || !best_hints || !temp_hints) {
		free(base_hints);
		free(best_hints);
		free(temp_hints);
		return;
	}

	memcpy(base_hints, hints, sizeof(struct hint) * base_count);
	memcpy(best_hints, hints, sizeof(struct hint) * base_count);
	last_temp_count = base_count;

	while (get_time_us() < poll_deadline_us && *count < max_hints) {
		size_t temp_count = base_count;

		memcpy(temp_hints, base_hints, sizeof(struct hint) * base_count);
		collect_bfs(menu_root, scr, menu_frame_ptr, temp_hints, max_hints,
			    &temp_count, deadline_us, 1, 1);

		if (temp_count > best_count) {
			memcpy(best_hints, temp_hints,
			       sizeof(struct hint) * temp_count);
			best_count = temp_count;
		}

		runs++;
		if (temp_count == last_temp_count)
			stable_runs++;
		else
			stable_runs = 0;
		last_temp_count = temp_count;
		if (runs >= min_runs && stable_runs >= stable_runs_needed)
			break;

		if (poll_interval_ms > 0)
			usleep((useconds_t)poll_interval_ms * 1000);
	}

	memcpy(hints, best_hints, sizeof(struct hint) * best_count);
	*count = best_count;
	free(base_hints);
	free(best_hints);
	free(temp_hints);
}

size_t ax_collect_menu_hints_from_menu_bar(AXUIElementRef app,
					   struct screen *scr,
					   struct hint *base_hints,
					   size_t base_count,
					   size_t max_hints,
					   struct hint *out_hints,
					   uint64_t deadline_us,
					   ax_collect_bfs_fn collect_bfs)
{
	size_t best_count = 0;
	NSPoint mouse_loc = [NSEvent mouseLocation];
	double mouse_x = mouse_loc.x;
	AXUIElementRef best_menu_item = NULL;
	char best_menu_title[256];
	best_menu_title[0] = 0;
	int scan_result = AX_MENU_SCAN_OK;
	int allow_auto_open = ax_env_int("WARPD_AX_MENU_AUTO_OPEN", 0);

	if (!app || !base_hints || !out_hints)
		return 0;

	if (ax_debug_enabled()) {
		ax_debug_log("MENU_SCAN start mouse_x=%.1f base_count=%zu deadline_us=%llu\n",
			     mouse_x, base_count,
			     (unsigned long long)deadline_us);
	}

	best_menu_item = ax_menu_bar_item_nearest(app, mouse_x, &scan_result);
	if (!best_menu_item) {
		if (ax_debug_enabled()) {
			switch (scan_result) {
			case AX_MENU_SCAN_NO_APP:
				ax_debug_log("MENU_SCAN no_app\n");
				break;
			case AX_MENU_SCAN_NO_MENU_BAR:
				ax_debug_log("MENU_SCAN menu_bar_missing\n");
				break;
			case AX_MENU_SCAN_NO_CHILDREN:
				ax_debug_log("MENU_SCAN menu_bar_children_missing\n");
				break;
			case AX_MENU_SCAN_CHILDREN_BAD_TYPE:
				ax_debug_log("MENU_SCAN menu_bar_children_not_array\n");
				break;
			case AX_MENU_SCAN_NO_ITEM:
				ax_debug_log("MENU_SCAN no_best_menu_item\n");
				break;
			default:
				ax_debug_log("MENU_SCAN no_best_menu_item\n");
				break;
			}
		}
		return 0;
	}

	ax_menu_bar_item_title(best_menu_item, best_menu_title,
			       sizeof best_menu_title);

	AXUIElementRef menu_root = ax_menu_root_from_menu_bar_item(best_menu_item);
	if (!menu_root) {
		if (!allow_auto_open) {
			CFRelease(best_menu_item);
			return 0;
		}
		if (ax_debug_enabled())
			ax_debug_log("MENU_OPEN target=\"%s\" initial_children=-1\n",
				     best_menu_title);
		int pressed = ax_press_menu_bar_item(best_menu_item);
		if (ax_debug_enabled())
			ax_debug_log("MENU_OPEN attempt=1 pressed=%d children=-1\n",
				     pressed);
		if (pressed)
			usleep(80 * 1000);
		menu_root = ax_menu_root_from_menu_bar_item(best_menu_item);
	}
	if (!menu_root) {
		CFRelease(best_menu_item);
		if (ax_debug_enabled())
			ax_debug_log("MENU_SCAN menu_root_missing title=\"%s\"\n",
				     best_menu_title);
		return 0;
	}

	if (!ax_menu_root_matches_title(menu_root, best_menu_title)) {
		CFRelease(menu_root);
		CFRelease(best_menu_item);
		if (ax_debug_enabled())
			ax_debug_log("MENU_SCAN menu_root_title_mismatch title=\"%s\"\n",
				     best_menu_title);
		return 0;
	}

	int menu_open_delay_ms =
		ax_env_int("WARPD_AX_MENU_OPEN_DELAY_MS", 80);
	int menu_open_retries =
		ax_env_int("WARPD_AX_MENU_OPEN_RETRIES", 1);
	if (ax_debug_enabled()) {
		CFIndex initial_children =
			ax_child_count(menu_root, kAXChildrenAttribute);
		int initial_visible = ax_menu_has_visible_children(menu_root);
		ax_debug_log("MENU_OPEN target=\"%s\" initial_children=%ld\n",
			     best_menu_title, (long)initial_children);
		if (!initial_visible)
			ax_debug_log("MENU_OPEN target=\"%s\" visible_children=0\n",
				     best_menu_title);
	}
	for (int attempt = 0;
	     attempt < menu_open_retries &&
	     (!ax_menu_has_children(menu_root) ||
	      !ax_menu_has_visible_children(menu_root));
	     attempt++) {
		if (!allow_auto_open)
			break;
		int pressed = ax_press_menu_bar_item(best_menu_item);
		if (ax_debug_enabled()) {
			CFIndex after_press =
				ax_child_count(menu_root, kAXChildrenAttribute);
			int visible_after = ax_menu_has_visible_children(menu_root);
			ax_debug_log("MENU_OPEN attempt=%d pressed=%d children=%ld\n",
				     attempt + 1, pressed, (long)after_press);
			if (!visible_after)
				ax_debug_log("MENU_OPEN attempt=%d visible_children=0\n",
					     attempt + 1);
		}
		if (!pressed)
			break;
		if (menu_open_delay_ms > 0)
			usleep((useconds_t)menu_open_delay_ms * 1000);
		if (!ax_menu_has_children(menu_root) ||
		    !ax_menu_has_visible_children(menu_root)) {
			AXUIElementRef refreshed = NULL;
			if (AXUIElementCopyAttributeValue(
				    best_menu_item, ax_menu_attribute(),
				    (CFTypeRef *)&refreshed) == kAXErrorSuccess &&
			    refreshed) {
				if (CFGetTypeID(refreshed) == AXUIElementGetTypeID()) {
					CFRelease(menu_root);
					menu_root = refreshed;
				} else {
					CFRelease(refreshed);
				}
			}
		}
	}

	size_t temp_count = base_count;
	struct hint *temp_hints = ax_alloc_hints(max_hints);
	if (!temp_hints) {
		CFRelease(menu_root);
		CFRelease(best_menu_item);
		return 0;
	}
	memcpy(temp_hints, base_hints, sizeof(struct hint) * base_count);
	ax_collect_menu_hints_with_poll(menu_root, scr, temp_hints, max_hints,
					&temp_count, deadline_us, collect_bfs);

	memcpy(out_hints, temp_hints, sizeof(struct hint) * temp_count);
	best_count = temp_count;

	free(temp_hints);
	CFRelease(menu_root);
	CFRelease(best_menu_item);
	return best_count;
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
