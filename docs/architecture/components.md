# Engine Components

**Last verified:** 2026-07-21
**Source of truth:** `src/scrapbot/component/registry.odin`  
**Canonical public field reference:** `docs-website/src/content/docs/reference/components.md`

The engine registry gives every component a runtime-local ID, ownership, storage kind, lifecycle, field schema, cached namespace tokens, and presentation metadata. The current `advanced` hint never changes storage or authorability: it keeps a component inspectable while asking editor consumers to start its panel collapsed. This page inventories architecture and availability; keep exhaustive public fields and defaults in the public component reference.

Lifecycle meanings:

- **Authored:** users may attach/remove it, scene TOML may persist it, and editor history can own its membership.
- **Derived:** the engine reconciles it from authoritative state; users may inspect but must not author its membership or mutate renderer-owned values.

## Inventory

<!-- inventory:engine-components:start -->
| Component | Area | Lifecycle | User-facing | Architectural role |
| --- | --- | --- | --- | --- |
| `scrapbot.keyboard_input` | Runtime input | Derived | Read-only | Singleton per-frame keyboard held/pressed/released snapshot; scheduler-visible and not entity-attached. |
| `scrapbot.pointer_input` | Runtime input | Derived | Read-only | Singleton per-frame pointer position/delta/wheel/button snapshot; scheduler-visible and not entity-attached. |
| `scrapbot.transform` | Spatial | Authored | Yes | UUID-parented local position, rotation, and scale; source for resolved world transforms. |
| `scrapbot.camera` | Spatial/render | Authored | Yes | Selects camera projection data; project camera is distinct from the editor fly camera. |
| `scrapbot.ambient_light` | Lighting | Authored | Yes | Compact scene-wide ambient light input. |
| `scrapbot.directional_light` | Lighting | Authored | Yes | Directional light and current shadow-map source. |
| `scrapbot.point_light` | Lighting | Authored | Yes | Bounded local light using the entity's resolved world position. |
| `scrapbot.mesh` | Legacy render membership | Authored | Yes | Primitive-name mesh shortcut retained alongside resource-backed geometry/material components. |
| `scrapbot.geometry` | Render membership | Authored | Yes | Holds a resolved generational geometry resource handle. |
| `scrapbot.material` | Render membership | Authored | Yes | Holds a resolved generational material resource handle. |
| `scrapbot.model` | Render membership | Authored | Yes | UUID-backed imported model root; reconciles derived node/primitive render entities. |
| `scrapbot.shadow_caster` | Rendering | Authored | Yes | Marker enabling participation in shadow rendering. |
| `scrapbot.shadow_receiver` | Rendering | Authored | Yes | Marker enabling shadow reception. |
| `scrapbot.ui_layout` | UI layout | Authored | Yes | Public box model, UUID parent, responsive sizing, visibility, and tree-row metadata. |
| `scrapbot.ui_hstack` | UI layout | Authored | Yes | Horizontal flow, proportional fill, and optional draggable gaps. |
| `scrapbot.ui_vstack` | UI layout | Authored | Yes | Vertical flow, proportional fill, and optional draggable gaps. |
| `scrapbot.ui_scroll_area` | UI container | Authored | Yes | Retained smooth vertical scrolling, clipping, and scrollbar styling. |
| `scrapbot.ui_panel` | UI container | Authored | Yes | Titled/collapsible decoration with reusable title-band actions. |
| `scrapbot.ui_table` | UI container | Authored | Yes | Row-major multi-column layout with reusable proportions and separators. |
| `scrapbot.ui_list` | UI container | Authored | Yes | Selection plus generic list/tree drag, reorder, and reparent state. |
| `scrapbot.ui_text` | UI content | Authored | Yes | MTSDF text content and style. |
| `scrapbot.ui_progress` | UI content | Authored | Yes | Reusable bounded progress visualization. |
| `scrapbot.ui_state` | UI interaction | Derived | Read-only | Renderer-owned hover/focus/activation/change/drop state and monotonic revisions. |
| `scrapbot.ui_button` | UI control | Authored | Yes | Text or SDF-icon activation control consuming generic element state. |
| `scrapbot.ui_input` | UI control | Authored | Yes | Single-line text/numeric input with focus, selection, validation, stepping, and opt-in scrubbing. |
| `scrapbot.ui_checkbox` | UI control | Authored | Yes | Reusable SDF boolean control with read-only mode. |
| `scrapbot.internal.render_instance` | Rendering | Derived | No | Engine-owned stable render slot derived from renderable component membership. |
<!-- inventory:engine-components:end -->

