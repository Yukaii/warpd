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

static void ax_collect_interactable_children(AXUIElementRef element,
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
		ax_collect_interactable_hints(child, scr, window_frame,
					      hints, max_hints, count, deadline_us, visited);
		if (*count >= max_hints)
			break;
	}

	CFRelease(children);
}

void ax_collect_interactable_hints(AXUIElementRef element, struct screen *scr,
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

	ax_collect_interactable_children(element, kAXChildrenAttribute, scr,
					 window_frame, hints, max_hints, count,
					 deadline_us, visited);
	if (*count >= max_hints)
		return;
	ax_collect_interactable_children(element, ax_visible_children_attribute(), scr,
					 window_frame, hints, max_hints, count,
					 deadline_us, visited);
	if (*count >= max_hints)
		return;
	ax_collect_interactable_children(element,
					 ax_children_in_navigation_order_attribute(),
					 scr, window_frame, hints, max_hints, count,
					 deadline_us, visited);
	if (*count >= max_hints)
		return;
	ax_collect_interactable_children(element, ax_contents_attribute(), scr,
					 window_frame, hints, max_hints, count,
					 deadline_us, visited);
	if (*count >= max_hints)
		return;
	/* Try to collect tabs if the element has an AXTabs attribute (e.g., browser tabs) */
	ax_collect_interactable_children(element, ax_tabs_attribute(), scr,
					 window_frame, hints, max_hints, count,
					 deadline_us, visited);
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
