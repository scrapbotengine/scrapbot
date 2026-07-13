# ADR-018: Render editor gizmos as screen overlays

**Date:** 2026-07-13

## Context

Transform handles represent world axes but must remain legible and easy to hit across camera distances, viewport sizes, and scene lighting. Modeling their rendered geometry as ordinary world entities would entangle editor tools with serialized project data and allow depth, materials, or lighting to obscure essential controls. At the same time, whether an entity currently has an editor tool should remain expressible through ECS data rather than an unrelated selection-only rendering branch.

## Decision

Reconcile a transient, engine-owned `EditorTransformGizmo` component onto the selected entity when it has a Transform, removing it when selection changes or the editor closes. A dedicated editor system queries that component, projects its world-space anchor and axes through the active camera, and renders the handles as screen-space overlay primitives clipped to the live viewport. The system converts pointer motion along a projected handle back into displacement on its corresponding world axis. Gizmo input captures the pointer ahead of scene picking and project UI interaction.

The component is part of the live engine world and appears in the component inspector, but it is not a scene TOML, Luau, or native-extension component and is never serialized into the project.

## Consequences

Handles keep a stable apparent size, remain visible, and do not enter project scene data. Selection and tool ownership remain observable in the ECS, while interaction state such as the active drag stays in the editor resource. The first implementation supports world-space translation only. Depth-aware handles, local axes, planar handles, rotation, scale, snapping, undo, and persisted edits require later editor systems.