## Per-component contracts

These entries deliberately omit exhaustive field/default documentation. Follow the public-reference link for authoring syntax and field behavior.

<!-- inventory:engine-component-details:start -->
### `scrapbot.keyboard_input`

- **Contract:** One immutable World-wide physical-key snapshot containing availability, focus, held state, and press/release edges.
- **Storage/lifecycle:** Dedicated ECS singleton resource; derived and platform-owned, with no entity slot or authored membership.
- **Producers:** Platform sampling once at the runtime frame boundary; deterministic renderer test injection.
- **Consumers:** Access-declared Luau and native gameplay systems through public input helpers.
- **Invalidation:** Replaced exactly once per runtime frame before project scheduling; no structural reconciliation or complete-world scan.
- **Surfaces:** Read-only Luau/native APIs and system access declarations; not scene TOML or entity queries.
- **Source/tests:** `shared/input.odin`, `platform/sdl3.odin`, `ecs/input.odin`, `render/render.odin`; `ecs/input_test.odin`, `platform/sdl3_test.odin`, `script/script_test.odin`.

### `scrapbot.pointer_input`

- **Contract:** One immutable World-wide pointer snapshot containing availability/capture, pixel position/delta, wheel delta, and button held/pressed/released state.
- **Storage/lifecycle:** Dedicated ECS singleton resource; derived and platform-owned, with no entity slot or authored membership.
- **Producers:** Platform sampling once at the runtime frame boundary; deterministic renderer test injection.
- **Consumers:** Access-declared Luau and native gameplay systems; UI/editor retain specialized downstream interaction interpretation.
- **Invalidation:** Replaced exactly once per runtime frame before project scheduling; no structural reconciliation or complete-world scan.
- **Surfaces:** Read-only Luau/native APIs and system access declarations; not scene TOML or entity queries.
- **Source/tests:** `shared/input.odin`, `platform/sdl3.odin`, `ecs/input.odin`, `render/render.odin`; `ecs/input_test.odin`, `platform/sdl3_test.odin`, `script/script_test.odin`.

### `scrapbot.transform`

- **Contract:** UUID-parented local position, Euler rotation, and scale; roots use local values as world values.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored.
- **Producers:** Scene loading, spawn/deferred commands, Luau and native writes, editor inspector/gizmo/history, playback restore.
- **Consumers:** Hierarchy resolution, render extraction, cameras, point lights, picking, gizmos, scene serialization.
- **Invalidation:** Attach/remove is structural; value and parent changes dirty exact render/world-transform consumers and hierarchy validation.
- **Surfaces:** Public in scene TOML, Luau, native Odin, and editor authoring; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbottransform).
- **Source/tests:** `ecs/world.odin`, `ecs/hierarchy.odin`, `ecs/commands.odin`; `ecs/world_test.odin`, `ecs/integrity_test.odin`.

### `scrapbot.camera`

- **Contract:** Perspective projection attached to an entity whose Transform supplies the project-camera pose.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored.
- **Producers:** Scene loading and editor/component authoring; membership is available to Luau/native commands.
- **Consumers:** Active-camera selection, render-view construction, editor camera mesh/frustum visualization, scene picking.
- **Invalidation:** Membership is structural; projection or Transform changes update compact camera input and selected-camera visualization.
- **Surfaces:** Public; scene/editor expose projection fields while current Luau/native handles primarily expose membership; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotcamera).
- **Source/tests:** `ecs/world.odin`, `render/render.odin`, `render/camera_visualizer.odin`; `render/camera_visualizer_test.odin`, `render/render_test.odin`.

### `scrapbot.ambient_light`

- **Contract:** Scene-wide ambient color and intensity independent of Transform.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored.
- **Producers:** Scene loading, Luau/native mutation, editor inspector/history.
- **Consumers:** Render preparation and world-lighting uniforms.
- **Invalidation:** Membership is structural; value changes dirty the compact lighting input rather than renderable membership.
- **Surfaces:** Public across scene TOML, Luau, native Odin, and editor authoring; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#lights-and-shadows).
- **Source/tests:** `ecs/world.odin`, `render/render.odin`, `render/wgpu.odin`; `ecs/world_test.odin`, `render/render_test.odin`.

### `scrapbot.directional_light`

- **Contract:** Directional color/intensity input; the first active directional light supplies the current shadow view.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored.
- **Producers:** Scene loading, Luau/native mutation, editor inspector/history.
- **Consumers:** World lighting, shadow-camera preparation, shadow rendering.
- **Invalidation:** Membership is structural; direction/color/intensity changes dirty compact light/shadow inputs.
- **Surfaces:** Public across scene TOML, Luau, native Odin, and editor authoring; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#lights-and-shadows).
- **Source/tests:** `ecs/world.odin`, `render/render.odin`, `render/wgpu.odin`; `ecs/world_test.odin`, `render/render_test.odin`.

