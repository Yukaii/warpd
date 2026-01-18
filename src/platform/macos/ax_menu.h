/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#ifndef WARPED_AX_MENU_H
#define WARPED_AX_MENU_H

#include "../../platform.h"
#include <ApplicationServices/ApplicationServices.h>

int ax_menu_bar_item_title(AXUIElementRef element, char *out, size_t out_len);
int ax_menu_root_matches_title(AXUIElementRef menu_root, const char *title);
int ax_element_is_menu_container(AXUIElementRef element);
int ax_menu_has_children(AXUIElementRef menu);
AXUIElementRef ax_menu_root_from_menu_bar_item(AXUIElementRef element);
AXUIElementRef ax_menu_root_for_element(AXUIElementRef element);
AXUIElementRef ax_menu_from_menu_bar_item(AXUIElementRef element);
int ax_press_menu_bar_item(AXUIElementRef element);
int ax_hint_position_exists(struct hint *hints, size_t count, int x, int y);
int ax_element_center_for_screen(AXUIElementRef element, struct screen *scr,
				 const CGRect *window_frame,
				 int *center_x, int *center_y);
void ax_collect_menu_bar_hints(AXUIElementRef menu_bar, struct screen *scr,
			       struct hint *hints, size_t max_hints,
			       size_t *count, uint64_t deadline_us);

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

typedef void (*ax_collect_bfs_fn)(AXUIElementRef root, struct screen *scr,
				  const CGRect *window_frame,
				  struct hint *hints, size_t max_hints,
				  size_t *count, uint64_t deadline_us,
				  int skip_menu_containers,
				  int include_menu_attr);

void ax_collect_menu_hints_with_poll(AXUIElementRef menu_root,
				     struct screen *scr,
				     struct hint *hints, size_t max_hints,
				     size_t *count, uint64_t deadline_us,
				     ax_collect_bfs_fn collect_bfs);
size_t ax_collect_menu_hints_from_menu_bar(AXUIElementRef app,
					   struct screen *scr,
					   struct hint *base_hints,
					   size_t base_count,
					   size_t max_hints,
					   struct hint *out_hints,
					   uint64_t deadline_us,
					   ax_collect_bfs_fn collect_bfs);

#endif
