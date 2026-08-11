# ADR-018: Render editor gizmos as screen overlays

**Date:** 2026-07-13

## Context

Transform handles represent either canonical world axes or the selected entity's rotated local axes, but must remain legible and easy to hit across camera distances, viewport sizes, and scene lighting. Modeling their rendered geometry as ordinary world entities would entangle editor tools with serialized project data and allow depth, materials, or lighting to obscure essential controls. At the same time, whether an entity currently has an editor tool should remain expressible through ECS data rather than an unrelated selection-only rendering branch.

## Decision

Reconcile a transient, engine-owned `EditorTransformGizmo` component onto the selected entity when it has a Transform, removing it when selection changes or the editor closes. A dedicated editor system queries that component, projects its world-space anchor, axes, or rotation rings through the active camera, and renders the handles as screen-space overlay primitives clipped to the live viewport. The component's mode selects translation, rotation, or scale behavior; its space selects canonical world axes or axes derived from the selected Transform's Euler rotation; and its pivot selects the Transform origin or the combined rendered-bounds center of the selected entity, descendants, and generated Model children.

The same overlay owns screen-facing camera and light icons. It projects each non-editor camera or point light with a valid world Transform into the Game viewport. Directional lights use their Transform when present and the world origin otherwise because their authored direction is position-independent. It then paints a constant-apparent-size symbol with camera/light semantic color and selection emphasis.

Icons participate in editor picking ahead of camera strokes and rendered triangles. An entity with multiple visualized component kinds receives one icon, preferring camera, then directional light, then point light. When projected icons overlap, deterministic screen-space offsets and leader lines preserve separate pick targets; the selected icon remains on its true projected anchor.

Selecting a point light adds three projected great circles for its range plus a radial handle. Selecting a directional light adds an arrow in its authored direction plus a trackball-style endpoint handle. These are transient overlay tools, not ECS components or project geometry. A drag writes the canonical light field through the inspector mutation path, captures pointer activation ahead of selection and project UI, retains pointer ownership across editor chrome, and creates one stopped-mode UUID-addressed history transaction on release. Escape restores the captured value. Direction edits remain normalized; point ranges remain positive.

Origin/Center is manipulation policy, not authored spatial data. Center translation preserves the offset between the bounds center and Transform origin. Center rotation and scaling move the Transform origin around the frozen bounds center while also changing orientation or scale, and record both fields in one authoring transaction. The system freezes the projected anchor and world-space bases when a drag begins so neither axes nor derived bounds move underneath the pointer. Gizmo input captures the pointer ahead of scene picking and project UI interaction, then retains the physical window pointer even outside Game. SDL confines every active world-tool drag to the window; transform gestures also edge-wrap and shift their retained pointer anchors by the warp displacement. The ECS-built World/Local and Origin/Center viewport toolbar has priority over initial gizmo hit testing.

One transient snap policy serves pointer handles, modal transforms, and Model placement. Translation quantizes displacement along the gesture's frozen axes, rotation quantizes its accumulated angle, and scaling quantizes factors around identity. The viewport control enables or disables the policy and selects its translation spacing; holding the platform command modifier temporarily inverts it for the active gesture.

The editor's world grid is spatial reference geometry rather than an essential handle. WGPU renders a camera-centered procedural XZ plane into the HDR world before transparent geometry and tests it against scene depth. The grid is independent of transform snapping. One division level applies across the plane: close views show one-world-unit cells, and camera height above the plane selects progressively coarser power-of-ten levels. Minor lines fade into every tenth major line during a level transition. A planar outer-radius fade bounds the field without fading merely because the camera approaches the plane. The bounded camera-relative plane produces the visual behavior of an infinite grid without authored entities, retained line geometry, project lighting, or UI-overlay overdraw.

The component is part of the live engine world and appears in the component inspector, but it is not a scene TOML, Luau, or native-extension component and is never serialized into the project.

## Consequences

Handles and component icons remain visible and do not enter project scene data. Component icons retain a stable apparent size; selected-light influence geometry remains spatially meaningful. Selection, tool ownership, active transform mode, orientation space, manipulation pivot, snap settings, icon decluttering, and light-handle drag state remain transient editor state. The derived bounds cache and frozen gesture basis stay in the editor resource.

The editor supports snapped world- or local-oriented single-axis and two-axis plane translation, camera-plane free translation, world- or local-oriented axis rotation, local-component per-axis and two-axis scaling, uniform XYZ scaling selected with G, R, and S, and direct point-range or directional-light editing. The grid provides depth-correct spatial scale without becoming a scene entity. Editing an asset's imported origin, custom pivots, depth-aware handles, and multi-selection require later editor systems.
