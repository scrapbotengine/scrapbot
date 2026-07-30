---
title: ECS UI
description: Build reusable screen-space interfaces with the same ECS components used by Scrapbot's editor.
---

Scrapbot UI is ordinary ECS data. Scene TOML, Luau systems, native Odin extensions, and the live editor all construct the same `scrapbot.ui_*` components; the renderer retains, lays out, paints, and updates interaction state from that data.

The editor is the first large consumer of this API, not a separate widget toolkit. A panel, list, input, checkbox, or scroll area improved for the editor is available to projects through the same component fields.

Themes are explicit composition-time recipes that resolve into those same fields. See [UI theming](/guides/ui-theming/) for the resolution order, override rules, and contrasting examples.

Appearing, disappearing, reparented, and hidden elements update a retained hierarchy through structural dirty notifications. Ordinary value changes on already-attached components increment the affected project or editor paint revision without rebuilding that hierarchy. Runtime-authored parent cycles are rejected during synchronization. Unchanged frames do not rebuild an element inventory, hash the complete UI component set, run layout, or regenerate paint commands; changed layout and paint walk retained parent/child/sibling links in linear time.

## Component model

Every visible element starts with `scrapbot.ui_layout`. Add at most one flow container and at most one content control to the same entity:

| Role | Components |
| --- | --- |
| Box | `ui_layout` |
| Root policy | Optional singleton `ui_canvas` |
| Flow | `ui_hstack`, `ui_vstack`, `ui_table`, `ui_list`, or `ui_dock_space` |
| Viewport | `ui_scroll_area` |
| Framing | `ui_panel`; `ui_dock_item` on a direct dock-space child |
| Content | `ui_icon`, `ui_text`, `ui_button`, `ui_input`, `ui_checkbox`, or `ui_color_picker` |
| Indicator | `ui_progress` |
| Semantics | Optional inheritable `ui_action` |
| Interaction | Renderer-owned, read-only `ui_state` |

Panels, scroll areas, and progress indicators compose with flow/content components rather than replacing them. For example, one entity can be a titled panel, a scroll viewport, and a selectable list.

Lists may reference a same-origin public input by UUID for reusable descendant-content filtering. Tree filters retain matching ancestors and reveal matches beneath collapsed rows without mutating collapse state. For large data sets, enable uniform-row virtualization with an explicit item height and overscan count; combine the list with a scroll area to retain the complete scroll extent while only visible rows are laid out. The editor Scene browser consumes this same public contract.

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

Positions and sizes use logical pixels. Margin, padding, and inset values use `[top, right, bottom, left]`. Parent cycles and incompatible container/content combinations fail project validation.

