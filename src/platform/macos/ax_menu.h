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

#endif
