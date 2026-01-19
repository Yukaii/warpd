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

### 6. Scrolling enhancements (`c9f47b0`, `c6f7705`, `050a4a9`)

**Additions:**
- Horizontal scrolling controls and bindings
- Page up/down scrolling via large scroll events
- Home/end scrolling on macOS implemented via key emulation for reliability

**Files modified:**
- `src/scroll.c`
- `src/config.c`
- `src/input.c`
- `src/platform/macos/input.m`
- `src/platform/macos/macos.m`
- `src/platform/linux/X/X.c`
- `src/platform/linux/wayland/wayland.c`

### 7. Visual feedback (ripples + cursor effects) (`a10bd89`, `485b0d2`, `63c3c5c`)

**Additions:**
- Ripple animation on clicks and jump commands
- Extra visual feedback for warp/jump actions
- Cursor entry pulse effect when entering normal mode (macOS)

**Files modified:**
- `src/platform/macos/macos.m`
- `src/normal.c`
- `src/grid.c`
- `src/hint.c`
- `src/mode-loop.c`
- `src/config.c`

### 8. Cursor customization (macOS) (`45e1375`)

**Additions:**
- Support for system cursor packs and custom cursor files
- Optional cursor halo and entry pulse when using non-default cursors

**Files modified:**
- `src/platform/macos/mouse.m`
- `src/platform/macos/macos.m`
- `src/config.c`

### 9. Input and mode behavior (`dd856c9`, `afe291f`, `8ad5e4d`)

**Additions:**
- Hold mouse buttons while key is held (`hold_buttons`)
- Rapid auto-click mode with configurable interval
- Fix history updates when enabling hold buttons

**Files modified:**
- `src/config.c`
- `src/input.c`
- `src/normal.c`
- `src/mode-loop.c`
- `src/mouse.c`

### 10. Hint customization (`49b3cc2`, `a62b3f8`)

**Additions:**
- Configurable hint appearance (colors, size, border radius)
- Monospace font default for clearer label rendering

**Files modified:**
- `src/config.c`
- `src/platform/macos/macos.m`
- `src/platform/linux/X/X.c`
- `src/platform/linux/wayland/wayland.c`

### 11. Find mode (macOS) and accessibility improvements (`199114e` .. `3607e9e`)

**Additions:**
- New find mode (`Alt-Cmd-f`) that hints interactable UI elements in the frontmost app
- Accessibility-based traversal of windows, menus, and controls
- Chrome/Electron-specific handling and stability/performance improvements

**Files modified:**
- `src/platform/macos/macos.m`
- `src/platform/macos/ax_helpers.m`
- `src/platform/macos/ax_menu.m`
- `src/hint.c`
- `src/mode-loop.c`

### 12. macOS behavior fixes (`398ec37`, `0d067c9`)

**Fixes:**
- Preserve modifier mouse interactions on macOS
- Improve edge-push behavior for auto-hiding Dock/menu bar

**Files modified:**
- `src/platform/macos/mouse.m`
- `src/mouse.c`

### 13. Multi-monitor targeting and find-mode fixes (`unreleased`)

**Additions/Fixes:**
- Screen selection now sets an active screen for mode-scoped targeting
- Cursor and hint modes respect the selected screen across monitors
- Find mode better handles external-monitor AX coordinates
- History hint layout uses the current monitor dimensions

**Files modified:**
- `src/screen.c`
- `src/warpd.h`
- `src/normal.c`
- `src/grid.c`
- `src/hint.c`
- `src/mouse.c`
- `src/mode-loop.c`
- `src/platform/macos/ax_menu.m`

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
