# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

warpd is a modal keyboard-driven interface for mouse manipulation, supporting macOS, Linux (X11/Wayland), and Windows. This is a fork with fixes for non-Latin keyboard layouts on macOS (see FORK_CHANGES.md).

The project provides three modal interfaces:
- **Hint mode**: Label-based point-and-click
- **Grid mode**: Recursive quadrant-based navigation
- **Normal mode**: Vim-like cursor movement with hjkl keys

## Build Commands

### macOS (Primary Platform)
```bash
# Development build
make

# The binary is output to: bin/warpd
# A code signing script runs automatically: ./codesign/sign.sh

# Install (installs to /usr/local and creates launchd service)
sudo make install

# Uninstall
sudo make uninstall

# Clean build artifacts
make clean

# Release build (universal binary for arm64 and x86_64)
make rel
```

### Linux
```bash
# Build with both X11 and Wayland support (default)
make

# Build X11 only
DISABLE_WAYLAND=1 make

# Build Wayland only
DISABLE_X=1 make
```

### Running
```bash
# Run directly from build directory
./bin/warpd

# Daemon mode (background, used by launchd on macOS)
./bin/warpd --daemon

# One-shot modes (for Wayland compositor bindings)
./bin/warpd --hint
./bin/warpd --grid
./bin/warpd --normal
```

## Architecture

### Platform Abstraction Layer

The core warpd logic is platform-agnostic. Platform-specific code is isolated behind function pointers defined in `src/platform.h`:

```
struct platform {
    void (*mouse_move)(screen_t scr, int x, int y);
    void (*mouse_click)(int btn);
    void (*scroll)(int direction);
    void (*scroll_amount)(int direction, int amount);
    void (*key_tap)(uint8_t code, uint8_t mods);  // Emulate key tap (macOS only)
    void (*input_grab_keyboard)();
    uint8_t (*input_lookup_code)(const char *name, int *shifted);
    char (*input_code_to_qwerty)(uint8_t code);
    uint8_t (*input_qwerty_to_code)(char c);
    void (*screen_draw_box)(screen_t scr, int x, int y, int w, int h, const char *color);
    void (*trigger_ripple)(screen_t scr, int x, int y);
    int (*has_active_ripples)(screen_t scr);
    // ... many more functions
};
```

Platform implementations live in:
- `src/platform/macos/` - Cocoa, Carbon, Core Graphics
- `src/platform/linux/X/` - X11/Xlib
- `src/platform/linux/wayland/` - wlroots protocol extensions
- `src/platform/windows/` - Windows API

### Core Components

**Mode Implementations** (in `src/`):
- `normal.c` - Vim-like cursor movement mode
- `grid.c` - Recursive grid navigation
- `hint.c` - Label generation and hint mode logic
- `history.c` - Cursor position history (in-memory)
- `histfile.c` - Persistent history on disk

**Support Systems**:
- `input.c` - Keyboard event abstraction and config matching
- `config.c` - Configuration system with defaults and file parsing
- `mouse.c` - Physics-based cursor movement (acceleration)
- `scroll.c` - Physics-based scrolling (momentum)
- `screen.c` - Multi-monitor support
- `mode-loop.c` - Mode switching orchestrator

**Entry Points**:
- `warpd.c` - Main entry point, CLI argument parsing
- `daemon.c` - Background daemon for hotkey detection

### Layout-Independent Input (Non-Latin Layout Support)

This fork fixes a critical issue where warpd became unresponsive with non-Latin keyboard layouts. The solution uses **QWERTY-based keycodes** instead of layout-dependent character matching:

**Key Functions**:
- `input_code_to_qwerty(code)` - Map hardware keycode → QWERTY character (e.g., keycode 36 → 'j')
- `input_qwerty_to_code(char)` - Map QWERTY character → hardware keycode (e.g., 'j' → keycode 36)
- `input_special_to_code(name)` - Handle special keys ("esc", "backspace", etc.)

