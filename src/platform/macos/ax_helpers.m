/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "ax_helpers.h"

int ax_get_bool_attr(AXUIElementRef element, CFStringRef attr, int *value)
{
	CFTypeRef raw = NULL;
	AXError error;

	if (!element)
		return 0;

	error = AXUIElementCopyAttributeValue(element, attr, &raw);

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

CFStringRef ax_link_role(void)
{
#ifdef kAXLinkRole
	return kAXLinkRole;
#else
	return CFSTR("AXLink");
#endif
}

CFStringRef ax_list_item_role(void)
{
#ifdef kAXListItemRole
	return kAXListItemRole;
#else
	return CFSTR("AXListItem");
#endif
}

CFStringRef ax_image_role(void)
{
#ifdef kAXImageRole
	return kAXImageRole;
#else
	return CFSTR("AXImage");
#endif
}

CFStringRef ax_actions_attribute(void)
{
#ifdef kAXActionsAttribute
	return kAXActionsAttribute;
#else
	return CFSTR("AXActions");
#endif
}

CFStringRef ax_visible_children_attribute(void)
{
#ifdef kAXVisibleChildrenAttribute
	return kAXVisibleChildrenAttribute;
#else
	return CFSTR("AXVisibleChildren");
#endif
}

CFStringRef ax_children_in_navigation_order_attribute(void)
{
#ifdef kAXChildrenInNavigationOrderAttribute
	return kAXChildrenInNavigationOrderAttribute;
#else
	return CFSTR("AXChildrenInNavigationOrder");
#endif
}

CFStringRef ax_contents_attribute(void)
{
#ifdef kAXContentsAttribute
	return kAXContentsAttribute;
#else
	return CFSTR("AXContents");
#endif
}

CFStringRef ax_frame_attribute(void)
{
#ifdef kAXFrameAttribute
	return kAXFrameAttribute;
#else
	return CFSTR("AXFrame");
#endif
}

CFStringRef ax_menu_bar_attribute(void)
{
#ifdef kAXMenuBarAttribute
	return kAXMenuBarAttribute;
#else
	return CFSTR("AXMenuBar");
#endif
}

CFStringRef ax_menu_attribute(void)
{
#ifdef kAXMenuAttribute
	return kAXMenuAttribute;
#else
	return CFSTR("AXMenu");
#endif
}

CFStringRef ax_menu_role(void)
{
#ifdef kAXMenuRole
	return kAXMenuRole;
#else
	return CFSTR("AXMenu");
#endif
}

CFStringRef ax_menu_bar_item_role(void)
{
#ifdef kAXMenuBarItemRole
	return kAXMenuBarItemRole;
#else
	return CFSTR("AXMenuBarItem");
#endif
}

CFStringRef ax_menu_bar_role(void)
{
#ifdef kAXMenuBarRole
	return kAXMenuBarRole;
#else
	return CFSTR("AXMenuBar");
#endif
}

CFStringRef ax_focused_ui_element_attribute(void)
{
#ifdef kAXFocusedUIElementAttribute
	return kAXFocusedUIElementAttribute;
#else
	return CFSTR("AXFocusedUIElement");
#endif
}

CFStringRef ax_tabs_attribute(void)
{
	/* AXTabs returns an array of tab elements for windows that support tabs */
	return CFSTR("AXTabs");
}

int ax_copy_string_attr(AXUIElementRef element, CFStringRef attr,
			char *out, size_t out_len)
{
	CFTypeRef raw = NULL;

	if (!out || out_len == 0)
		return 0;

	out[0] = 0;
	if (AXUIElementCopyAttributeValue(element, attr, &raw) != kAXErrorSuccess ||
	    !raw)
		return 0;

	int ok = 0;
	if (CFGetTypeID(raw) == CFStringGetTypeID()) {
		ok = CFStringGetCString((CFStringRef)raw, out, out_len,
					kCFStringEncodingUTF8);
	}

	CFRelease(raw);
	return ok;
}

CFArrayRef ax_copy_child_array(AXUIElementRef element, CFStringRef attr)
{
	CFTypeRef children_ref = NULL;

	if (AXUIElementCopyAttributeValue(element, attr, &children_ref) !=
		kAXErrorSuccess || !children_ref)
		return NULL;

	/* Validate it's actually an array */
	if (CFGetTypeID(children_ref) != CFArrayGetTypeID()) {
		CFRelease(children_ref);
		return NULL;
	}

	CFArrayRef children = (CFArrayRef)children_ref;
	if (CFArrayGetCount(children) == 0) {
		CFRelease(children);
		return NULL;
	}

	return children;
}

CFIndex ax_child_count(AXUIElementRef element, CFStringRef attr)
{
	CFIndex count = -1;

	if (!element)
		return -1;

	if (AXUIElementGetAttributeValueCount(element, attr, &count) !=
		    kAXErrorSuccess)
		return -1;

	return count;
}

int ax_get_position_size(AXUIElementRef element, CGPoint *position,
			 CGSize *size)
{
	AXValueRef position_value = NULL;
	AXValueRef size_value = NULL;
	AXValueRef frame_value = NULL;
	int has_position = 0;
	int has_size = 0;

	if (!element)
		return 0;

	if (AXUIElementCopyAttributeValue(element, kAXPositionAttribute,
				      (CFTypeRef *)&position_value) == kAXErrorSuccess &&
	    position_value) {
		has_position = AXValueGetValue(position_value, kAXValueCGPointType,
					       position);
		CFRelease(position_value);
	}

	if (AXUIElementCopyAttributeValue(element, kAXSizeAttribute,
				      (CFTypeRef *)&size_value) == kAXErrorSuccess &&
	    size_value) {
		has_size = AXValueGetValue(size_value, kAXValueCGSizeType, size);
		CFRelease(size_value);
	}

	if (has_position && has_size)
		return 1;

	if (AXUIElementCopyAttributeValue(element, ax_frame_attribute(),
				      (CFTypeRef *)&frame_value) == kAXErrorSuccess &&
	    frame_value) {
		CGRect frame = CGRectZero;
		if (AXValueGetValue(frame_value, kAXValueCGRectType, &frame)) {
			*position = frame.origin;
			*size = frame.size;
			CFRelease(frame_value);
			return 1;
		}
		CFRelease(frame_value);
	}

	return 0;
}