### `scrapbot.point_light`

- **Contract:** Bounded color/intensity/range input positioned by the entity's resolved world Transform.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored.
- **Producers:** Scene loading, Luau/native mutation, editor inspector/history.
- **Consumers:** Hierarchy/world-transform resolution and compact point-light render inputs.
- **Invalidation:** Membership is structural; light values or the paired Transform dirty the exact compact light input.
- **Surfaces:** Public across scene TOML, Luau, native Odin, and editor authoring; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#lights-and-shadows).
- **Source/tests:** `ecs/world.odin`, `ecs/hierarchy.odin`, `render/render.odin`; `ecs/world_test.odin`, `render/render_test.odin`.

### `scrapbot.mesh`

- **Contract:** Legacy primitive-name shortcut that resolves built-in geometry and material for render eligibility.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored.
- **Producers:** Scene loading, spawn/deferred commands, editor component authoring.
- **Consumers:** Render-instance reconciliation and resource render-list extraction.
- **Invalidation:** Attach/remove/name replacement is structural and re-evaluates the entity's retained render slot.
- **Surfaces:** Public; scene/editor author the primitive while current Luau/native access is membership-oriented; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotmesh).
- **Source/tests:** `ecs/world.odin`, `ecs/commands.odin`, `render/render.odin`; `ecs/world_test.odin`, `ecs/registered_components_test.odin`.

### `scrapbot.geometry`

- **Contract:** Generational handle to a shared geometry resource used with Transform and Material.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored reference to registry-owned data.
- **Producers:** Scene resource resolution, Luau/native resource APIs, editor authoring and playback restore.
- **Consumers:** Render-instance reconciliation, retained render list, GPU draw/batch database.
- **Invalidation:** Membership/handle changes are structural; resource topology/content versions invalidate affected retained/GPU state.
- **Surfaces:** Public; persistent scenes store a resource name while ECS stores a resolved handle; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotgeometry-and-scrapbotmaterial).
- **Source/tests:** `ecs/world.odin`, `resources/`, `render/wgpu_gpu_driven.odin`; `ecs/world_test.odin`, `resources/resources_test.odin`.

### `scrapbot.material`

- **Contract:** Generational handle to a shared material resource used with Transform and Geometry.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored reference to registry-owned data.
- **Producers:** Scene UUID resolution, Luau/native resource APIs, editor resource authoring and playback restore.
- **Consumers:** Render-instance reconciliation, retained render list, material GPU cache and world/postprocess shading.
- **Invalidation:** Membership/handle changes are structural; resource content/topology versions invalidate affected retained/GPU state.
- **Surfaces:** Public; persistent scenes store a stable resource UUID while ECS stores a resolved handle; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotgeometry-and-scrapbotmaterial).
- **Source/tests:** `ecs/world.odin`, `resources/`, `project/resources.odin`, `render/wgpu_gpu_driven.odin`; `ecs/world_test.odin`, `project/project_test.odin`.

### `scrapbot.model`

- **Contract:** References one authored Model UUID from a scene root entity.
- **Storage/lifecycle:** Authored UUID reference on the root; imported nodes and primitives are derived Runtime-origin ECS entities owned by that root.
- **Producers:** Scene TOML, editor reflected authoring, resource/bootstrap reconciliation.
- **Consumers:** Model-instance reconciliation, then ordinary transform hierarchy and render extraction through derived Geometry/Material entities.
- **Invalidation:** Model import/version or world replacement removes and recreates only the root's derived hierarchy with deterministic child UUIDs; ordinary frames do not scan model resources.
- **Surfaces:** Public scene TOML, component membership queries, and editor inspection; generated children are not persistent source.
- **Source/tests:** `asset_import/models.odin`, `resources/models.odin`, `scrapbot.odin`; `asset_import/models_test.odin`, `model_instance_test.odin`.

### `scrapbot.shadow_caster`

- **Contract:** Empty marker opting eligible renderable geometry into directional-shadow casting.
- **Storage/lifecycle:** Dedicated marker storage; authored.
- **Producers:** Scene loading, deferred commands, Luau/native/editor component membership changes.
- **Consumers:** Render-instance batch keys, visibility, and shadow-pass encoding.
- **Invalidation:** Attach/remove is structural and updates the affected retained render slot/batch.
- **Surfaces:** Public across scene TOML, Luau, native Odin, and editor authoring; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#lights-and-shadows).
- **Source/tests:** `ecs/world.odin`, `render/wgpu_gpu_driven.odin`; `ecs/world_test.odin`, `render/render_test.odin`.