These functions are implemented per-platform:
- **macOS**: Uses Carbon keycodes (hardware-based, layout-independent)
- **Linux X11**: Uses evdev keycodes (hardware-based)
- **Linux Wayland**: Uses evdev keycodes
- **Windows**: Uses virtual key codes

When parsing config keys like `left: h`, the system:
1. Tries QWERTY mapping first: `input_qwerty_to_code('h')` → keycode 36
2. Falls back to special keys: `input_special_to_code("escape")` → keycode 1
3. Falls back to layout-dependent lookup for non-ASCII

This ensures keys like "hjkl" work regardless of active keyboard layout.

### Configuration System

Config entries are defined in `src/config.c` with type metadata:

```c
struct config_option {
    const char *key;
    const char *default_value;
    const char *description;
    enum option_type type;  // OPT_STRING, OPT_INT, OPT_KEY, OPT_BUTTON
};
```

Configuration is loaded from:
1. Built-in defaults (`config.c`)
2. `~/.config/warpd/config` (overrides defaults)

**Key Config Categories**:
- Mode activation keys (e.g., `activation_key_hint: A-M-x`)
- Movement keys (e.g., `left: h`, `down: j`)
- Scroll keys (e.g., `scroll_up: e`, `scroll_left: t`)
- Appearance (e.g., `hint_font: Menlo-Regular`, `cursor_color: #cc0000`)
- Physics (e.g., `max_speed: 1200`, `acceleration: 2900`)
- Visual effects (e.g., `ripple_enabled: 1`, `ripple_max_radius: 50`)

### Drawing and Overlay System (macOS)

On macOS, drawing uses overlay windows with a hook-based rendering system:

```c
struct window {
    NSWindow *win;
    size_t nr_hooks;
    struct drawing_hook hooks[MAX_DRAWING_HOOKS];
};

struct screen {
    int x, y, w, h;  // Dimensions (Lower-Left Origin in Cocoa)
    struct box boxes[MAX_BOXES];
    struct ripple ripples[MAX_RIPPLES];
    struct hint hints[MAX_HINTS];
    struct window *overlay;
};
```

**Drawing Process**:
1. Platform code registers draw hooks with `window_register_draw_hook()`
2. Each hook is called during overlay redraw
3. Hooks draw using Cocoa primitives: `macos_draw_box()`, `macos_draw_circle()`, `macos_draw_text()`
4. `platform->commit()` flushes changes and shows/hides windows

**Coordinate Systems**:
- warpd uses Upper-Left Origin (ULO) throughout
- macOS Cocoa uses Lower-Left Origin (LLO)
- Conversion happens at the lowest level (in draw functions)

### Animation System (Ripples)

Ripple effects provide visual feedback on clicks and jumps:

```c
struct ripple {
    int x, y;
    float radius;
    uint64_t start_time;
    int active;
};
```

**Animation Loop**:
1. Trigger: `platform->trigger_ripple(scr, x, y)` creates new ripple
2. Update: Each redraw updates `radius` based on elapsed time
3. Render: Draw expanding circle with alpha fade-out
4. Continuous redraw: Each mode checks `platform->has_active_ripples()` and forces redraw when animations are active

Time-based animation ensures frame-rate independence:
```c
float progress = (float)elapsed_ms / (float)duration_ms;
radius = progress * max_radius;
alpha = 1.0 - progress;  // Fade out
```

**Where Ripples Are Triggered**:
- **Normal Mode** (`src/normal.c`):
  - Clicks: `m`, `,`, `.` (buttons)
  - Jumps: `H`, `M`, `L` (top/middle/bottom), `0`, `$` (start/end)
  - History navigation: `Ctrl-o`, `Ctrl-i`
  - Oneshot buttons: `n`, `-`, `/`

