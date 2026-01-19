# GPUI Integration Plan for warpd

> **Goal**: Add a cross-platform GUI layer with configuration UI and an advanced command palette for UI element interaction (like Shortcat), while preserving the existing C daemon functionality.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Command Palette Design](#command-palette-design)
3. [Configuration UI Design](#configuration-ui-design)
4. [IPC Protocol](#ipc-protocol)
5. [Project Structure](#project-structure)
6. [Implementation Phases](#implementation-phases)
7. [Platform Considerations](#platform-considerations)
8. [Alternatives Considered](#alternatives-considered)

---

## Architecture Overview

### Hybrid Daemon + GUI Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    warpd daemon (existing C)                     │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                 Core Functionality                       │    │
│  │  • Keyboard interception (CGEventTap / XGrabKey)        │    │
│  │  • Mouse control (CGEvent / XTest)                      │    │
│  │  • Accessibility tree traversal (AXUIElement)           │    │
│  │  • Mode implementations (normal, grid, hint, find)      │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                 IPC Server (new)                         │    │
│  │  • Unix socket listener (/tmp/warpd.sock)               │    │
│  │  • JSON-based protocol                                   │    │
│  │  • Config read/write                                     │    │
│  │  • Element query API                                     │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
└──────────────────────────────┼───────────────────────────────────┘
                               │ Unix Socket IPC
                               │
┌──────────────────────────────┼───────────────────────────────────┐
│                    warpd-ui (new Rust/GPUI)                      │
│                              │                                   │
│  ┌───────────────────────────┴───────────────────────────────┐  │
│  │                    IPC Client                              │  │
│  │         • Async message passing                            │  │
│  │         • Connection management                            │  │
│  │         • Response handling                                │  │
│  └───────────────────────────┬───────────────────────────────┘  │
│                              │                                   │
│  ┌───────────────┬───────────┴───────────┬─────────────────┐   │
│  │               │                       │                 │   │
│  │  Command      │    Configuration      │   Overlay       │   │
│  │  Palette      │    UI (Settings)      │   Renderer      │   │
│  │               │                       │   (Future)      │   │
│  │  • Text input │    • Category tabs    │                 │   │
│  │  • Fuzzy find │    • Option editors   │   • Hints       │   │
│  │  • Element    │    • Key capture      │   • Grid        │   │
│  │    filtering  │    • Color pickers    │   • Cursor      │   │
│  │  • Quick      │    • Live preview     │                 │   │
│  │    actions    │                       │                 │   │
│  └───────────────┴───────────────────────┴─────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Why This Architecture?

| Decision | Rationale |
|----------|-----------|
| **Separate processes** | GUI crashes don't kill keyboard interception |
| **Keep C daemon** | Proven stability, no need to rewrite system-level code |
| **GPUI for UI** | GPU-accelerated, fast palette rendering, pure Rust |
| **IPC over FFI** | Cleaner separation, easier debugging, platform flexibility |

---

## Command Palette Design

### Concept: Advanced UI Element Interaction

The command palette extends find mode with **text-based filtering** and **rich element metadata**. Unlike system launchers (Spotlight, Raycast), this is specifically for interacting with UI elements in the focused application.

```
┌─────────────────────────────────────────────────────────────┐
│  🔍  search for button or link...                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ▸ Submit                          [Button]    ⌘ + Return  │
│    Primary action button                                    │
│                                                             │
│  ▸ Cancel                          [Button]    Escape      │
│    Dismiss dialog                                           │
│                                                             │
│  ▸ Learn More                      [Link]                  │
│    Opens documentation                                      │
│                                                             │
│  ▸ Email Input                     [TextField]             │
│    Enter your email address                                 │
│                                                             │
│  ▸ Remember Me                     [Checkbox]  ☑           │
│    Stay signed in                                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Features

#### 1. Text-Based Element Filtering

```
User types: "sub"
Matches:
  - "Submit" button
  - "Subscribe" link
  - "Subscription Settings" menu item
```

#### 2. Element Type Filtering

```
User types: ":button sub"   → Only buttons matching "sub"
User types: ":link"         → All links
User types: ":input"        → All text fields
User types: ":menu"         → Menu items
```

#### 3. Hierarchical Navigation

```
User types: "File > Save"   → Navigate menu hierarchy
User types: "Settings >"    → Show children of Settings
```

#### 4. Quick Actions

| Shortcut | Action |
|----------|--------|
| `Enter` | Click element |
| `Shift+Enter` | Right-click element |
| `Cmd+Enter` | Double-click element |
| `Tab` | Focus element (for text fields) |
| `Cmd+C` | Copy element text |
| `Cmd+Shift+C` | Copy element accessibility info |

#### 5. Element Metadata Display

For each element, show:
- **Label**: Visible text or accessibility label
- **Type**: Button, Link, TextField, Checkbox, etc.
- **Shortcut**: If the element has a keyboard shortcut
- **State**: Checked/unchecked, enabled/disabled
- **Hint**: Generated label (a, b, c...) for quick selection

### Data Flow

```
1. User activates palette (e.g., Alt+Cmd+Space)

2. Daemon receives activation
   └─► Calls collect_interactable_hints()
   └─► Traverses accessibility tree
   └─► Sends element list to UI via IPC

3. UI displays palette with elements
   └─► User types filter text
   └─► Fuzzy matching filters list
   └─► User selects element

4. UI sends action to daemon
   └─► Daemon performs click/focus
   └─► Triggers ripple animation
   └─► Palette closes (or stays for sticky mode)
```

### Element Data Structure

```rust
// Shared between daemon and UI

pub struct InteractableElement {
    // Identity
    pub id: u64,                    // Unique ID for this session
    pub hint_label: String,         // "a", "b", "aa", etc.

    // Display
    pub label: String,              // "Submit", "Cancel", etc.
    pub description: Option<String>, // Accessibility description
    pub element_type: ElementType,

    // Position
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub screen_id: i32,

    // State
    pub enabled: bool,
    pub focused: bool,
    pub checked: Option<bool>,      // For checkboxes/toggles

    // Hierarchy
    pub parent_label: Option<String>,
    pub depth: u32,

    // Actions
    pub supported_actions: Vec<ElementAction>,
    pub keyboard_shortcut: Option<String>,
}

pub enum ElementType {
    Button,
    Link,
    TextField,
    TextArea,
    Checkbox,
    RadioButton,
    ComboBox,
    Slider,
    Tab,
    MenuItem,
    MenuBarItem,
    ToolbarButton,
    ListItem,
    TableCell,
    TreeItem,
    Image,
    StaticText,
    Group,
    Window,
    Other(String),
}

pub enum ElementAction {
    Press,      // AXPress
    ShowMenu,   // AXShowMenu
    Pick,       // AXPick (for menus)
    Confirm,    // AXConfirm
    Cancel,     // AXCancel
    Increment,  // AXIncrement (sliders)
    Decrement,  // AXDecrement
}
```

### Fuzzy Matching Algorithm

```rust
use fuzzy_matcher::skim::SkimMatcherV2;

pub struct PaletteFilter {
    matcher: SkimMatcherV2,
    type_filter: Option<ElementType>,
}

impl PaletteFilter {
    pub fn filter(&self, query: &str, elements: &[InteractableElement]) -> Vec<FilteredElement> {
        // Parse type prefix (e.g., ":button search")
        let (type_filter, text_query) = self.parse_query(query);

        elements
            .iter()
            .filter(|e| self.matches_type(e, &type_filter))
            .filter_map(|e| {
                // Match against label, description, and parent
                let score = self.compute_score(e, &text_query)?;
                Some(FilteredElement { element: e.clone(), score })
            })
            .sorted_by(|a, b| b.score.cmp(&a.score))
            .take(50)  // Limit results
            .collect()
    }

    fn compute_score(&self, element: &InteractableElement, query: &str) -> Option<i64> {
        let label_score = self.matcher.fuzzy_match(&element.label, query);
        let desc_score = element.description.as_ref()
            .and_then(|d| self.matcher.fuzzy_match(d, query));

        // Prefer label matches, boost by element type priority
        let base_score = label_score.or(desc_score)?;
        let type_boost = self.type_priority(&element.element_type);

        Some(base_score + type_boost)
    }

    fn type_priority(&self, element_type: &ElementType) -> i64 {
        match element_type {
            ElementType::Button => 100,
            ElementType::Link => 90,
            ElementType::TextField => 80,
            ElementType::MenuItem => 70,
            _ => 0,
        }
    }
}
```

### Configuration Options

```
# New config options for command palette

palette_activation_key: A-M-space    # Activation hotkey
palette_sticky: 0                    # Stay open after action
palette_show_hints: 1                # Show hint labels (a, b, c)
palette_show_shortcuts: 1            # Show element keyboard shortcuts
palette_show_types: 1                # Show element type badges
palette_max_results: 50              # Maximum displayed results
palette_font: SF Pro Text            # Palette font
palette_font_size: 14                # Font size
palette_width: 600                   # Palette width in pixels
palette_bgcolor: #1c1c1e             # Background color
palette_fgcolor: #ffffff             # Text color
palette_selected_bgcolor: #3478f6    # Selected item background
palette_border_radius: 8             # Window corner radius
```

---

## Configuration UI Design

### Window Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  warpd Settings                                        ─  □  ✕  │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────────────────────────────────┐ │
│  │              │  │  🔍 Search settings...                   │ │
│  │  Categories  │  └──────────────────────────────────────────┘ │
│  │              │                                               │
│  │  ▸ Activation│  ┌──────────────────────────────────────────┐ │
│  │    Keys      │  │  Activation Keys                         │ │
│  │              │  │                                          │ │
│  │  ○ Movement  │  │  hint_activation_key                     │ │
│  │              │  │  Activates hint mode                     │ │
│  │  ○ Appearance│  │  ┌────────────────────┐  [Record]        │ │
│  │              │  │  │  ⌥ ⌘ X            │                   │ │
│  │  ○ Scrolling │  │  └────────────────────┘                  │ │
│  │              │  │                                          │ │
│  │  ○ Grid Mode │  │  ─────────────────────────────────────── │ │
│  │              │  │                                          │ │
│  │  ○ Hint Mode │  │  activation_key                          │ │
│  │              │  │  Activate normal movement mode           │ │
│  │  ○ Find Mode │  │  ┌────────────────────┐  [Record]        │ │
│  │              │  │  │  ⌥ ⌘ C            │                   │ │
│  │  ○ Animations│  │  └────────────────────┘                  │ │
│  │              │  │                                          │ │
│  │  ○ Command   │  │  ...                                     │ │
│  │    Palette   │  │                                          │ │
│  │              │  └──────────────────────────────────────────┘ │
│  └──────────────┘                                               │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  [Reset to Defaults]              [Cancel]  [Save]       │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Option Categories

| Category | Options |
|----------|---------|
| **Activation Keys** | hint_activation_key, find_activation_key, grid_activation_key, activation_key, palette_activation_key |
| **Movement** | left, down, up, right, top, middle, bottom, start, end, speed, max_speed, acceleration |
| **Appearance** | cursor_color, cursor_size, cursor_pack, cursor_halo_*, indicator_* |
| **Scrolling** | scroll_up, scroll_down, scroll_speed, scroll_acceleration, scroll_page_amount |
| **Grid Mode** | grid_nr, grid_nc, grid_size, grid_color, grid_keys, grid_up/down/left/right |
| **Hint Mode** | hint_chars, hint_font, hint_size, hint_bgcolor, hint_fgcolor, hint_border_* |
| **Find Mode** | find_activation_key, (inherits hint appearance) |
| **Animations** | ripple_enabled, ripple_color, ripple_duration, cursor_entry_effect |
| **Command Palette** | palette_*, (new options) |
| **Advanced** | repeat_interval, oneshot_timeout, drag_button |

### UI Components

#### Key Binding Capture

```rust
pub struct KeyBindingInput {
    value: String,           // "A-M-x"
    recording: bool,
    captured_mods: u8,
    captured_code: Option<u8>,
}

impl KeyBindingInput {
    fn render(&self, cx: &mut ViewContext<Self>) -> impl IntoElement {
        div()
            .flex()
            .items_center()
            .gap_2()
            .child(
                div()
                    .px_3()
                    .py_1()
                    .rounded_md()
                    .bg(if self.recording { theme.accent } else { theme.input_bg })
                    .child(self.format_display())
            )
            .child(
                button("Record")
                    .on_click(|_, cx| self.start_recording(cx))
            )
    }

    fn format_display(&self) -> String {
        // Convert "A-M-x" to "⌥ ⌘ X" for display
        format_key_for_display(&self.value)
    }
}
```

#### Color Picker

```rust
pub struct ColorPicker {
    value: String,           // "#ff4500" or "#ff450080"
    show_alpha: bool,
}

impl ColorPicker {
    fn render(&self, cx: &mut ViewContext<Self>) -> impl IntoElement {
        div()
            .flex()
            .items_center()
            .gap_2()
            .child(
                // Color swatch preview
                div()
                    .size_6()
                    .rounded_sm()
                    .bg(parse_color(&self.value))
                    .border_1()
                    .border_color(theme.border)
            )
            .child(
                // Hex input
                text_input()
                    .value(&self.value)
                    .on_change(|v, cx| self.set_value(v, cx))
            )
            .child(
                // Picker button
                button("...")
                    .on_click(|_, cx| self.show_picker(cx))
            )
    }
}
```

#### Integer Slider

```rust
pub struct IntSlider {
    value: i32,
    min: i32,
    max: i32,
    label: String,
}

impl IntSlider {
    fn render(&self, cx: &mut ViewContext<Self>) -> impl IntoElement {
        div()
            .flex()
            .items_center()
            .gap_4()
            .child(
                slider()
                    .min(self.min)
                    .max(self.max)
                    .value(self.value)
                    .on_change(|v, cx| self.set_value(v, cx))
            )
            .child(
                text_input()
                    .w_16()
                    .value(&self.value.to_string())
                    .on_change(|v, cx| self.parse_and_set(v, cx))
            )
    }
}
```

### Live Preview

For appearance options, show a live preview:

```
┌─────────────────────────────────────────────────────────────┐
│  Hint Appearance                                            │
│                                                             │
│  hint_bgcolor: [#1c1c1e] [■]                               │
│  hint_fgcolor: [#a1aba7] [■]                               │
│  hint_size:    [20] ─────●─────                            │
│  hint_font:    [Menlo-Regular    ▼]                        │
│                                                             │
│  Preview:                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                                                     │   │
│  │      ┌───┐  ┌───┐  ┌───┐                          │   │
│  │      │ a │  │ b │  │ c │                          │   │
│  │      └───┘  └───┘  └───┘                          │   │
│  │                                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## IPC Protocol

### Transport

- **Socket**: Unix domain socket at `/tmp/warpd.sock`
- **Format**: JSON-RPC 2.0 style messages
- **Encoding**: UTF-8, newline-delimited

### Message Types

```rust
// Request from UI to Daemon
#[derive(Serialize, Deserialize)]
pub struct Request {
    pub id: u64,
    pub method: String,
    pub params: Option<serde_json::Value>,
}

// Response from Daemon to UI
#[derive(Serialize, Deserialize)]
pub struct Response {
    pub id: u64,
    pub result: Option<serde_json::Value>,
    pub error: Option<RpcError>,
}

// Notification (no response expected)
#[derive(Serialize, Deserialize)]
pub struct Notification {
    pub method: String,
    pub params: Option<serde_json::Value>,
}

#[derive(Serialize, Deserialize)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
}
```

### Methods

#### Configuration

```json
// Get all config
{ "id": 1, "method": "config.get_all" }
→ { "id": 1, "result": { "entries": [...] } }

// Get single value
{ "id": 2, "method": "config.get", "params": { "key": "hint_bgcolor" } }
→ { "id": 2, "result": { "value": "#1c1c1e" } }

// Set value
{ "id": 3, "method": "config.set", "params": { "key": "hint_bgcolor", "value": "#2c2c2e" } }
→ { "id": 3, "result": { "ok": true } }

// Reload config from file
{ "id": 4, "method": "config.reload" }
→ { "id": 4, "result": { "ok": true } }

// Get schema (types, defaults, descriptions)
{ "id": 5, "method": "config.get_schema" }
→ { "id": 5, "result": { "categories": [...] } }
```

#### Element Queries (for Command Palette)

```json
// Get all interactable elements
{ "id": 10, "method": "elements.list" }
→ { "id": 10, "result": { "elements": [...], "screen_id": 0 } }

// Perform action on element
{ "id": 11, "method": "elements.click", "params": { "id": 42 } }
→ { "id": 11, "result": { "ok": true } }

// Focus element (for text fields)
{ "id": 12, "method": "elements.focus", "params": { "id": 42 } }
→ { "id": 12, "result": { "ok": true } }

// Get element details
{ "id": 13, "method": "elements.info", "params": { "id": 42 } }
→ { "id": 13, "result": { "element": {...} } }
```

#### Mode Control

```json
// Activate mode
{ "id": 20, "method": "mode.activate", "params": { "mode": "hint" } }
→ { "id": 20, "result": { "ok": true } }

// Get current mode
{ "id": 21, "method": "mode.current" }
→ { "id": 21, "result": { "mode": "normal", "active": true } }

// Exit current mode
{ "id": 22, "method": "mode.exit" }
→ { "id": 22, "result": { "ok": true } }
```

#### Status & System

```json
// Get daemon status
{ "id": 30, "method": "status" }
→ { "id": 30, "result": { "version": "1.3.5", "uptime": 3600, "mode": null } }

// Quit daemon
{ "id": 31, "method": "quit" }
→ { "id": 31, "result": { "ok": true } }
```

#### Notifications (Daemon → UI)

```json
// Mode changed
{ "method": "mode.changed", "params": { "mode": "hint", "active": true } }

// Config file changed
{ "method": "config.changed", "params": { "keys": ["hint_bgcolor"] } }

// Request palette display
{ "method": "palette.show", "params": { "elements": [...] } }
```

### C Implementation (Daemon Side)

```c
// src/ipc.h

#define IPC_SOCKET_PATH "/tmp/warpd.sock"
#define IPC_MAX_MSG_SIZE 65536

struct ipc_server {
    int socket_fd;
    int client_fds[16];
    size_t nr_clients;
};

void ipc_init(struct ipc_server *server);
void ipc_poll(struct ipc_server *server, int timeout_ms);
void ipc_broadcast(struct ipc_server *server, const char *method, const char *params_json);
void ipc_respond(int client_fd, uint64_t id, const char *result_json);
void ipc_error(int client_fd, uint64_t id, int code, const char *message);
```

```c
// src/ipc.c

#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include "cJSON.h"  // Lightweight JSON library

void ipc_handle_message(struct ipc_server *server, int client_fd, const char *msg) {
    cJSON *req = cJSON_Parse(msg);
    if (!req) {
        ipc_error(client_fd, 0, -32700, "Parse error");
        return;
    }

    uint64_t id = cJSON_GetObjectItem(req, "id")->valueint;
    const char *method = cJSON_GetObjectItem(req, "method")->valuestring;

    if (strcmp(method, "config.get_all") == 0) {
        char *json = config_to_json();
        ipc_respond(client_fd, id, json);
        free(json);
    }
    else if (strcmp(method, "config.set") == 0) {
        cJSON *params = cJSON_GetObjectItem(req, "params");
        const char *key = cJSON_GetObjectItem(params, "key")->valuestring;
        const char *value = cJSON_GetObjectItem(params, "value")->valuestring;
        config_set(key, value);
        ipc_respond(client_fd, id, "{\"ok\":true}");
    }
    else if (strcmp(method, "elements.list") == 0) {
        struct hint hints[MAX_HINTS];
        size_t n = platform->collect_interactable_hints(current_screen, hints, MAX_HINTS);
        char *json = hints_to_json(hints, n);
        ipc_respond(client_fd, id, json);
        free(json);
    }
    // ... more methods

    cJSON_Delete(req);
}
```

---

## Project Structure

```
warpd/
├── src/                              # Existing C daemon code
│   ├── warpd.c                       # Entry point
│   ├── daemon.c                      # Daemon loop
│   ├── ipc.c                         # NEW: IPC server
│   ├── ipc.h                         # NEW: IPC declarations
│   ├── config.c                      # Config system (extend for IPC)
│   ├── normal.c                      # Normal mode
│   ├── grid.c                        # Grid mode
│   ├── hint.c                        # Hint/find mode
│   ├── platform.h                    # Platform abstraction
│   └── platform/
│       ├── macos/                    # macOS implementation
│       ├── linux/X/                  # X11 implementation
│       └── linux/wayland/            # Wayland implementation
│
├── ui/                               # NEW: Rust/GPUI application
│   ├── Cargo.toml
│   ├── build.rs                      # Build script
│   └── src/
│       ├── main.rs                   # Entry point
│       ├── app.rs                    # GPUI Application setup
│       │
│       ├── ipc/                      # IPC client
│       │   ├── mod.rs
│       │   ├── client.rs             # Socket connection
│       │   ├── protocol.rs           # Message types
│       │   └── handler.rs            # Response handling
│       │
│       ├── state/                    # Application state
│       │   ├── mod.rs
│       │   ├── config.rs             # Config state model
│       │   └── elements.rs           # Element list state
│       │
│       ├── views/                    # UI Views
│       │   ├── mod.rs
│       │   ├── palette.rs            # Command palette
│       │   ├── settings.rs           # Settings window
│       │   └── preview.rs            # Appearance preview
│       │
│       ├── components/               # Reusable UI components
│       │   ├── mod.rs
│       │   ├── key_input.rs          # Key binding capture
│       │   ├── color_picker.rs       # Color selection
│       │   ├── slider.rs             # Int slider
│       │   ├── font_picker.rs        # Font selection
│       │   ├── search_bar.rs         # Search input
│       │   └── category_list.rs      # Sidebar navigation
│       │
│       └── theme.rs                  # Visual styling constants
│
├── docs/                             # Documentation
│   └── GPUI_INTEGRATION_PLAN.md      # This file
│
├── Makefile                          # Main build (modified)
└── mk/
    ├── macos.mk
    ├── linux.mk
    └── rust.mk                       # NEW: Rust build rules
```

### Cargo.toml

```toml
[package]
name = "warpd-ui"
version = "0.1.0"
edition = "2021"

[dependencies]
gpui = "0.1"                    # GPUI framework
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tokio = { version = "1", features = ["net", "io-util", "sync", "rt-multi-thread"] }
fuzzy-matcher = "0.3"           # Fuzzy matching
dirs = "5.0"                    # Config directories
tracing = "0.1"                 # Logging
tracing-subscriber = "0.3"

[target.'cfg(target_os = "macos")'.dependencies]
cocoa = "0.25"                  # macOS bindings (if needed)

[target.'cfg(target_os = "linux")'.dependencies]
# Linux-specific deps if needed

[profile.release]
opt-level = 3
lto = true
```

### Build Integration

```makefile
# mk/rust.mk

RUST_DIR = ui
RUST_TARGET = $(RUST_DIR)/target/release/warpd-ui
RUST_SOURCES = $(shell find $(RUST_DIR)/src -name '*.rs')

$(RUST_TARGET): $(RUST_DIR)/Cargo.toml $(RUST_SOURCES)
	cd $(RUST_DIR) && cargo build --release

rust: $(RUST_TARGET)

clean-rust:
	cd $(RUST_DIR) && cargo clean

install-rust: $(RUST_TARGET)
	install -m 755 $(RUST_TARGET) $(PREFIX)/bin/warpd-ui

.PHONY: rust clean-rust install-rust
```

```makefile
# Modify main Makefile

ifeq ($(PLATFORM), macos)
    include mk/macos.mk
    include mk/rust.mk
    all: warpd rust
    install: install-warpd install-rust
    clean: clean-warpd clean-rust
endif
```

---

## Implementation Phases

### Phase 1: Foundation (2-3 weeks)

**Goal**: Establish IPC communication between daemon and UI

#### 1.1 Daemon IPC Server
- [ ] Add cJSON dependency for JSON parsing
- [ ] Implement Unix socket server in `src/ipc.c`
- [ ] Handle basic methods: `status`, `config.get_all`
- [ ] Integrate with daemon event loop
- [ ] Test with netcat/socat

#### 1.2 Rust Project Setup
- [ ] Create `ui/` directory structure
- [ ] Set up Cargo.toml with dependencies
- [ ] Implement IPC client (async socket)
- [ ] Test round-trip communication

#### 1.3 Build Integration
- [ ] Create `mk/rust.mk`
- [ ] Modify main Makefile
- [ ] Test combined build

**Deliverable**: `warpd` and `warpd-ui` can exchange messages

### Phase 2: Configuration UI (3-4 weeks)

**Goal**: Full settings window with all config options

#### 2.1 Config Schema
- [ ] Extract schema from `config.c` options array
- [ ] Define Rust types for options
- [ ] Implement category grouping

#### 2.2 Settings Window
- [ ] Implement main window layout
- [ ] Category sidebar navigation
- [ ] Search/filter functionality

#### 2.3 Option Editors
- [ ] Key binding capture component
- [ ] Color picker component
- [ ] Integer slider component
- [ ] Font selector component
- [ ] String input component

#### 2.4 Config Persistence
- [ ] Load config from file
- [ ] Save changes to file
- [ ] Live reload notification to daemon

#### 2.5 Live Preview
- [ ] Hint appearance preview
- [ ] Cursor appearance preview
- [ ] Grid appearance preview

**Deliverable**: Fully functional settings UI

### Phase 3: Command Palette (3-4 weeks)

**Goal**: Shortcat-style UI element interaction

#### 3.1 Element Query API
- [ ] Extend `collect_interactable_hints()` with metadata
- [ ] Add IPC methods: `elements.list`, `elements.click`, `elements.focus`
- [ ] Include element type, state, hierarchy info

#### 3.2 Palette Window
- [ ] Overlay window creation (transparent, always-on-top)
- [ ] Text input with fuzzy filtering
- [ ] Element list rendering
- [ ] Keyboard navigation (up/down, enter)

#### 3.3 Element Type Filtering
- [ ] Parse `:type` prefix syntax
- [ ] Filter by element type
- [ ] Visual type badges

#### 3.4 Actions
- [ ] Click action
- [ ] Right-click action
- [ ] Focus action (for text fields)
- [ ] Copy element text

#### 3.5 Polish
- [ ] Animation (fade in/out)
- [ ] Scroll for long lists
- [ ] Hint labels (a, b, c...)
- [ ] Keyboard shortcut display

**Deliverable**: Working command palette

### Phase 4: Integration & Polish (2-3 weeks)

**Goal**: Production-ready release

#### 4.1 Process Lifecycle
- [ ] Auto-start UI from daemon
- [ ] Handle UI crash/restart
- [ ] Graceful shutdown

#### 4.2 Platform Testing
- [ ] macOS testing (10.15+)
- [ ] Linux X11 testing
- [ ] Linux Wayland testing

#### 4.3 Documentation
- [ ] Update README.md
- [ ] Update man page
- [ ] Add UI usage guide

#### 4.4 Release
- [ ] Code signing (macOS)
- [ ] Package creation
- [ ] Update FORK_CHANGES.md

**Deliverable**: Release-ready version

---

## Platform Considerations

### macOS

| Feature | Implementation |
|---------|----------------|
| Overlay windows | NSWindow with level `NSMainMenuWindowLevel + 999` |
| Global hotkeys | Existing CGEventTap |
| Accessibility | Existing AXUIElement code |
| GPU rendering | GPUI uses Metal |
| Code signing | Existing codesign script |

### Linux X11

| Feature | Implementation |
|---------|----------------|
| Overlay windows | `override_redirect` windows |
| Global hotkeys | XGrabKey |
| Accessibility | AT-SPI2 (limited) |
| GPU rendering | GPUI uses Vulkan/OpenGL |

### Linux Wayland

| Feature | Implementation |
|---------|----------------|
| Overlay windows | wlr-layer-shell protocol |
| Global hotkeys | Compositor-specific (limitation) |
| Accessibility | AT-SPI2 (limited) |
| GPU rendering | GPUI uses Vulkan |

### Accessibility Limitations

The command palette's usefulness depends heavily on accessibility API quality:

| Platform | Quality | Notes |
|----------|---------|-------|
| macOS | Good | Full AXUIElement support, but Chrome/Electron limited |
| Linux X11 | Moderate | AT-SPI2 works for GTK/Qt apps |
| Linux Wayland | Limited | AT-SPI2 + compositor cooperation needed |

---

## Alternatives Considered

### GPUI vs Tauri vs Iced vs egui

| Framework | Pros | Cons |
|-----------|------|------|
| **GPUI** | 120 FPS, pure Rust, Zed-proven | Pre-1.0, steep learning curve |
| **Tauri** | Stable, web UI flexibility, small binary | WebView overhead, JS dependency |
| **Iced** | Pure Rust, good docs | Less GPU optimization |
| **egui** | Immediate mode, simple | Retained state challenges |

**Decision**: GPUI for native performance in command palette. Tauri as fallback if GPUI blocks.

### Separate Process vs FFI Integration

| Approach | Pros | Cons |
|----------|------|------|
| **Separate process** | Clean isolation, GPUI-friendly | IPC latency, deployment complexity |
| **FFI integration** | Single binary, no IPC | GPUI event loop conflict, crash coupling |

**Decision**: Separate process for cleaner architecture.

### JSON-RPC vs Custom Protocol vs gRPC

| Protocol | Pros | Cons |
|----------|------|------|
| **JSON-RPC** | Simple, human-readable, good tooling | Parsing overhead |
| **Custom binary** | Fast, compact | Debugging difficulty |
| **gRPC** | Type-safe, efficient | Heavy dependency |

**Decision**: JSON-RPC for simplicity and debuggability.

---

## Success Metrics

1. **Configuration UI**
   - All 80+ options editable
   - Changes persist correctly
   - Live preview works

2. **Command Palette**
   - < 100ms to display after hotkey
   - Fuzzy matching feels responsive
   - Works with Safari, Firefox (Chrome limited by design)

3. **Stability**
   - UI crash doesn't affect daemon
   - No memory leaks in long sessions
   - Graceful degradation if UI unavailable

4. **User Experience**
   - Intuitive keyboard navigation
   - Consistent with platform conventions
   - Clear visual feedback

---

## Open Questions

1. **GPUI overlay support**: Does GPUI support transparent, always-on-top windows? Need prototype to verify.

2. **Linux Wayland hotkeys**: How to handle palette activation on Wayland without global hotkey support?

3. **Accessibility data richness**: How much element metadata can we extract across platforms?

4. **Update mechanism**: Should UI auto-update independently of daemon?

---

## References

- [GPUI Documentation](https://gpui.rs/)
- [GPUI Rust Docs](https://docs.rs/gpui)
- [Zed Blog: GPU Rendering](https://zed.dev/blog/videogame)
- [macOS Accessibility Programming Guide](https://developer.apple.com/documentation/accessibility)
- [AT-SPI2 Documentation](https://gitlab.gnome.org/GNOME/at-spi2-core)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