### `scrapbot.shadow_receiver`

- **Contract:** Empty marker opting eligible renderable geometry into directional-shadow sampling.
- **Storage/lifecycle:** Dedicated marker storage; authored.
- **Producers:** Scene loading, deferred commands, Luau/native/editor component membership changes.
- **Consumers:** Render-instance batch/material flags and world shading.
- **Invalidation:** Attach/remove is structural and updates the affected retained render slot/batch.
- **Surfaces:** Public across scene TOML, Luau, native Odin, and editor authoring; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#lights-and-shadows).
- **Source/tests:** `ecs/world.odin`, `render/wgpu_gpu_driven.odin`; `ecs/world_test.odin`, `render/render_test.odin`.

### `scrapbot.ui_layout`

- **Contract:** Required UI geometry/hierarchy box containing UUID parent, sizing, box style, visibility, and tree-row metadata.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Scene TOML, Luau/native UI APIs, editor composition, generic UI setters.
- **Consumers:** Retained hierarchy, layout, clipping, interaction hit testing, painting, tree/list mechanics.
- **Invalidation:** Attach/remove/parent changes enqueue structural work; layout-affecting setters advance layout revision and visual setters advance paint revision.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_layout).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ecs/ui_components_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_hstack`

- **Contract:** Horizontal child flow with gaps, proportional fill, minimum panes, and optional draggable separators.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Retained UI layout and generic separator interaction.
- **Invalidation:** Membership and flow-option mutations invalidate the affected hierarchy/layout domain; separator drags target pane sizes.
- **Surfaces:** Shared public UI contract across scene TOML, Luau, native Odin, and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_hstack-and-scrapbotui_vstack).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_vstack`

- **Contract:** Vertical child flow with gaps, proportional fill, minimum panes, and optional draggable separators.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Retained UI layout and generic separator interaction.
- **Invalidation:** Membership and flow-option mutations invalidate the affected hierarchy/layout domain; separator drags target pane sizes.
- **Surfaces:** Shared public UI contract across scene TOML, Luau, native Odin, and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_hstack-and-scrapbotui_vstack).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_scroll_area`

- **Contract:** Clipped viewport with retained fractional scroll position, smooth scrolling, nested routing, and scrollbar style.
- **Storage/lifecycle:** Dedicated typed UI storage plus reconciler-owned retained scroll state; authored component.
- **Producers:** Public project UI surfaces and editor composition; pointer wheel updates retained target/current offsets.
- **Consumers:** Layout clipping, pointer routing, painting, and scrollbar generation.
- **Invalidation:** Geometry/options invalidate layout/paint; wheel input dirties only the deepest eligible scroll area and subsequent smoothing frames.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_scroll_area).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_panel`

- **Contract:** Optional titled/collapsible framing whose direct panel-action buttons occupy the title band.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Layout, disclosure interaction, title/action placement, SDF painting.
- **Invalidation:** Title/collapse/geometry mutations invalidate affected layout and paint; collapsed descendants remain ECS members but leave visible traversal.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_panel).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_table`

- **Contract:** Row-major 1–64-column layout with gaps, proportional widths, and optional reusable column separators.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Retained table measurement/layout and generic separator interaction.
- **Invalidation:** Column/options/child changes invalidate table layout; separator drags update reusable column proportions.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_table).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_list`

- **Contract:** Full-width selectable child rows with optional drag/reorder/reparent and flattened UUID tree metadata.
- **Storage/lifecycle:** Dedicated typed UI storage plus retained gesture state; authored component.
- **Producers:** Public project UI surfaces, editor entity/system browsers, pointer interactions.
- **Consumers:** Selection, tree flattening, drop classification/painting, editor bindings via generic `ui_state` events.
- **Invalidation:** Membership/tree metadata changes invalidate hierarchy/layout; hover/selection/drag changes target interaction/paint state and completed drops advance a revision.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_list).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_progress`

- **Contract:** Bounded reusable progress track/fill, including right-to-left presentation.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor system-performance composition.
- **Consumers:** Retained measurement and SDF paint generation.
- **Invalidation:** Value/style mutations dirty paint; geometry/inset changes also dirty layout where measurement changes.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_progress).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_text`

