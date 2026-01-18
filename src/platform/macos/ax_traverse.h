/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#ifndef WARPED_AX_TRAVERSE_H
#define WARPED_AX_TRAVERSE_H

#include "macos.h"
#include <ApplicationServices/ApplicationServices.h>

int ax_element_is_interactable(AXUIElementRef element);

void ax_collect_interactable_hints(AXUIElementRef element, struct screen *scr,
				   const CGRect *window_frame,
				   struct hint *hints,
				   size_t max_hints, size_t *count,
				   uint64_t deadline_us,
				   CFMutableSetRef visited);

void ax_collect_hints_bfs(AXUIElementRef root, struct screen *scr,
			  const CGRect *window_frame,
			  struct hint *hints, size_t max_hints,
			  size_t *count, uint64_t deadline_us,
			  int skip_menu_containers,
			  int include_menu_attr);

#endif
