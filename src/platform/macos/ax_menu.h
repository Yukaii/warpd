/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#ifndef WARPED_AX_MENU_H
#define WARPED_AX_MENU_H

#include <ApplicationServices/ApplicationServices.h>

int ax_menu_bar_item_title(AXUIElementRef element, char *out, size_t out_len);
int ax_menu_root_matches_title(AXUIElementRef menu_root, const char *title);
int ax_element_is_menu_container(AXUIElementRef element);
int ax_menu_has_children(AXUIElementRef menu);
AXUIElementRef ax_menu_root_from_menu_bar_item(AXUIElementRef element);
AXUIElementRef ax_menu_root_for_element(AXUIElementRef element);
AXUIElementRef ax_menu_from_menu_bar_item(AXUIElementRef element);
int ax_press_menu_bar_item(AXUIElementRef element);

enum ax_menu_scan_result {
	AX_MENU_SCAN_OK = 0,
	AX_MENU_SCAN_NO_APP,
	AX_MENU_SCAN_NO_MENU_BAR,
	AX_MENU_SCAN_NO_CHILDREN,
	AX_MENU_SCAN_CHILDREN_BAD_TYPE,
	AX_MENU_SCAN_NO_ITEM,
};

AXUIElementRef ax_menu_bar_item_nearest(AXUIElementRef app, double mouse_x,
					int *scan_result);

#endif