- **Contract:** Font-selected MTSDF text with color, size, and alignment.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Text measurement, layout, glyph-atlas lookup, UI paint/vertex conversion.
- **Invalidation:** Text/font/size changes dirty measurement/layout and paint; color/alignment changes dirty paint or placement as applicable.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_text).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`, `project/fonts.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_button`

- **Contract:** Text and/or reusable SDF-icon activation control consuming generic pointer/focus state.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Measurement, hit testing, hover/active painting, activation bindings, panel title actions.
- **Invalidation:** Content/style changes dirty layout/paint; pointer/keyboard edges target interaction state and activation revision.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_button).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/diagnostic_driver_test.odin`.

### `scrapbot.ui_input`

- **Contract:** Single-line text/numeric editor with selection, navigation, validation, staged Enter-to-commit numeric typing, cancel-on-focus-transfer, and opt-in live numerical scrubbing.
- **Storage/lifecycle:** Dedicated typed UI storage plus retained caret/selection/scrub state; authored component.
- **Producers:** Public project UI surfaces, editor reflected-field bindings, keyboard/pointer input.
- **Consumers:** Measurement, focus/navigation order, editing/validation, paint, editor history bindings.
- **Invalidation:** External value/style changes target layout/paint; numeric keyboard edits change only retained text/validity until submission, while live scrubbing advances change revisions and release advances submission without rebuilding unrelated UI.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_input).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`, `ui/editor_inspector_binding.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_checkbox`

- **Contract:** SDF boolean control with hover/active appearance and read-only mode.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces, editor boolean-field bindings, pointer/keyboard activation.
- **Consumers:** Measurement, hit testing, SDF painting, generic changed/activation binding.
- **Invalidation:** Checked/style changes dirty paint; activation targets the control's interaction/change revision.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_checkbox).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`, `ui/editor_inspector_binding.odin`; `ui/ui_test.odin`, `ecs/ui_components_test.odin`.

### `scrapbot.ui_state`

- **Contract:** Read-only hover, active, focus, editing, activation, and drag/drop state with monotonic event revisions.
- **Storage/lifecycle:** Dedicated typed UI storage; derived and renderer-owned.
- **Producers:** Retained UI reconciliation and interaction processing only; despawn/UI disappearance releases its slot.
- **Consumers:** Luau/native project systems and editor bindings that react without depending on one-frame booleans.
- **Invalidation:** Targeted interaction-dirty queues update affected nodes; transient edges reset without rewriting authored UI components.
- **Surfaces:** Publicly queryable but invalid in scene authoring, spawn payloads, and component writes; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_state).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ecs/ui_components_test.odin`, `ui/ui_test.odin`.

### `scrapbot.internal.render_instance`

- **Contract:** Stable engine render slot joining an entity to resolved geometry/material/shadow batch state.
- **Storage/lifecycle:** Dedicated render-instance storage; internal derived component.
- **Producers:** Render-instance reconciliation adds/releases slots from exact renderable membership and resource resolution changes.
- **Consumers:** Backend-neutral render list, WGPU instance table, batch database, visibility and draw encoding.
- **Invalidation:** Structural/render dirty queues mutate the affected slot; free-slot reuse and generational resources prevent complete-world stable-frame rebuilds.
- **Surfaces:** Internal only; rejected from scene, Luau, native extension, and editor authoring surfaces.
- **Source/tests:** `ecs/world.odin`, `render/render.odin`, `render/wgpu_gpu_driven.odin`; `ecs/world_test.odin`, `ecs/registered_components_test.odin`.
<!-- inventory:engine-component-details:end -->

## User-defined components

- Project components use one name token and register through Luau.
- Library/native components use dotted names outside the reserved `scrapbot` namespace.
- Custom storage supports Number, Vec2, Vec3, Vec4, and semantic Color fields plus shared editor metadata.
- Scene TOML, Luau, native Odin, generated declarations, editor reflection, history, and persistence consume the same registry definition.

## Membership and mutation

- Entity records keep generational indexes into typed component storage; custom component storage additionally maintains compact active indexes.
- Component attach/remove, spawn/despawn, world replacement, and relevant resource changes enqueue structural dirtiness.
- Render-affecting value changes enqueue exact retained-extraction updates.
- UI mutations use typed setters to advance the correct project/editor layout or paint revision.
- `scrapbot.ui_state` and `scrapbot.internal.render_instance` must only be produced by their owning engine systems.

See [ADR-007](../adr/ADR-007-use-id-keyed-component-storage.md), [ADR-024](../adr/ADR-024-update-derived-ecs-state-from-structural-changes.md), and [ADR-025](../adr/ADR-025-use-one-public-ecs-ui-contract.md).
