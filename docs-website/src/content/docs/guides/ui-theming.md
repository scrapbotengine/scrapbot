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

- Deep neutral canvas and region surfaces.
- Slightly raised panel headers and controls.
- Quiet borders reserved for controls, focus, and major boundaries.
- One compact typography and spacing scale.
- Mint for identity, focus, selection, and positive authoring state.
- Amber for temporary playback state.
- Red for invalid or destructive state.

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
background = [0.018, 0.023, 0.031, 1]
border_color = [0.05, 0.06, 0.076, 1]
border_width = 1
corner_radius = 5

[entities.ui_button]
text = "Apply"
color = [0.86, 0.88, 0.92, 1]
size = 13
hover_background = [0.028, 0.036, 0.048, 1]
active_background = [0.042, 0.053, 0.07, 1]
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
- Ordinary and emphasized border widths.

Individual layouts remain free to override every metric. A theme scale is a consistency tool, not validation.

### Control recipes

Recipes can combine canonical defaults with theme values for:

- Quiet, standard, primary, and destructive buttons.
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

## Text-first projects

Scene TOML currently stores resolved component values rather than referencing a named theme resource. This is verbose, but it makes a scene self-describing and keeps Save, hot reload, diagnostics, and generated APIs aligned.

Use scene-generation code or project conventions to reuse values across a large interface. A future project-facing theme helper or theme resource must still resolve through the same public fields; it will not create a second renderer style store or implicit stable-frame cascade.

## Test a visual system

Test themes at two levels:

- Use deterministic component tests to prove recipes preserve semantic fields, accept complete overrides, and produce valid public values.
- Use a bounded headless WGPU framegrab to inspect representative controls in idle, hover, active, focused, invalid, read-only, and selected states.

Keep contrasting compositions in the showcase. If the same public components cannot express both Scrapbot's reduced editor and a visually unrelated project UI, improve the public styling vocabulary instead of adding an editor-only paint path.
