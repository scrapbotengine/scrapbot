---
title: UI theming
description: Build coherent Scrapbot interfaces without constraining the public ECS styling surface.
---

Scrapbot treats a theme as a composition recipe, not as renderer-owned inherited state. A theme chooses reusable palette, typography, spacing, radius, and control-state values. Composition resolves those choices into ordinary `scrapbot.ui_*` components before the UI is laid out or painted.

The effective appearance therefore remains visible in ECS:

1. Start from the canonical component default.
2. Apply a theme recipe when one is useful.
3. Apply entity-specific content, geometry, behavior, and visual overrides.
4. Attach or update the complete resolved component through the ordinary typed ECS path.

The renderer does not receive a theme name. It consumes the same layout, text, button, input, list, panel, scrollbar, checkbox, progress, and color-picker fields regardless of how their values were chosen.

## Built-in theme and recipe vocabulary

The current built-in theme is `reduced_dark`. It is the editor's restrained, almost-black visual language, not a mandatory project look.

Recipes are composable and applied in order:

| Group | Recipes | Components produced |
| --- | --- | --- |
| Surfaces | `canvas`, `region`, `panel_surface`, `raised`, `control`, `overlay` | `ui_layout` |
| Application chrome | `chrome_bar`, `warning_frame` | `ui_layout` |
| Text | `primary_text`, `secondary_text`, `muted_text`, `accent_text`, `warning_text`, `danger_text` | `ui_text` |
| Buttons | `quiet_button`, `standard_button`, `primary_button`, `selected_button`, `warning_button`, `destructive_button` | `ui_layout`, `ui_button` |
| Controls | `input`, `checkbox`, `color_picker` | The matching control; `input` also produces `ui_layout` |
| Containers | `panel`, `list`, `scroll_area` | The matching container; `panel` also produces `ui_layout` |

Later recipes replace presentation fields on components produced by an earlier recipe. Explicit component values are applied after every recipe and therefore win. Recipe output may still be incomplete as a valid entity: text and button recipes intentionally leave content empty for the caller to provide.

## Why themes resolve explicitly

Explicit resolution preserves several Scrapbot guarantees:

- Scene TOML, Luau, native extensions, editor composition, diagnostics, and rendering agree on the effective component value.
- A project can override any field without fighting an implicit selector or ancestry cascade.
- Reparenting an entity does not silently change its appearance.
- Layout and paint remain change-driven through ordinary component revisions.
- Stable frames do not walk ancestors or theme resources to rediscover unchanged style.
- The editor cannot acquire private visual behavior that projects cannot reproduce.

Themes intentionally do not mutate existing entities automatically. Restyling a live tree means explicitly recomposing it or applying targeted component updates.

## The editor is one theme

Scrapbot's editor uses the UI system's reduced dark recipe:

- Almost-black canvas and region surfaces with small tonal elevation steps.
- Slightly raised, subtly rounded panel headers and controls.
- Borderless resting surfaces; focus, validation, and playback receive deliberate semantic emphasis.
- Embedded Inter at a compact 13-pixel body and 12-pixel technical-title scale.
- Mint for identity, focus, selection, and positive authoring state.
- Amber for temporary playback state.
- Red for invalid or destructive state.

The editor does not keep a second palette beside this theme. Its app bars, selected and warning controls, viewport emphasis, profiler provenance, vector axes, and overlays all select shared recipes or named theme tokens. Editor code contributes content, geometry, and meaning; it does not invent local colors.

Those choices are editor presentation, not widget behavior. `scrapbot.ui_button` does not imply a dark rectangle, mint focus, a particular radius, or compact dimensions. The editor merely supplies those resolved fields when it creates the button.

## A project can look completely different

The `ui-showcase` example places a restrained application surface beside a saturated arcade surface. Both use ordinary layout, stack, text, button, and checkbox components.

This button is compact and restrained:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000201"
name = "Reduced Action"

[entities.ui_layout]
position = [40, 40]
size = [180, 34]
padding = [7, 10, 6, 10]
background = [0.016, 0.021, 0.028, 1]
corner_radius = 6

[entities.ui_button]
text = "Apply"
color = [0.82, 0.85, 0.90, 1]
size = 13
hover_background = [0.032, 0.041, 0.055, 1]
active_background = [0.045, 0.057, 0.076, 1]
```

The same components can produce an unrelated arcade treatment:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000202"
name = "Arcade Action"

[entities.ui_layout]
position = [260, 40]
size = [260, 82]
padding = [24, 20, 18, 20]
background = [0.98, 0.12, 0.38, 1]
border_color = [1, 0.68, 0.16, 1]
border_width = 4
corner_radius = 28

[entities.ui_button]
text = "BOOST"
color = [1, 1, 1, 1]
size = 24
hover_background = [1, 0.24, 0.52, 1]
active_background = [0.72, 0.04, 0.24, 1]
```

No renderer mode changes between them. A project may also set `corner_radius = 0`, use transparent backgrounds, omit borders, choose project fonts, or construct its own style vocabulary.

## What belongs in a theme

A useful theme usually defines a small, intentional vocabulary rather than one style per screen.