See the [Project File Reference](/reference/project-files/#built-in-component-sections) for every field and validation rule.
The [Engine Component Reference](/reference/components/#ui-composition-rules) is the compact field/default inventory for every `scrapbot.ui_*` component.

## Use scalable icons

Declare a `scrapbot.icon_set` resource whose source is a directory of monochrome SVG files. Each filename stem becomes a stable symbol:

```toml
id = "a1000000-0000-4000-8000-000000000001"
type = "scrapbot.icon_set"
name = "Game Icons"

[icon_set]
source = "assets/icons"
```

Use that UUID and a symbol on a standalone icon:

```toml
[entities.ui_icon]
icon_set = "a1000000-0000-4000-8000-000000000001"
icon = "inventory"
color = [0.7, 1.2, 1.8, 1]
inset = 2
```

Buttons use the same reference and resolver:

```toml
[entities.ui_button]
text = "PLAY"
icon_set = "a11c0000-0000-4000-8000-000000000001"
icon = "play"
icon_position = "leading"
icon_size = 18
icon_gap = 7
icon_inset = 2
```

Inputs can reserve the same scalable icon inside their own padded content:

```toml
[entities.ui_input]
icon_set = "a11c0000-0000-4000-8000-000000000001"
icon = "magnifying-glass"
icon_position = "leading"
icon_color = [0.65, 0.68, 0.74, 1]
icon_size = 14
icon_gap = 6
icon_inset = 0
```

The input owns the icon's layout and clipping. A leading prefix badge remains
outermost, and editable text scrolls without moving the icon.

The built-in catalog also contains `x`, `plus`, `caret-right`, `caret-down`, `magnifying-glass`, `pause`, `stop`, and `skip-forward`. Luau can use `scrapbot.ui.builtin_icon_set`; native Odin can use `scrapbot.ui_builtin_icon_set()`. Projects may use the built-in set, compile wholly different art, or combine both. The editor is only another consumer of this API.

Scrapbot compiles supported SVG geometry into a cached 512×512 MTSDF atlas. The runtime never parses SVG, stable frames do not rebuild icon data, and reimport uploads only the changed icon-set layer. Icons are monochrome masks by design; use their HDR `color` tint for presentation.

## Make layout responsive

Put `scrapbot.ui_canvas` on one root layout to define how logical UI reaches the
window or editor game viewport:

```toml
[entities.ui_layout]
size = [1280, 720]
fill_width = true
fill_height = true

[entities.ui_canvas]
reference_size = [1280, 720]
scale_mode = "expand"
horizontal_alignment = "center"
vertical_alignment = "center"
safe_area = [24, 32, 24, 32]
```

Choose `expand` for a resolution-independent HUD that preserves scale and
reveals more logical space on wider or taller displays. Use `fit` to letterbox,
`fill` to crop while preserving aspect, `stretch` only when distortion is
intentional, `pixel_perfect` for whole-number presentation, or `none` to follow
the output pixel density. Optional `min_scale` and `max_scale` clamp the result;
zero leaves a bound open.

Canvas safe-area insets apply to its children. Combine them with each child's
`horizontal_alignment` and `vertical_alignment` (`start`, `center`, `end`, or
`stretch`) to anchor HUD regions without resize scripts:

```toml
[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000100"
size = [320, 96]
horizontal_alignment = "end"
vertical_alignment = "start"
```

Then compose the rest from ordinary layout policy:

- `fill_width` / `fill_height` consume available parent space.
- `fit_content_width` / `fit_content_height` size around visible descendants.
- `min_size` prevents either policy from shrinking too far.
- `fixed_in_fill` preserves a bar or control's authored main-axis size inside a fill stack.
- Stack `fill = true` distributes remaining space proportionally.
- Stack `draggable = true` turns gaps into resize handles; `min_size` limits pane shrinking.
- Layout `basis`, `grow`, and `shrink` provide per-child preferred and flexible sizing without mutating authored rectangles.
- Stack `wrap = true` packs children into lines separated by `line_gap`; each line resolves grow and shrink independently.
- Text `wrap = true` uses the active font's glyph metrics and optional `line_height`, so `fit_content_height` follows the rendered lines exactly.
- Table `proportional_columns = true` treats the first row's authored widths as column weights for every row.
- Table `resizable_columns = true` turns column gaps into resize handles; `min_column_width` limits shrinking.
- List `tree_enabled = true` flattens direct tree rows by their public semantic parent/order metadata and indents only their contents.
- `hidden = true` removes the complete subtree from layout, painting, focus traversal, and pointer input without despawning it.

Use `ui_scroll_area` when content can exceed its viewport. Its content moves by continuous pixel offsets, including fractional trackpad deltas, and nested scroll areas consume wheel input from the deepest hovered viewport.

Project layout, painting, embedded viewports, pointer hit testing, and semantic
diagnostics all use the exact authored canvas transform. The editor is only a
host for that public policy. Projects without a canvas retain the legacy
top-left 1280×720 fit.

## Compose a docked workspace

Docking is a public group-and-item contract, not an editor workspace object.
Put dock spaces inside ordinary draggable fill stacks to define the available
regions:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000130"
name = "Workspace"

[entities.ui_layout]
size = [1280, 720]

[entities.ui_hstack]
fill = true
draggable = true
min_size = 180
gap = 4

[[entities]]
id = "d4000000-0000-4000-8000-000000000131"
name = "Left Dock"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000130"
size = [320, 720]
fill_height = true

[entities.ui_dock_space]
active = "d4000000-0000-4000-8000-000000000132"
font = "Inter"
split_horizontal = true
split_vertical = true
split_ratio = 0.5
split_edge_fraction = 0.25
split_gap = 4
split_min_size = 120
tab_connection_height = 4
tab_content_overlap = 2
tab_strip_background = [0.02, 0.025, 0.032, 1]
content_background = [0.105, 0.115, 0.135, 1]
content_corner_radius = 4
content_padding = [2, 2, 2, 2]

[[entities]]
id = "d4000000-0000-4000-8000-000000000132"
name = "Inventory Tab"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000131"
size = [320, 688]
fill_width = true
fill_height = true

[entities.ui_dock_item]
title = "INVENTORY"
movable = true
```

Every direct dock-item child contributes one tab. A direct titled `ui_panel`
also contributes a tab using its panel title; while docked, that tab replaces
the panel's internal title band. Clicking selects it. Dragging a movable tab
onto another draggable dock space reparents the item by stable UUID, selects it
in the destination, and emits the ordinary public drop state and immutable
`dropped` event. A panel tab may instead return to a reorderable stack. Set an
item's `movable` field or a destination's `draggable` field to `false` for fixed
application regions.

Compose each dock item around a reorderable HStack or VStack when it should
accept panels. Dropping on that item's tab header routes into the nearest such
descendant stack, even when the tab is inactive. Dropping on empty dock-space
chrome creates a sibling tab instead. The dock component discovers ordinary
public stack composition; it does not own a second panel collection.

The accepting tab header uses the dock space's `drop_background` while the
pointer is over it. Movable titles and tabs use the platform move cursor; an
active workspace drag uses the not-allowed cursor when no compatible
destination is under the pointer.

Enable `split_horizontal` and/or `split_vertical` when an edge drop should
create another pane. Left/right edges create a public draggable fill HStack;
top/bottom edges create the equivalent VStack. The target dock stays in place,
the dropped item enters a newly created sibling dock, and `split_ratio`,
`split_gap`, and `split_min_size` configure the initial public stack geometry.
An edge target is offered only when both panes can satisfy the minimum size.
Because the result is ordinary ECS UI topology, project code may query, restyle,
resize, or persist it with the same APIs it uses for authored stacks and dock
spaces.

Tab silhouettes and their shared pane sheet are themeable rather than
editor-specific. `tab_strip_background` gives the tab rail its own surface
without painting over active content. `content_background`,
`content_corner_radius`, and `content_padding` create the physical surface that
houses every pane in the group. A positive `tab_connection_height` squares the
active tab's lower corners, while `tab_content_overlap` joins it cleanly over
that sheet. A zero
connection height retains a detached rounded control. Use a transparent
inactive `tab_background` when inactive entries should read as tab labels
rather than buttons.

A panel may carry that stack itself so the tab created by docking the panel can
accept later drops. While the panel remains nested in another stack, its own
stack only lays out its content and the containing workspace stack remains the
drop destination.

The dock space owns only tabs and active-child presentation. Nested stacks,
tables, lists, scroll areas, and viewports remain normal components inside the
dock item. This is the same framework consumed by Scrapbot's Browse, Game, and
Inspect editor regions.

## Compose rearrangeable panels

Use a reorderable stack when several panels should remain visible while users
change their order. Add `fill` and `draggable` when the same gaps should resize
adjacent panels:

```toml
[entities.ui_vstack]
gap = 6
fill = true
draggable = true
min_size = 96
reorderable = true
drop_indicator_color = [0.2, 1.4, 1.1, 1]

[entities.ui_layout]
stack_order = 0

[entities.ui_panel]
title = "QUEST LOG"
collapsible = true
movable = true
```

The panel must be a direct child of the stack. A title click toggles collapse;
moving past `drag_threshold` switches the gesture to workspace dragging.
Releasing without a compatible destination cancels and does not toggle
collapse. Stack drops mutate public `stack_order` and normalize the affected
siblings. Dock-space drops make the same panel a direct child and new tab; its
tab can later move it back into a reorderable stack. This is the same public
path used by the editor's Performance, Systems, Scene, and Resources panels.

## Compose a popup

A popup is a root `ui_layout`, not a private menu widget. Point an ordinary button at the popup UUID, then compose the popup from the same stack, list, scroll-area, and content components used elsewhere:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000120"
name = "Open Difficulty"

[entities.ui_layout]
position = [32, 32]
size = [180, 40]

[entities.ui_button]
text = "Difficulty"
popup = "d4000000-0000-4000-8000-000000000121"

[[entities]]
id = "d4000000-0000-4000-8000-000000000121"
name = "Difficulty Popup"

[entities.ui_layout]
size = [180, 240]
popup = true
popup_close_on_selection = true
popup_gap = 4
popup_min_width = 180
popup_max_height = 160
popup_viewport_margin = 8
background = [0.025, 0.03, 0.04, 1]

[entities.ui_list]

[entities.ui_scroll_area]
```

The popup must remain a root, while its menu rows are ordinary children. Activating the button assigns it as the anchor and toggles `popup_open`. Shared UI places the popup below or above the anchor, clamps it to the current UI viewport, scrolls oversized content, closes another open popup in the same project/editor UI domain, and dismisses it on same-domain outside presses or Escape. With `popup_close_on_selection = true`, selecting a descendant list row also closes it. The derived screen rectangle never overwrites the authored `position` or `size`.

## Style controls per entity

Layout backgrounds, borders, and corner radii are SDF shapes. Controls expose their own internal chrome as component fields:

- Scrollbar track/thumb geometry and colors.
- Panel title, disclosure-arrow, and trailing-action geometry and colors.
- Button hover/active backgrounds and text colors.
- List selection, hover, active, and drop-target backgrounds with a shared highlight radius.
- Direct linear RGBA color picking with optional alpha and HDR exposure tracks.
- Input prefix, selection, focus/invalid border, and caret styling.
- Checkbox box, border, checkmark, hover, and active styling.
- Progress track/fill, inset, radius, and direction.

Set a supported corner radius to `0` for square geometry. Omit `font` to use embedded Inter, or reference a project font declared in `project.toml`.

Scrapbot's reduced editor theme is one reusable composition recipe, not a renderer mode. Scene TOML, Luau, and native Odin can resolve the same named recipes into ordinary components, override any field per entity, or ignore the recipe system entirely. See [UI theming](/guides/ui-theming/).

## React through semantic events

Use `ui_action` to bind project meaning without teaching buttons, inputs, lists, or the renderer about gameplay commands:

```toml
[entities.ui_action]
action = "menu.launch"
payload = "campaign"
```

The action may live on the exact control or a UI ancestor shared by a composite subtree. `scrapbot.ui.events(cursor)` returns ordered activation, change, submission, cancellation, and drop events to Luau; native extensions use the same cursor model. Reads are immutable, so multiple systems can independently observe the same interaction.

The `ui-showcase` example uses this contract to drive a live neon event monitor from ordinary buttons, a checkbox, an input, and the HDR color picker.

## Inspect current state through `ui_state`

The renderer attaches a read-only `scrapbot.ui_state` to laid-out elements. It reports hover, active, and focus state plus activation, change, validation, submit, cancel, and draggable-list drop edges. A draggable list publishes `dragging`, direct-child `drag_source`/`drop_target` UUIDs, `drop_placement` (`before`, `into`, or `after`), and a monotonic `drop_revision`; an empty target with `into` means the list background rather than another row.

For a reusable nested tree, set `tree_enabled = true` on the list and `tree_item = true` on each row's layout. Rows remain ordinary direct children of the list for composition and selection. Their `tree_parent` points to another row UUID, `tree_order` is sibling-local, and `tree_collapsed` hides the descendant branch. The shared list lays rows out depth-first, applies `tree_indent` to row contents while retaining edge-to-edge selection chrome, rejects cyclic drops, and updates parent/order metadata atomically for `before`, `into`, and `after`. A normal child button can paint a disclosure icon and toggle its row's `tree_collapsed` field; no editor-only tree widget is involved.

Transient booleans describe the latest UI pass. Use revision counters when a system needs per-entity current state. Prefer the ordered event history for semantic commands spanning multiple controls:

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

Buttons advance activation state. Checkboxes own a mutable `checked` value and advance change state. Inputs support focus, selection, cursor movement, Tab traversal, submission/cancellation, and numeric bounds and stepping. Typed numeric text is staged locally: Enter validates and commits it, while Escape, focus loss, and Tab navigation restore the previously committed value. Set `draggable = true` on a writable numeric input to opt into live horizontal scrubbing from its complete control surface; releasing the pointer submits that scrub. Prefix badges are presentation rather than an interaction requirement.

Windowed runs use the platform's pointer cursor over buttons, selectable list rows, writable checkboxes and color pickers, interactive viewports, and fixed collapsible panel titles. Movable panel titles and dock tabs use the move cursor; active workspace drags switch to not-allowed over dead space. Writable text and numeric inputs use the text-edit cursor. A draggable numeric input switches to the horizontal-resize cursor while a scrub is armed or active, and draggable layout separators keep their directional resize cursor.

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

Headless runs normally have no platform pointer, but `--ui-script` can semantically drive hover, active, focus, scrolling, typing, assertions, and target-cropped framegrabs through the same reconciler. See [Rendering And Testing](/guides/rendering-testing/#semantic-ui-diagnostics) for the script and UI-tree dump workflow.

## Current limits

The current text/input slice is printable ASCII and single-line. List filtering folds ASCII case only, and virtualized rows require one uniform item height. Clipboard operations, IME composition, Unicode shaping, multiline editing, inline theme-resource editing, accessibility semantics, and general command-event routing remain future work.
