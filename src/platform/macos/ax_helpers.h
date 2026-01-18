/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#ifndef WARPED_AX_HELPERS_H
#define WARPED_AX_HELPERS_H

#include <ApplicationServices/ApplicationServices.h>

CFStringRef ax_link_role(void);
CFStringRef ax_list_item_role(void);
CFStringRef ax_image_role(void);

CFStringRef ax_actions_attribute(void);
CFStringRef ax_visible_children_attribute(void);
CFStringRef ax_children_in_navigation_order_attribute(void);
CFStringRef ax_contents_attribute(void);
CFStringRef ax_frame_attribute(void);
CFStringRef ax_menu_bar_attribute(void);
CFStringRef ax_menu_attribute(void);
CFStringRef ax_menu_role(void);
CFStringRef ax_menu_bar_item_role(void);
CFStringRef ax_menu_bar_role(void);
CFStringRef ax_focused_ui_element_attribute(void);
CFStringRef ax_tabs_attribute(void);

int ax_get_bool_attr(AXUIElementRef element, CFStringRef attr, int *value);
int ax_copy_string_attr(AXUIElementRef element, CFStringRef attr,
			char *out, size_t out_len);
CFArrayRef ax_copy_child_array(AXUIElementRef element, CFStringRef attr);
CFIndex ax_child_count(AXUIElementRef element, CFStringRef attr);
int ax_get_position_size(AXUIElementRef element, CGPoint *position,
			 CGSize *size);
int ax_env_int(const char *name, int default_value);

#endif
