# Fork Changes

This is a fork of [warpd](https://github.com/rvaiya/warpd) by Raheman Vaiya, based on [B1T3X's fork](https://gitlab.com/B1T3X/warpd).

All credit for the original warpd implementation goes to the original author. This fork includes:
- Fixes for non-Latin keyboard layout support on macOS (from B1T3X's fork)
- Additional enhancements: visual ripple effects, horizontal scrolling, page scrolling

## Problem

When using warpd with a non-Latin keyboard layout (e.g., Hebrew, Russian, Arabic), the original version would become completely unresponsive - a "softlock" where no keys would register and the only way out was to kill the process.

Additionally, the copy/yank functionality (`copy_and_exit` config option) did not work correctly with non-Latin layouts, particularly in terminals using the Kitty keyboard protocol.

## Changes

### 1. Fix non-Latin keyboard layout softlock (`f8c49f7`)

**Problem:** Key bindings were matched using layout-dependent lookups. With a non-Latin layout active, characters like "h", "j", "k", "l" don't exist in the keymap, causing all key matching to fail.

**Solution:** Added layout-independent QWERTY keycode mapping functions:
- `input_code_to_qwerty()` - convert keycode to QWERTY character
- `input_qwerty_to_code()` - convert QWERTY character to keycode
- `input_special_to_code()` - handle special keys (esc, backspace, etc.)

Modified `input_parse_string()` in `src/input.c` to use QWERTY-based lookup for single printable characters, falling back to layout-dependent lookup for special keys.

**Files modified:**
- `src/input.c`
- `src/platform.h`
- `src/platform/macos/input.m`
- `src/platform/macos/macos.h`
- `src/platform/macos/macos.m`
- `src/platform/linux/wayland/wayland.c`
- `src/platform/linux/wayland/wayland.h`
- `src/platform/linux/X/input.c`
- `src/platform/linux/X/X.h`
- `src/platform/linux/X/X.c`
- `src/platform/windows/windows.c`

### 2. Use hardcoded keycodes for copy selection (`81487d6`)

**Problem:** The copy function used `input_lookup_code("c")` which fails on non-Latin layouts.

**Solution:** Use hardcoded keycodes (56 for Command, 9 for 'c') instead of layout-dependent lookup.

**Files modified:**
- `src/platform/macos/macos.m`

### 3. Use Accessibility API for copy in Kitty terminal (`6103652`)

**Problem:** Kitty terminal's keyboard protocol interprets synthetic key events based on the current keyboard layout, causing Cmd+C to produce wrong characters with non-Latin layouts (e.g., `^[[1489;9u` instead of copy).

**Solution:** Detect when the focused application is Kitty (by bundle ID) and use macOS Accessibility API to read selected text directly, bypassing the keyboard protocol.

**Files modified:**
- `src/platform/macos/macos.m`

### 4. Fix copy detection to check focused app (`f7a3ce9`)

**Problem:** The initial Kitty detection checked environment variables (`KITTY_WINDOW_ID`, `TERM`), which reflect where warpd was launched from, not the current focused application. This caused the accessibility-based copy to be used for all apps when warpd was launched from Kitty.

**Solution:** Use Accessibility API to get the focused application's bundle ID and only use accessibility-based copy when the focused app is actually Kitty.

**Files modified:**
- `src/platform/macos/macos.m`

### 5. Code cleanup (`2668918`)

**Fixes:**
- Memory leak: Added missing `CFRelease(kbd)` in `update_keymap()` - leaked on every keyboard layout change
- Consolidated duplicate accessibility API code into `get_focused_app()` helper
- Removed unused `hider` variable in mouse.m
- Fixed header signature mismatch for `create_overlay_window()`

**Files modified:**
- `src/platform/macos/input.m`
- `src/platform/macos/macos.m`
- `src/platform/macos/mouse.m`
- `src/platform/macos/macos.h`

## Compatibility

These changes are backward compatible:
- English/Latin keyboard layouts work exactly as before
- Non-Kitty terminals use the standard synthetic Cmd+C approach
- The accessibility-based copy is only used when necessary (Kitty + non-Latin layout)

## Testing

Tested on macOS with:
- Hebrew keyboard layout
- English keyboard layout
- Kitty terminal
- Terminal.app
- iTerm2
- Slack (GUI app)
