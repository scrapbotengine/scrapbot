---
title: ECS UI
description: Build reusable screen-space interfaces with the same ECS components used by Scrapbot's editor.
---

Scrapbot UI is ordinary ECS data. Scene TOML, Luau systems, native Odin extensions, and the live editor all construct the same `scrapbot.ui_*` components; the renderer retains, lays out, paints, and updates interaction state from that data.

The editor is the first large consumer of this API, not a separate widget toolkit. A panel, list, input, checkbox, or scroll area improved for the editor is available to projects through the same component fields.

## Component model

Every visible element starts with `scrapbot.ui_layout`. Add at most one flow container and at most one content control to the same entity:

| Role | Components |
| --- | --- |
| Box | `ui_layout` |
| Flow | `ui_hstack`, `ui_vstack`, `ui_table`, or `ui_list` |
| Viewport | `ui_scroll_area` |
| Framing | `ui_panel` |
| Content | `ui_text`, `ui_button`, `ui_input`, or `ui_checkbox` |
| Indicator | `ui_progress` |
| Interaction | Renderer-owned, read-only `ui_state` |

Panels, scroll areas, and progress indicators compose with flow/content components rather than replacing them. For example, one entity can be a titled panel, a scroll viewport, and a selectable list.

## Build a tree in scene TOML

UI parents are stable entity UUIDs, never display names:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000100"
name = "Menu"

[entities.ui_layout]
position = [32, 32]
size = [360, 220]
padding = [16, 16, 16, 16]
background = [0.02, 0.025, 0.035, 0.98]
border_color = [0.16, 0.18, 0.22, 1]
border_width = 1
corner_radius = 8

[entities.ui_vstack]
gap = 10

[[entities]]
id = "d4000000-0000-4000-8000-000000000101"
name = "Title"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000100"
size = [328, 36]

[entities.ui_text]
text = "SETTINGS"
color = [0.9, 0.92, 0.95, 1]
size = 16

[[entities]]
id = "d4000000-0000-4000-8000-000000000102"
name = "Apply"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000100"
size = [328, 40]
padding = [10, 14, 10, 14]
background = [0.08, 0.10, 0.14, 1]
corner_radius = 5

[entities.ui_button]
text = "Apply"
color = [0.9, 0.92, 0.95, 1]
size = 16
hover_background = [0.12, 0.15, 0.20, 1]
active_background = [0.06, 0.08, 0.11, 1]
```

Positions and sizes use top-left screen pixels. Margin, padding, and inset values use `[top, right, bottom, left]`. Parent cycles and incompatible container/content combinations fail project validation.

See the [Project File Reference](/reference/project-files/#built-in-component-sections) for every field and validation rule.

## Make layout responsive

Use layout policy instead of repairing rectangles after layout:

- `fill_width` / `fill_height` consume available parent space.
- `fit_content_width` / `fit_content_height` size around visible descendants.
- `min_size` prevents either policy from shrinking too far.
- `fixed_in_fill` preserves a bar or control's authored main-axis size inside a fill stack.
- Stack `fill = true` distributes remaining space proportionally.
- Stack `draggable = true` turns gaps into resize handles; `min_size` limits pane shrinking.
- Table `proportional_columns = true` treats the first row's authored widths as column weights for every row.
- Table `resizable_columns = true` turns column gaps into resize handles; `min_column_width` limits shrinking.
- `hidden = true` removes the complete subtree from layout, painting, focus traversal, and pointer input without despawning it.

Use `ui_scroll_area` when content can exceed its viewport. Its content moves by continuous pixel offsets, including fractional trackpad deltas, and nested scroll areas consume wheel input from the deepest hovered viewport.

## Style controls per entity

Layout backgrounds, borders, and corner radii are SDF shapes. Controls expose their own internal chrome as component fields:

- Scrollbar track/thumb geometry and colors.
- Panel title and disclosure-arrow geometry.
- Button hover/active backgrounds and text colors.
- Input prefix, selection, focus/invalid border, and caret styling.
- Checkbox box, border, checkmark, hover, and active styling.
- Progress track/fill, inset, radius, and direction.

Set a supported corner radius to `0` for square geometry. Omit `font` to use embedded Inter, or reference a project font declared in `project.toml`.

Scrapbot does not have a shared theme resource yet. Reuse style values in your scene-generation or project code when several entities should match.

## React through `ui_state`

The renderer attaches a read-only `scrapbot.ui_state` to laid-out elements. It reports hover, active, and focus state plus activation, change, validation, submit, and cancel edges.

Transient booleans describe the latest UI pass. Use revision counters when a system must not miss an edge between its own updates:

```lua
local Buttons = scrapbot.query(scrapbot.ui_button, scrapbot.ui_state)
local last_activation: { [string]: number } = {}

scrapbot.system(Buttons, { name = "menu" }, function(_, entity, _, state)
	local previous = last_activation[entity.id] or 0
	if state.activation_revision ~= previous then
		last_activation[entity.id] = state.activation_revision
		scrapbot.log(`activated {entity.name}`)
	end
end)
```

Buttons advance activation state. Checkboxes own a mutable `checked` value and advance change state. Inputs support focus, selection, cursor movement, Tab traversal, submission/cancellation, numeric bounds and stepping, and optional prefix scrubbing.

## Create and update UI from Luau

Luau lifecycle changes are issued from scheduled systems and deferred until the system step completes. `scrapbot.spawn` returns the new stable UUID immediately so children can reference a parent queued in the same command batch:

```lua
local built = false
scrapbot.system({
	name = "build_ui",
	writes = { scrapbot.ui_layout, scrapbot.ui_vstack, scrapbot.ui_text },
}, function()
	if built then
		return
	end
	built = true

	local root_id = scrapbot.spawn({
		name = "Runtime UI",
		components = {
			["scrapbot.ui_layout"] = { size = { x = 320, y = 180 } },
			["scrapbot.ui_vstack"] = { gap = 8 },
		},
	})

	scrapbot.spawn({
		name = "Runtime Label",
		components = {
			["scrapbot.ui_layout"] = {
				parent = root_id,
				size = { x = 280, y = 32 },
			},
			["scrapbot.ui_text"] = { text = "Created from Luau" },
		},
	})
end)
```

Use `scrapbot.add_component(entity, component, payload)` to attach or update UI. UI updates are partial: omitted fields preserve their current values. Use `scrapbot.remove_component` for structural removal. Do not attempt to author or write `ui_state`.

Native extensions use typed payloads and defaults from `scrapbot:extension`; see [Native Extensions: Build ECS UI](/guides/native-extensions/#build-ecs-ui-from-native-systems).

## Verify UI work

Use `examples/ui-showcase` for project UI and `examples/ecs-showcase --editor` for editor composition:

```sh
bin/scrapbot check examples/ui-showcase --json
bin/scrapbot run examples/ui-showcase \
  --backend wgpu \
  --headless \
  --frames 2 \
  --framegrab /tmp/scrapbot-ui.png
```

Hidden framegrabs do not provide pointer interaction, so cover hover, active, focus, scrolling, and edits with UI tests or a bounded visible-window smoke. See [Rendering And Testing](/guides/rendering-testing/) for 1:1 frame regions and visual verification.

## Current limits

The current text/input slice is printable ASCII and single-line. Clipboard operations, IME composition, Unicode shaping, multiline editing, UI themes, accessibility semantics, list virtualization, and general command-event routing remain future work.
