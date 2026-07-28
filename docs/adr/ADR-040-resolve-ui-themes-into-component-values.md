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
- Require any future project-authored theme resource or Luau/native convenience API to resolve through the same component fields and typed mutation paths. It must not introduce a second renderer style store or stable-frame traversal.

## Consequences

The editor's visual language becomes reusable UI-system data while the editor remains only a consumer. Tests and diagnostics can inspect the complete rendered values without evaluating a cascade, and ordinary component revisions continue to drive layout and paint invalidation.

Themes intentionally do not update already-resolved entities by magic. Changing a theme requires explicit recomposition or targeted component updates. Project TOML also remains verbose until a public authoring-time recipe surface exists, but its values stay portable, obvious, and fully overridable.

The theme vocabulary can grow as real project and editor compositions expose missing capabilities. Adding a theme token alone does not expand the public ECS or native ABI; adding a new visual behavior still requires the full cross-surface component audit from ADR-025.
