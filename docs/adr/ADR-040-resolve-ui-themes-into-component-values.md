# ADR-040: Resolve UI themes into explicit component values

**Date:** 2026-07-28

## Context

Scrapbot's public ECS UI exposes visual fields directly on layout and control components. This lets projects create interfaces that look unrelated to the editor, but coherent applications otherwise repeat many palette, typography, spacing, radius, and control-state values.

The editor accumulated its own constants while exercising those same public components. Moving that styling into renderer branches, editor roles, or implicit ancestry-based cascading would make the editor privileged again and would hide effective visual state from scene files, diagnostics, Luau, native extensions, and change-driven invalidation.

## Decision

Model a theme as explicit composition-time data that resolves into ordinary public `scrapbot.ui_*` component values.

- Keep the complete effective visual state on the existing ECS components. Layout and painting consume no theme identity, inherited selector, or editor role.
- Let the UI package own reusable palettes, metrics, and recipes for surfaces, typography, buttons, inputs, panels, lists, scrolling, checkboxes, and color pickers.
- Apply a recipe before attaching or updating a component, then permit entity-specific overrides. Theme application changes presentation fields while preserving hierarchy, identity, geometry policy, control content, and interaction semantics.
- Treat Scrapbot's reduced dark appearance as one built-in recipe used by editor composition, not as the canonical look of a button, input, panel, or list.
- Keep canonical component defaults neutral and independently valid. Projects may use a recipe, define a radically different recipe, copy resolved values into text-first scenes, or ignore themes and style each entity directly.
- Expose one named recipe vocabulary to scene TOML, Luau, native Odin, and editor composition. Text-first entities resolve `ui_theme` plus ordered `ui_recipes` before their explicit component fields; Luau receives a mutable component map; native Odin receives bounded typed ABI payloads from the host.
- Store project-authored themes as UUID-backed `scrapbot.ui_theme` resources. A resource explicitly names a built-in baseline and overrides semantic palette colors, metric scales, and the typography font. Missing tokens inherit from the baseline; every resulting token is validated before the project loads. RGB channels are non-negative HDR values, while alpha remains between zero and one.
- Keep the recipe vocabulary engine-owned and shared. A project theme changes the values selected by `canvas`, `primary_button`, `input`, and the other semantic recipes; it does not create screen-specific widget classes or content-bearing recipes.
- Resolve project theme UUIDs through the same component fields and typed mutation paths as built-in names. Scene parsing receives validated declarations, Luau reads the runtime theme registry, and native Odin uses a UUID-specific host callback. Theme UUIDs never travel through a generic string ABI field.
- Register themes in a non-rendering runtime resource family with stable UUID lookup, generation, version, and an aggregate revision. Reload updates a surviving UUID in place and retires missing entries. The revision drives editor/resource inspection only; UI layout and paint never observe it.

## Consequences

The editor's visual language becomes reusable UI-system data while the editor remains only a consumer. Tests and diagnostics can inspect the complete rendered values without evaluating a cascade, and ordinary component revisions continue to drive layout and paint invalidation.

Themes intentionally do not update already-resolved entities by magic. Changing a theme requires explicit recomposition or targeted component updates. Project-facing helpers reduce repeated values, but they deliberately return or create ordinary components that remain portable, inspectable, and fully overridable.

Text-first directives are authoring input rather than retained ECS fields. Luau resolves through the same engine-owned recipes, and the native extension wrapper delegates to a host callback instead of copying palette values across the ABI. Adding a recipe therefore requires parity tests and generated/public API updates, but never renderer work.

Project load and whole-project hot reload reparse scene authoring and rerun project scripts, so those explicit composition boundaries naturally consume a changed theme. Existing live entities are not traversed when a theme registry version changes. Project theme resources are text-authored and read-only in the current editor resource inspector.

The theme vocabulary can grow as real project and editor compositions expose missing capabilities. Adding a theme token alone does not expand the public ECS or native ABI; adding a new visual behavior still requires the full cross-surface component audit from ADR-025.
