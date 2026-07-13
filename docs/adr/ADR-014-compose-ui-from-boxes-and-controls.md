# ADR-014: Compose UI from boxes and controls

**Date:** 2026-07-13

## Context

Scrapbot's first retained UI slice combined box styling and row, column, or overlay behavior in one layout component. Expanding that model with controls would make one component responsible for geometry, container behavior, content, and future interaction state. UI entities instead need a consistent box model and composable roles that fit the ECS.

## Decision

Every UI entity has one layout component defining its rectangular box, parent, position, size, per-edge margin and padding, optional background, and corner radius. Independent horizontal-stack, vertical-stack, text, and button components add container or content behavior. An entity without a stack component overlays its children.

Pointer hit testing operates on every retained element box. The topmost hit element receives hover state. Primary-button press captures active state on that element until release. These states belong to the element; individual controls decide whether to render or act on them. Buttons are the first consumer through optional hover and active colors.

Background corner radii are evaluated as signed-distance rounded rectangles in the UI fragment shader. Font glyphs continue to use the separately precomputed MTSDF atlas described by ADR-013.

## Consequences

All controls share one predictable box model and interaction state, and new container or content roles can be added without growing a single tagged control type. Scene validation must reject conflicting roles such as simultaneous horizontal and vertical stacks or text and button content. Button press feedback is immediate, while activation still depends on the future UI command-event system.
