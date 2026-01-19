/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "ax_traverse.h"
#include "ax_debug.h"
#include "ax_helpers.h"
#include "ax_menu.h"
#include <string.h>

/* Declare get_time_us from warpd.c - avoid including warpd.h */
extern uint64_t get_time_us(void);

struct ax_profile {
	uint64_t start_us;
	uint64_t total_us;
	uint64_t attr_us[5];
	size_t nodes_visited;
	size_t interactable_checked;
	size_t hints_added;
	size_t dup_skipped;
	size_t offscreen_skipped;
	size_t attr_calls[5];
	size_t attr_children[5];
	int max_depth;
};

static struct ax_profile ax_prof;

static void ax_fill_hint_metadata(AXUIElementRef element, struct hint *hint)
{
	if (!element || !hint)
		return;

	hint->title[0] = 0;
	hint->role[0] = 0;
	hint->desc[0] = 0;

	ax_copy_string_attr(element, kAXRoleAttribute, hint->role,
			    sizeof hint->role);
	if (!ax_copy_string_attr(element, kAXTitleAttribute, hint->title,
				 sizeof hint->title))
		if (!ax_copy_string_attr(element, kAXValueAttribute, hint->title,
					 sizeof hint->title))
			if (!ax_copy_string_attr(element, kAXDescriptionAttribute,
						 hint->title,
						 sizeof hint->title))
				ax_copy_string_attr(element, kAXHelpAttribute,
						    hint->title,
						    sizeof hint->title);

	ax_copy_string_attr(element, kAXRoleDescriptionAttribute, hint->desc,
			    sizeof hint->desc);
}

static void ax_profile_begin(void)
{
	if (!ax_prof.start_us)
		ax_prof.start_us = get_time_us();
}

void ax_profile_reset(void)
{
	memset(&ax_prof, 0, sizeof(ax_prof));
}

void ax_profile_set_total(uint64_t total_us)
{
	ax_prof.total_us = total_us;
}

void ax_profile_log(const char *label)
{
	if (!ax_debug_enabled())
		return;

	ax_debug_log("=== AX profile (%s) ===\n", label);
	ax_debug_log("nodes=%zu interactable=%zu hints=%zu dup=%zu offscreen=%zu max_depth=%d\n",
		     ax_prof.nodes_visited, ax_prof.interactable_checked, ax_prof.hints_added,
		     ax_prof.dup_skipped, ax_prof.offscreen_skipped, ax_prof.max_depth);
	ax_debug_log("attr: children=%zu (%llums, calls=%zu) visible=%zu (%llums, calls=%zu) nav=%zu (%llums, calls=%zu) contents=%zu (%llums, calls=%zu) tabs=%zu (%llums, calls=%zu)\n",
		     ax_prof.attr_children[0],
		     (unsigned long long)(ax_prof.attr_us[0] / 1000), ax_prof.attr_calls[0],
		     ax_prof.attr_children[1],
		     (unsigned long long)(ax_prof.attr_us[1] / 1000), ax_prof.attr_calls[1],
		     ax_prof.attr_children[2],
		     (unsigned long long)(ax_prof.attr_us[2] / 1000), ax_prof.attr_calls[2],
		     ax_prof.attr_children[3],
		     (unsigned long long)(ax_prof.attr_us[3] / 1000), ax_prof.attr_calls[3],
		     ax_prof.attr_children[4],
		     (unsigned long long)(ax_prof.attr_us[4] / 1000), ax_prof.attr_calls[4]);
	ax_debug_log("time: total=%llums\n",
		     (unsigned long long)(ax_prof.total_us / 1000));
	ax_debug_log("\n");
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

int ax_element_is_interactable(AXUIElementRef element)
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

static size_t ax_collect_interactable_children(AXUIElementRef element,
				     CFStringRef attribute,
				     struct screen *scr,
				     const CGRect *window_frame,
				     struct hint *hints,
				     size_t max_hints, size_t *count,
				     uint64_t deadline_us,
				     CFMutableSetRef visited,
				     int depth,
				     int attr_idx)
{
	CFTypeRef children_ref = NULL;
	uint64_t attr_start_us = 0;

	if (ax_debug_enabled()) {
		ax_profile_begin();
		attr_start_us = get_time_us();
		ax_prof.attr_calls[attr_idx]++;
	}

	if (AXUIElementCopyAttributeValue(element, attribute, &children_ref) !=
		kAXErrorSuccess || !children_ref) {
		if (ax_debug_enabled() && attr_start_us)
			ax_prof.attr_us[attr_idx] += get_time_us() - attr_start_us;
		return 0;
	}

	/* Validate it's actually an array */
	if (CFGetTypeID(children_ref) != CFArrayGetTypeID()) {
		CFRelease(children_ref);
		if (ax_debug_enabled() && attr_start_us)
			ax_prof.attr_us[attr_idx] += get_time_us() - attr_start_us;
		return 0;
	}

	CFArrayRef children = (CFArrayRef)children_ref;
	CFIndex child_count = CFArrayGetCount(children);
	if (ax_debug_enabled())
		ax_prof.attr_children[attr_idx] += (size_t)child_count;
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
		ax_collect_interactable_hints(child, scr, window_frame,
				      hints, max_hints, count, deadline_us, visited,
				      depth + 1);
		if (*count >= max_hints)
			break;
	}

	CFRelease(children);
	if (ax_debug_enabled() && attr_start_us)
		ax_prof.attr_us[attr_idx] += get_time_us() - attr_start_us;
	return (size_t)child_count;
}


