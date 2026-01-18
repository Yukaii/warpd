/*
 * warpd - A modal keyboard-driven pointing system.
 *
 * © 2019 Raheman Vaiya (see: LICENSE).
 */

#include "ax_debug.h"
#include "ax_helpers.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* File-based debug logging - safer than stderr */
static FILE *ax_debug_file = NULL;

int ax_debug_enabled(void)
{
	const char *value = getenv("WARPD_AX_DEBUG");
	if (value && value[0] != '0')
		return 1;

	value = getenv("WARPD_AX_DEBUG_VERBOSE");
	if (value && value[0] != '0')
		return 1;

	value = getenv("WARPD_AX_DUMP");
	return value && value[0] != '0';
}

void ax_debug_open(void)
{
	if (!ax_debug_enabled())
		return;
	if (ax_debug_file)
		return;
	ax_debug_file = fopen("/tmp/warpd_ax_debug.log", "w");
	if (ax_debug_file) {
		fprintf(ax_debug_file, "=== WARPD AX Debug Log ===\n\n");
		fflush(ax_debug_file);
	}
}

void ax_debug_close(void)
{
	if (ax_debug_file) {
		fclose(ax_debug_file);
		ax_debug_file = NULL;
	}
}

void ax_debug_log(const char *fmt, ...)
{
	if (!ax_debug_file)
		return;
	va_list args;
	va_start(args, fmt);
	vfprintf(ax_debug_file, fmt, args);
	va_end(args);
	fflush(ax_debug_file);
}

static size_t ax_debug_node_budget(void)
{
	const char *val = getenv("WARPD_AX_DEBUG_NODES");
	if (val)
		return (size_t)atol(val);
	return 500; /* Default: dump up to 500 nodes */
}

static int ax_debug_depth(void)
{
	const char *val = getenv("WARPD_AX_DEBUG_DEPTH");
	if (val)
		return atoi(val);
	return 10; /* Default: max depth of 10 levels */
}

static void ax_debug_indent(int depth)
{
	for (int i = 0; i < depth; i++)
		ax_debug_log("  ");
}

static void ax_debug_dump_element(AXUIElementRef element, int depth,
				  int max_depth, size_t *node_budget)
{
	if (!element || depth > max_depth || *node_budget == 0)
		return;

	(*node_budget)--;

	char role[128];
	char title[256];
	char role_desc[128];
	char value[256];
	char url[256];
	int enabled = 1;
	int hidden = 0;
	CGPoint position = CGPointZero;
	CGSize size = CGSizeZero;
	int has_frame = ax_get_position_size(element, &position, &size);

	ax_copy_string_attr(element, kAXRoleAttribute, role, sizeof role);
	ax_copy_string_attr(element, kAXTitleAttribute, title, sizeof title);
	ax_copy_string_attr(element, kAXRoleDescriptionAttribute, role_desc,
			    sizeof role_desc);
	ax_copy_string_attr(element, kAXValueAttribute, value, sizeof value);
	ax_copy_string_attr(element, kAXURLAttribute, url, sizeof url);

	ax_get_bool_attr(element, kAXEnabledAttribute, &enabled);
	ax_get_bool_attr(element, kAXHiddenAttribute, &hidden);

	ax_debug_indent(depth);
	ax_debug_log("role=%s title=%s desc=%s enabled=%d hidden=%d value=%s url=%s",
		role[0] ? role : "-", title[0] ? title : "-",
		role_desc[0] ? role_desc : "-", enabled, hidden,
		value[0] ? value : "-", url[0] ? url : "-");
	if (has_frame) {
		ax_debug_log(" frame=[%.0f,%.0f %.0fx%.0f]",
			position.x, position.y, size.width, size.height);
	}
	ax_debug_log("\n");

	CFArrayRef children = ax_copy_child_array(element, kAXChildrenAttribute);
	if (!children)
		children = ax_copy_child_array(element, ax_visible_children_attribute());
	if (!children)
		children = ax_copy_child_array(element,
					ax_children_in_navigation_order_attribute());
	if (!children)
		children = ax_copy_child_array(element, ax_contents_attribute());

	if (!children)
		return;

	CFIndex child_count = CFArrayGetCount(children);
	for (CFIndex i = 0; i < child_count; i++) {
		CFTypeRef child_ref = CFArrayGetValueAtIndex(children, i);
		if (!child_ref)
			continue;
		/* Validate it's an AXUIElement before casting */
		if (CFGetTypeID(child_ref) != AXUIElementGetTypeID())
			continue;
		AXUIElementRef child = (AXUIElementRef)child_ref;
		ax_debug_dump_element(child, depth + 1, max_depth, node_budget);
		if (*node_budget == 0)
			break;
	}

	CFRelease(children);
}

void ax_debug_dump_tree(AXUIElementRef root, const char *label)
{
	if (!ax_debug_enabled() || !root)
		return;

	ax_debug_open();
	size_t node_budget = ax_debug_node_budget();
	int max_depth = ax_debug_depth();
	ax_debug_log("[DUMP] === AX debug dump (%s) ===\n", label);
	ax_debug_dump_element(root, 0, max_depth, &node_budget);
	ax_debug_log("\n");
}

int ax_debug_dump_enabled(void)
{
	const char *val = getenv("WARPD_AX_DUMP");
	return val && val[0] != '0';
}

void ax_debug_log_element(AXUIElementRef element, const char *status,
			  int x, int y)
{
	if (!ax_debug_file || !element)
		return;

	char role[128] = {0};
	char title[128] = {0};
	char url[256] = {0};
	char desc[128] = {0};
	CGPoint position = CGPointZero;
	CGSize size = CGSizeZero;

	ax_copy_string_attr(element, kAXRoleAttribute, role, sizeof role);
	ax_copy_string_attr(element, kAXTitleAttribute, title, sizeof title);
	ax_copy_string_attr(element, kAXURLAttribute, url, sizeof url);
	ax_copy_string_attr(element, kAXDescriptionAttribute, desc, sizeof desc);
	ax_get_position_size(element, &position, &size);

	/* Truncate long strings for readability */
	if (strlen(title) > 40) {
		title[37] = '.';
		title[38] = '.';
		title[39] = '.';
		title[40] = '\0';
	}
	if (strlen(url) > 60) {
		url[57] = '.';
		url[58] = '.';
		url[59] = '.';
		url[60] = '\0';
	}
	if (strlen(desc) > 40) {
		desc[37] = '.';
		desc[38] = '.';
		desc[39] = '.';
		desc[40] = '\0';
	}

	ax_debug_log("[%s] role=%-20s pos=(%4.0f,%4.0f) size=(%4.0fx%4.0f)",
		status, role[0] ? role : "?",
		position.x, position.y, size.width, size.height);

	if (x >= 0 && y >= 0)
		ax_debug_log(" hint=(%d,%d)", x, y);
	if (title[0])
		ax_debug_log(" title=\"%s\"", title);
	if (url[0])
		ax_debug_log(" url=\"%s\"", url);
	if (desc[0])
		ax_debug_log(" desc=\"%s\"", desc);
	ax_debug_log("\n");
}

int ax_debug_verbose(void)
{
	const char *val = getenv("WARPD_AX_DEBUG_VERBOSE");
	return val && val[0] != '0';
}
