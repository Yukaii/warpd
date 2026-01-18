/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#ifndef WARPED_AX_DEBUG_H
#define WARPED_AX_DEBUG_H

#include <ApplicationServices/ApplicationServices.h>

int ax_debug_enabled(void);
int ax_debug_dump_enabled(void);
int ax_debug_verbose(void);
void ax_debug_open(void);
void ax_debug_close(void);
void ax_debug_log(const char *fmt, ...);
void ax_debug_dump_tree(AXUIElementRef root, const char *label);
void ax_debug_log_element(AXUIElementRef element, const char *status,
			  int x, int y);

#endif