- **Grid Mode** (`src/grid.c`):
  - Quadrant selection: `u`, `i`, `j`, `k`
  - Grid cuts: `W`, `A`, `S`, `D`
  - Button clicks within grid mode

- **Hint Mode** (`src/hint.c`):
  - Final hint selection (when hint is chosen)

- **History Mode**:
  - Uses hint selection (ripple from hint.c)

- **Mode Loop** (`src/mode-loop.c`):
  - Oneshot mode clicks

**Configuration**:
```
ripple_enabled: 1               # Enable/disable ripples
ripple_color: #00ff0060         # RGBA hex (last 2 digits = alpha)
ripple_duration: 300            # Animation duration (ms)
ripple_max_radius: 50           # Maximum radius (pixels)
ripple_line_width: 2            # Circle line width
```

Color format: `#RRGGBBAA` where:
- `RR` = Red (00-FF)
- `GG` = Green (00-FF)
- `BB` = Blue (00-FF)
- `AA` = Alpha/transparency (00=transparent, FF=opaque)

Examples:
- `#ff000080` - Semi-transparent red
- `#00ff00ff` - Opaque green
- `#0080ff40` - Very transparent blue

Currently implemented only on macOS (X11/Wayland have NULL stubs).

## Development Notes

### Modifying Keybindings

To add new keybindings:

1. **Add config option** in `src/config.c`:
   ```c
   { "my_new_action", "m", "Description", OPT_KEY }
   ```

2. **Add to whitelist** in the mode file (e.g., `src/normal.c`):
   ```c
   const char *keys[] = {
       // ...
       "my_new_action",
   };
   config_input_whitelist(keys, sizeof keys / sizeof keys[0]);
   ```

3. **Handle the event**:
   ```c
   if (config_input_match(ev, "my_new_action")) {
       // Perform action
   }
   ```

### Hold Buttons (Mouse Down While Held)

Use the `hold_buttons` config option to bind keys that hold mouse buttons while pressed (default is unbound). These behave like press-and-hold for left/middle/right clicks and are released on key-up or when the mode exits.

Example:
```
hold_buttons: m , .
```

### Rapid Click (Auto-Click While Held)

Press `rapid_mode` (default `R`) to toggle rapid clicking, then press a mouse button key to start auto-clicking. Press `rapid_mode` again or press `esc` to stop. Configure speed with `rapid_click_interval`, and the HUD with `rapid_indicator_color`/`rapid_indicator_width`.

Example:
```
rapid_mode: R
rapid_click_interval: 40
rapid_indicator_color: #ff000080
rapid_indicator_width: 3
```

### Adding Platform Functions

When adding new platform capabilities:

1. **Declare** in `src/platform.h`:
   ```c
   void (*new_function)(int arg);
   ```

2. **Implement** in each platform:
   - `src/platform/macos/macos.m` → `osx_new_function()`
   - `src/platform/linux/X/X.c` → `x_new_function()`
   - `src/platform/linux/wayland/wayland.c` → `way_new_function()`

3. **Register** in platform init function:
   ```c
   platform->new_function = osx_new_function;
   ```

