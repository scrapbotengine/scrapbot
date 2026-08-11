# ADR-018: Render editor gizmos as screen overlays

**Date:** 2026-07-13

## Context

Transform handles represent either canonical world axes or the selected entity's rotated local axes, but must remain legible and easy to hit across camera distances, viewport sizes, and scene lighting. Modeling their rendered geometry as ordinary world entities would entangle editor tools with serialized project data and allow depth, materials, or lighting to obscure essential controls. At the same time, whether an entity currently has an editor tool should remain expressible through ECS data rather than an unrelated selection-only rendering branch.

## Decision

Reconcile a transient, engine-owned `EditorTransformGizmo` component onto the selected entity when it has a Transform, removing it when selection changes or the editor closes. A dedicated editor system queries that component, projects its world-space anchor, axes, or rotation rings through the active camera, and renders the handles as screen-space overlay primitives clipped to the live viewport. The component's mode selects translation, rotation, or scale behavior; its space selects canonical world axes or axes derived from the selected Transform's Euler rotation; and its pivot selects the Transform origin or the combined rendered-bounds center of the selected entity, descendants, and generated Model children.

Origin/Center is manipulation policy, not authored spatial data. Center translation preserves the offset between the bounds center and Transform origin. Center rotation and scaling move the Transform origin around the frozen bounds center while also changing orientation or scale, and record both fields in one authoring transaction. The system freezes the projected anchor and world-space bases when a drag begins so neither axes nor derived bounds move underneath the pointer. Gizmo input captures the pointer ahead of scene picking and project UI interaction; the ECS-built World/Local and Origin/Center viewport toolbar has priority over gizmo hit testing.

The component is part of the live engine world and appears in the component inspector, but it is not a scene TOML, Luau, or native-extension component and is never serialized into the project.

## Consequences

Handles keep a stable apparent size, remain visible, and do not enter project scene data. Selection, tool ownership, active transform mode, orientation space, and manipulation pivot remain observable in the ECS, while the derived bounds cache and frozen gesture basis stay in the editor resource. The editor supports world- or local-oriented single-axis and two-axis plane translation, camera-plane free translation, world- or local-oriented axis rotation, local-component per-axis and two-axis scaling, and uniform XYZ scaling selected with G, R, and S. Editing an asset's imported origin, custom pivots, depth-aware handles, snapping, and multi-selection require later editor systems.
