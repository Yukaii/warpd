/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "ax_menu.h"
#include "ax_helpers.h"
#include <ctype.h>
#include <string.h>

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