4. **Call with NULL checks** (for platforms that don't implement it):
   ```c
   if (platform->new_function)
       platform->new_function(arg);
   ```

### Scroll Implementation Details

warpd has two scroll modes:

**Smooth Scroll** (with momentum):
- Used by: `scroll_up`, `scroll_down`, `scroll_left`, `scroll_right`
- Physics: `scroll.c` implements acceleration/deceleration
- Platform: `platform->scroll(direction)` sends single scroll event
- Update: `scroll_tick()` called every event loop iteration (10ms)

**Instant Scroll** (no momentum):
- Used by: `scroll_page_down`, `scroll_page_up`
- Implementation: `platform->scroll_amount(direction, amount)` sends large single event
- macOS: Uses `CGEventCreateScrollWheelEvent()` with pixel units
- X11: Loops button press events (buttons 4/5/6/7)
- Amounts: Configurable via `scroll_page_amount` (default 800)

**Home/End Scroll** (keyboard emulation):
- Used by: `scroll_home`, `scroll_end`
- macOS: Uses `platform->key_tap()` to send Cmd+Up (Home) / Cmd+Down (End)
- Other platforms: Falls back to `scroll_amount` with `scroll_home_amount` (default 100000)
- Why keyboard emulation: Many apps cap or smooth large scroll events, but reliably handle Cmd+Up/Down as native Home/End shortcuts

### macOS Accessibility API Usage

The fork uses macOS Accessibility API in two cases:

1. **Kitty Terminal Copy Fix** (`src/platform/macos/macos.m:osx_copy_selection()`):
   - Detects focused app via `AXUIElementCopyAttributeValue()`
   - Reads selected text directly via `kAXSelectedTextAttribute`
   - Writes to clipboard via `NSPasteboard`
   - Bypasses Kitty's keyboard protocol issues with non-Latin layouts

2. **Focused Application Detection**:
   - `get_focused_app()` helper retrieves current focused app
   - Used to determine when to apply Kitty-specific workarounds

### macOS Key Emulation

The `platform->key_tap(code, mods)` function emits synthetic keyboard events:

**Implementation** (`src/platform/macos/input.m:osx_key_tap()`):
- Creates `CGEventCreateKeyboardEvent()` for key down and up
- Sets modifier flags via `CGEventSetFlags()` (Cmd, Ctrl, Shift, Alt)
- Posts events via `CGEventPost(kCGHIDEventTap, ...)`

**Passthrough Mechanism**:
- warpd intercepts all keyboard events via an event tap
- Synthetic events must be marked in `passthrough_keys[code]` array
- Without this, warpd would swallow its own emitted key events
- `passthrough_keys[code] += 2` marks both down and up events to pass through

**Usage**:
```c
if (platform->key_tap) {
    uint8_t code = platform->input_special_to_code("uparrow");
    platform->key_tap(code, PLATFORM_MOD_META);  /* Cmd+Up */
}
```

### Testing on macOS

After building, test with:

```bash
# Build
make

# Important: Grant Accessibility permissions on first run
# System Settings → Privacy & Security → Accessibility → Add bin/warpd

# Run interactively (Ctrl+C to stop)
./bin/warpd

# Activate modes
Alt-Cmd-x  # Hint mode
Alt-Cmd-g  # Grid mode
Alt-Cmd-c  # Normal mode

# Test with non-Latin layout
# 1. Switch macOS keyboard layout (e.g., Hebrew, Russian)
# 2. Activate normal mode (Alt-Cmd-c)
# 3. Press hjkl - should still work
```

If you rebuild and warpd becomes unresponsive:
```bash
# Reset accessibility permissions (removes all apps!)
sudo tccutil reset Accessibility

# Re-add bin/warpd to accessibility settings
```

### Common Pitfalls

1. **Coordinate system confusion**: Always convert ULO ↔ LLO at the lowest level (draw functions)
2. **Missing NULL checks**: Always check if platform function exists before calling
3. **Accessibility permissions**: macOS requires explicit permission grant for keyboard/mouse control
4. **Whitelist forgetting**: New config keys must be added to mode's whitelist array
5. **Animation freezing**: Animations need continuous redraw - check `has_active_ripples()`

## File Locations

- Config: `~/.config/warpd/config`
- History: `~/.local/share/warpd/history`
- Man page: `/usr/local/share/man/man1/warpd.1.gz`
- Binary: `/usr/local/bin/warpd`
- LaunchAgent (macOS): `/Library/LaunchAgents/com.warpd.warpd.plist`

## Related Documentation

- `README.md` - User-facing documentation with keymapping tables
- `warpd.1.md` - Man page with complete configuration reference
- `FORK_CHANGES.md` - Details on non-Latin layout fixes
- `CONTRIBUTING.md` - Bug reporting guidelines