### Palette

Separate structural surfaces from semantic state:

- Canvas, region, panel, raised, control, and overlay surfaces.
- Primary, secondary, and muted text.
- Ordinary and strong boundaries.
- Selection, hover, active, and focus treatments.
- Accent, warning, danger, and their quieter surface variants.

Project-specific colors such as health, rarity, factions, teams, damage types, or rhythm lanes belong beside the project domain that gives them meaning. They need not become generic engine tokens.

### Metrics

Choose reusable scales for:

- Primary and small text sizes.
- Control, row, and panel-title heights.
- Small, ordinary, and large gaps.
- Control and panel padding.
- Small, ordinary, and large corner radii.
- Resting and semantic-emphasis boundary policies, including when to omit borders.

Individual layouts remain free to override every metric. A theme scale is a consistency tool, not validation.

### Control recipes

Recipes can combine canonical defaults with theme values for:

- Quiet, standard, primary, selected, warning, and destructive buttons.
- Edge-to-edge application bars and semantic warning frames.
- Text and numeric inputs.
- Panel frames and title bands.
- Selectable lists and drag/drop feedback.
- Scrollbar geometry and color.
- Checkbox states.
- HDR color-picker chrome.

Keep content and behavior outside the recipe. A button recipe should not choose its text, popup target, icon meaning, or editor action. An input recipe should not choose its committed value, bounds, or read-only policy.

## Override without losing semantics

Theme application should preserve fields that identify or control the element:

- Layout parent UUID, position, size, sizing policy, popup state, and tree metadata.
- Button text, popup UUID, icon, alignment, and panel-action meaning.
- Input text, numeric value, bounds, stepping, and read-only behavior.
- Panel title, collapse state, and collapsibility.
- List selection, filter UUID, virtualization, tree, and drag/drop configuration.

Only the intended presentation fields should change. Applying a surface recipe, for example, may set background, border, width, and radius while leaving parent and responsive sizing untouched.

## Resolve recipes in scene TOML

Declare `ui_theme` and `ui_recipes` in the entity table, before its component sections:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000202"
name = "Arcade Action"
ui_theme = "reduced_dark"
ui_recipes = ["primary_button"]

[entities.ui_layout]
position = [260, 40]
size = [260, 82]
background = [0.98, 0.12, 0.38, 1]
border_color = [1, 0.68, 0.16, 1]
border_width = 4
corner_radius = 28

[entities.ui_button]
text = "BOOST"
color = [1, 1, 1, 1]
size = 24
```

The recipe creates `ui_layout` and `ui_button`; the component sections replace selected values to produce the arcade treatment. Compose containers with arrays such as `["panel", "scroll_area"]`. Both fields are required together, the array must be non-empty, and one entity may apply at most 16 recipes.

Theme directives are load-time authoring input. The resulting ECS entity contains only the resolved components.

## Resolve recipes in Luau

`scrapbot.ui.resolve` returns a mutable component map suitable for `scrapbot.spawn`:

```lua
local components = scrapbot.ui.resolve("reduced_dark", { "primary_button" })
components["scrapbot.ui_layout"].size = { x = 260, y = 82 }
components["scrapbot.ui_layout"].corner_radius = 28
components["scrapbot.ui_layout"].background = { x = 0.98, y = 0.12, z = 0.38, w = 1 }
components["scrapbot.ui_button"].text = "BOOST"

scrapbot.spawn({
	name = "Arcade Action",
	components = components,
})
```

Resolution is pure composition and requires no system access. The eventual spawn or component attachment still requires declared writes for every returned component.

## Resolve recipes in native Odin

The native helper delegates resolution to the host, keeping palette values out of the extension ABI:

```odin
recipes := [?]scrapbot.UI_Theme_Recipe{.Panel, .Scroll_Area}
storage: [scrapbot.UI_THEME_PAYLOAD_CAPACITY]scrapbot.UI_Component_Payload
components, err := scrapbot.ui_theme_resolve(
	ctx,
	.Reduced_Dark,
	recipes[:],
	storage[:],
)
if err != nil {
	return err
}
```

The returned slice borrows caller storage and contains ordinary typed UI payloads. Override their fields, set bounded text/font/prefix strings with the existing payload helpers, and pass the slice to `spawn_options_with_ui`. Native systems need the same declared writes as manually constructed payloads.

## Project-defined themes

Projects can already create wholly unrelated interfaces through explicit overrides, as Neon Arcade demonstrates. Named project-defined theme resources are not yet part of the project format. If added, they must resolve through this same recipe-to-component boundary; they will not create a renderer style store or implicit stable-frame cascade.

## Test a visual system

Test themes at two levels:

- Use deterministic component tests to prove recipes preserve semantic fields, accept complete overrides, and produce valid public values.
- Use a bounded headless WGPU framegrab to inspect representative controls in idle, hover, active, focused, invalid, read-only, and selected states.

Keep contrasting compositions in the showcase. If the same public components cannot express both Scrapbot's reduced editor and a visually unrelated project UI, improve the public styling vocabulary instead of adding an editor-only paint path.