void ax_collect_interactable_hints(AXUIElementRef element, struct screen *scr,
				   const CGRect *window_frame,
				   struct hint *hints,
				   size_t max_hints, size_t *count,
				   uint64_t deadline_us,
				   CFMutableSetRef visited,
				   int depth)
{
	if (!element)
		return;

	if (*count >= max_hints)
		return;

	if (deadline_us > 0 && get_time_us() >= deadline_us)
		return;

	if (ax_debug_enabled()) {
		ax_profile_begin();
		ax_prof.nodes_visited++;
		if (depth > ax_prof.max_depth)
			ax_prof.max_depth = depth;
	}

	if (visited) {
		if (CFSetContainsValue(visited, element))
			return;
		CFSetAddValue(visited, element);
	}

	/* Log ALL elements when verbose mode is enabled */
	if (ax_debug_verbose())
		ax_debug_log_element(element, "VISIT", -1, -1);

	int hidden = 0;
	int should_traverse = 1;
	if (ax_get_bool_attr(element, kAXHiddenAttribute, &hidden) && hidden)
		should_traverse = 0;
	if (should_traverse) {
		CGPoint pos = CGPointZero;
		CGSize size = CGSizeZero;
		if (ax_get_position_size(element, &pos, &size)) {
			if (size.width <= 0 || size.height <= 0) {
				should_traverse = 0;
			} else {
				float right = pos.x + size.width;
				float top = pos.y + size.height;
				float scr_right = scr->x + scr->w;
				float scr_top = scr->y + scr->h;
				if (right < scr->x || pos.x > scr_right ||
				    top < scr->y || pos.y > scr_top)
					should_traverse = 0;
			}
		}
	}

	if (ax_element_is_interactable(element)) {
		int x;
		int y;

		if (ax_debug_enabled())
			ax_prof.interactable_checked++;

		if (ax_element_center_for_screen(element, scr, window_frame, &x, &y)) {
			/* Skip duplicate positions */
			if (ax_hint_position_exists(hints, *count, x, y)) {
				if (ax_debug_enabled())
					ax_prof.dup_skipped++;
				ax_debug_log_element(element, "DUP", x, y);
			} else {
				hints[*count].x = x;
				hints[*count].y = y;
				ax_fill_hint_metadata(element, &hints[*count]);
				(*count)++;
				if (ax_debug_enabled())
					ax_prof.hints_added++;
				ax_debug_log_element(element, "HINT", x, y);
				if (*count >= max_hints)
					return;
			}
		} else {
			if (ax_debug_enabled())
				ax_prof.offscreen_skipped++;
			ax_debug_log_element(element, "OFFSCREEN", -1, -1);
		}
	}

	if (!should_traverse)
		return;

	size_t children_found = 0;

	children_found = ax_collect_interactable_children(element, kAXChildrenAttribute,
						scr, window_frame, hints, max_hints, count,
						deadline_us, visited, depth, 0);
	if (*count >= max_hints)
		return;
	if (children_found == 0) {
		children_found = ax_collect_interactable_children(element,
							 ax_visible_children_attribute(), scr,
							 window_frame, hints, max_hints, count,
							 deadline_us, visited, depth, 1);
		if (*count >= max_hints)
			return;
	}
	if (children_found == 0) {
		children_found = ax_collect_interactable_children(element,
							 ax_children_in_navigation_order_attribute(),
							 scr, window_frame, hints, max_hints, count,
							 deadline_us, visited, depth, 2);
		if (*count >= max_hints)
			return;
	}
	if (children_found == 0) {
		children_found = ax_collect_interactable_children(element,
							 ax_contents_attribute(), scr,
							 window_frame, hints, max_hints, count,
							 deadline_us, visited, depth, 3);
		if (*count >= max_hints)
			return;
	}
	if (children_found == 0) {
		/* Try to collect tabs if the element has an AXTabs attribute (e.g., browser tabs) */
		ax_collect_interactable_children(element, ax_tabs_attribute(), scr,
							 window_frame, hints, max_hints, count,
							 deadline_us, visited, depth, 4);
	}
}


/*
 * BFS version of hint collection - better for menu bars and web content
 * where we want breadth-first traversal to find items at similar depths.
 */
#define BFS_QUEUE_SIZE 4096

void ax_collect_hints_bfs(AXUIElementRef root, struct screen *scr,
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
						ax_fill_hint_metadata(element,
								      &hints[*count]);
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
				} else if (CFGetTypeID(children_ref) ==
					   AXUIElementGetTypeID()) {
					if (queue_tail < BFS_QUEUE_SIZE) {
						CFRetain(children_ref);
						queue[queue_tail++] =
							(AXUIElementRef)children_ref;
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
