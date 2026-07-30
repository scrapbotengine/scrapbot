# Engine Components

**Last verified:** 2026-07-30
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
| `scrapbot.camera` | Spatial/render | Authored | Yes | Selects camera projection, manual or GPU-budgeted world render-grid scale, fixed or GPU-adaptive exposure, and per-view TAA/fast-AA/AO/SSR/bloom policy; project camera is distinct from the editor fly camera. |
| `scrapbot.world_environment` | Environment/render | Authored | Yes | Singleton scene selection for imported lighting, procedural or imported sky presentation, and base exposure. |
| `scrapbot.volumetric_fog` | Environment/render | Authored | Yes | Singleton global height/distance medium with ambient, shadowed directional, and clustered point-light scattering. |
| `scrapbot.ambient_light` | Lighting | Authored | Yes | Compact scene-wide ambient light input. |
| `scrapbot.directional_light` | Lighting | Authored | Yes | Directional light and current shadow-map source. |
| `scrapbot.point_light` | Lighting | Authored | Yes | Bounded local light using the entity's resolved world position. |
| `scrapbot.mesh` | Legacy render membership | Authored | Yes | Primitive-name mesh shortcut retained alongside resource-backed geometry/material components. |
| `scrapbot.geometry` | Render membership | Authored | Yes | Holds a resolved generational geometry resource handle. |
| `scrapbot.material` | Render membership | Authored | Yes | Holds a resolved generational material resource handle. |
| `scrapbot.model` | Render membership | Authored | Yes | UUID-backed imported model root; reconciles derived node/primitive render entities. |
| `scrapbot.shadow_caster` | Rendering | Authored | Yes | Marker enabling participation in shadow rendering. |
| `scrapbot.shadow_receiver` | Rendering | Authored | Yes | Marker enabling shadow reception. |
| `scrapbot.ui_layout` | UI layout | Authored | Yes | Public box model, UUID parent/popup anchor, responsive sizing, visibility, and list/stack sibling order metadata. |
| `scrapbot.ui_canvas` | UI layout | Authored | Yes | Singleton project-origin root policy for logical reference size, output scaling/alignment, safe area, and scale bounds. |
| `scrapbot.ui_hstack` | UI layout | Authored | Yes | Horizontal fixed, proportional, wrapping, resizable, or reorderable flow. |
| `scrapbot.ui_vstack` | UI layout | Authored | Yes | Vertical fixed, proportional, wrapping, resizable, or reorderable flow. |
| `scrapbot.ui_scroll_area` | UI container | Authored | Yes | Retained smooth vertical scrolling, clipping, and scrollbar styling. |
| `scrapbot.ui_panel` | UI container | Authored | Yes | Titled/collapsible/movable decoration with reusable title-band actions. |
| `scrapbot.ui_dock_space` | UI container | Authored | Yes | Styled tab group whose direct items transfer between groups or create public resizable split topology from enabled edges. |
| `scrapbot.ui_dock_item` | UI layout | Authored | Yes | Direct dock-space child carrying reusable tab identity and movement policy. |
| `scrapbot.ui_table` | UI container | Authored | Yes | Row-major multi-column layout with reusable proportions and separators. |
| `scrapbot.ui_list` | UI container | Authored | Yes | Styled, filtered, and virtualized selection plus generic list/tree drag, reorder, and reparent state. |
| `scrapbot.ui_text` | UI content | Authored | Yes | Intrinsically measured, optionally wrapped MTSDF text. |
| `scrapbot.ui_icon` | UI content | Authored | Yes | UUID-backed symbolic MTSDF icon content shared by projects, controls, themes, and editor chrome. |
| `scrapbot.ui_progress` | UI content | Authored | Yes | Reusable bounded progress visualization. |
| `scrapbot.ui_viewport` | UI content | Authored | Yes | Interactive renderer-backed Texture, Model, Material, or World surface composited through ordinary UI paint. |
| `scrapbot.ui_state` | UI interaction | Derived | Read-only | Renderer-owned hover/focus/activation/change/drop state and monotonic revisions. |
| `scrapbot.ui_action` | UI semantics | Authored | Yes | Inheritable semantic action and payload copied into immutable UI events. |
| `scrapbot.ui_button` | UI control | Authored | Yes | Text or SDF-icon activation control with an optional popup target UUID. |
| `scrapbot.ui_input` | UI control | Authored | Yes | Single-line text/numeric input with optional icon, focus, selection, validation, stepping, and opt-in scrubbing. |
| `scrapbot.ui_checkbox` | UI control | Authored | Yes | Reusable SDF boolean control with read-only mode. |
| `scrapbot.ui_color_picker` | UI control | Authored | Yes | Linear RGBA color control with optional HDR exposure and alpha tracks. |
| `scrapbot.internal.render_instance` | Rendering | Derived | No | Engine-owned stable render slot derived from renderable component membership. |
| `scrapbot.internal.editor_transform_gizmo` | Editor tooling | Derived | No | Transient selected-entity gizmo ownership and active manipulation mode. |
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

- **Contract:** Perspective projection, backend-neutral debug view, a bounded `0.5`–`1` world render-grid ceiling, optional GPU-budgeted dynamic resolution with a bounded floor and positive millisecond target, positive fixed exposure or opt-in GPU-adaptive exposure, and per-view temporal-AA, fast-AA, ambient-occlusion, screen-space-reflection, and bloom policy attached to an entity whose Transform supplies the project-camera pose. Debug views cover lit output, material inputs, mapped normals, logarithmic depth, retained meshlet identity, selected LOD, and GPU visibility classification. AO and SSR expose bounded `0.25`–`1` sample-quality tiers. Automatic exposure clamps to authored positive bounds, adapts at an authored positive inverse-seconds rate, and treats manual exposure as compensation. TAA takes precedence over fast AA. Zero-valued legacy/programmatic components normalize to lit output, native render scale `1`, dynamic floor `0.5`, dynamic target `16.667` ms, fixed exposure `1`, automatic bounds `0.125`–`8`, speed `2`, and balanced AO/SSR quality `0.5`; authored TOML defaults dynamic resolution and automatic exposure off, TAA/AO/bloom on, and fast AA/SSR off.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored.
- **Producers:** Scene loading, editor/component authoring, validated Luau query writeback, and native membership commands.
- **Consumers:** Active-camera selection, GPU-timestamp dynamic-resolution control, scaled world/depth/post target layout, render-view/debug construction, postprocess dispatch/jitter/history/exposure policy, global environment uniform, visible-sky ray construction, editor Game-view override, camera mesh/frustum visualization, and scene picking.
- **Invalidation:** Membership is structural; projection, debug view, render-scale policy, exposure, render-feature, quality, or Transform changes update compact camera input. A debug-view change updates the retained render/cull uniform and post policy without rebuilding membership or geometry; non-lit modes skip presentation effects. Visibility diagnostics write bounded frame-valued rejection records only while selected. The editor override mutates only the extracted camera copy. Dynamic resolution consumes each asynchronously completed timestamp exactly once, excludes native UI time, filters the result, and changes scale only after bounded hysteresis. Timestamp samples carry the controller generation, while the stable project-camera UUID owns controller identity even when the editor fly camera supplies pose/lens. A scale, policy, or owner change rejects delayed evidence and resets filtered state. The controller never mutates the authored camera. An effective-scale step lazily replaces only the owned scaled depth and size-dependent post targets and rejects temporal history; stable scale reuses them and native scale reuses the output depth target. Unsupported timestamps fall back to the authored ceiling. Fixed exposure changes rewrite only the environment uniform. Automatic exposure uses a persistent GPU scalar and one bounded metering dispatch per enabled frame; disabling it restores scalar `1` once and performs no metering work. AO and SSR quality change only the next uniform and loop bound; neither rebuilds retained post targets. TAA mode changes reject temporal history; disabled AO/SSR/bloom skip their compute work.
- **Surfaces:** Public in scene TOML, generated Luau query data/writeback, automatic editor inspection/history, and persistence; native Odin currently exposes membership. See the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotcamera).
- **Source/tests:** `ecs/world.odin`, `render/render.odin`, `render/camera_visualizer.odin`; `render/camera_visualizer_test.odin`, `render/render_test.odin`.

### `scrapbot.world_environment`

- **Contract:** At most one authored component per scene selects Environment-resource UUIDs for image-based lighting and the visible background, plus independent diffuse/specular lighting strength and presentation values. An enabled empty background selects the art-directable procedural atmosphere with its own world-space HDR sun.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored singleton-by-validation, attached to an ordinary selectable scene entity.
- **Producers:** Scene loading, automatic editor reflection/history, component membership commands, and playback restore.
- **Consumers:** The fixed `scrapbot.environment` phase resolves UUIDs to generational Environment handles and updates the renderer-facing resource-registry cache, including procedural color/haze/sun controls. Backend-neutral light extraction inserts an above-horizon procedural sun as the first derived directional-light input without mutating World entities; WGPU consumes that light through ordinary GGX/shadow paths and derives horizon-clipped sky presentation plus procedural fill from the same retained state.
- **Invalidation:** Structural membership changes rediscover the singleton. Value changes compare the retained entity component revision. Stable frames do not scan World entities or resources.
- **Surfaces:** Public in scene TOML, Luau membership/query data, native membership, editor authoring, and persistence; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotworld_environment).
- **Source/tests:** `resources/environments.odin`, `ecs/world.odin`, `render/wgpu_environment.odin`; `project/project_test.odin`, `resources/resources_test.odin`, `ecs/world_test.odin`, WGPU day/night framegrab smoke tests.

### `scrapbot.volumetric_fog`

- **Contract:** At most one authored component per scene configures a global exponential height medium, distance bound, scattering color, directional anisotropy, ambient fill, primary-light strength, and independently opt-in clustered point-light strength. Absence or zero density disables the effect.
- **Storage/lifecycle:** Registry-defined custom ECS storage with canonical Number/Vec3 fields; authored singleton-by-validation on an ordinary entity.
- **Producers:** Scene loading, automatic type-inspected editor controls/history, validated Luau writes, component membership commands, and playback restore.
- **Consumers:** WGPU postprocessing reads the compact active storage, clamps its reflected payload, and integrates a bounded 16-step view ray against scene depth. The first directional light and four-cascade shadow array supply filtered in-scattering. Each ray step reads the complete relevant point-light list from the same GPU-built view-frustum cluster used by surface lighting.
- **Invalidation:** Membership and value mutation use ordinary custom-component lifecycle/revisions. The current bounded frame input visits only the fog storage's compact active set; it never scans entities or component capacity. No fog-specific GPU target is allocated, and zero density takes the shader no-op branch.
- **Surfaces:** Public in scene TOML, generated Luau query data/writeback, native membership, runtime-generated editor inspection, history, and persistence; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotvolumetric_fog).
- **Source/tests:** `component/registry.odin`, `project/project.odin`, `render/wgpu_post.odin`, `render/wgpu_shader.odin`; `component/registry_test.odin`, `render/render_test.odin`, Sponza WGPU framegrab smoke tests.

### `scrapbot.ambient_light`

- **Contract:** Scene-wide ambient color and intensity independent of Transform.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored.
- **Producers:** Scene loading, Luau/native mutation, editor inspector/history.
- **Consumers:** Render preparation and world-lighting uniforms.
- **Invalidation:** Membership is structural; value changes dirty the compact lighting input rather than renderable membership.
- **Surfaces:** Public across scene TOML, Luau, native Odin, and editor authoring; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#lights-and-shadows).
- **Source/tests:** `ecs/world.odin`, `render/render.odin`, `render/wgpu.odin`; `ecs/world_test.odin`, `render/render_test.odin`.

### `scrapbot.directional_light`

- **Contract:** Directional color/intensity input; the first active directional light supplies the current four-cascade shadow direction.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored.
- **Producers:** Scene loading, Luau/native mutation, editor inspector/history.
- **Consumers:** World lighting, shadow-camera preparation, shadow rendering.
- **Invalidation:** Membership is structural; direction/color/intensity changes dirty compact light/shadow inputs.
- **Surfaces:** Public across scene TOML, Luau, native Odin, and editor authoring; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#lights-and-shadows).
- **Source/tests:** `ecs/world.odin`, `render/render.odin`, `render/wgpu.odin`; `ecs/world_test.odin`, `render/render_test.odin`.

### `scrapbot.point_light`

- **Contract:** Bounded color/intensity/range input positioned by the entity's resolved world Transform.
- **Storage/lifecycle:** Dedicated typed ECS storage; authored or runtime-spawned, with dead typed slots reused across entity lifetimes.
- **Producers:** Scene loading, validated deferred Luau spawn, native mutation, editor inspector/history.
- **Consumers:** Hierarchy/world-transform resolution, compact point-light render inputs, and WGPU's GPU-built clustered-light table.
- **Invalidation:** Membership is structural; light values or the paired Transform dirty the exact compact light input.
- **Surfaces:** Public across scene TOML, Luau, native Odin, and editor authoring; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#lights-and-shadows).
- **Source/tests:** `ecs/world.odin`, `ecs/commands.odin`, `script/commands.odin`, `ecs/hierarchy.odin`, `render/render.odin`; `script/commands_test.odin`, `ecs/world_test.odin`, `render/render_test.odin`.

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

- **Contract:** Required UI geometry/hierarchy box containing UUID parent, authored/minimum sizing, per-child basis/grow/shrink and stack order, per-axis alignment, box style, visibility, tree-row metadata, and optional root-popup anchor/open/viewport constraints.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Scene TOML, Luau/native UI APIs, editor composition, generic UI setters.
- **Consumers:** Retained hierarchy, intrinsic/flex layout, clipping, interaction hit testing, painting, tree/list mechanics, and generic popup placement/dismissal.
- **Invalidation:** Attach/remove/parent changes enqueue structural work; layout-affecting setters advance layout revision and visual setters advance paint revision. Popup open/anchor/constraint changes target the affected domain; stable closed or unchanged popups do no derived work.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_layout).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ecs/ui_components_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_canvas`

- **Contract:** Optional singleton root policy per entity-origin domain selecting a logical reference size, fit/fill/expand/stretch/pixel-perfect/native-density scaling, host alignment, safe-area insets, and scale bounds.
- **Storage/lifecycle:** Dedicated typed UI storage; authored, root-only, and dependent on `ui_layout`.
- **Producers:** Scene TOML, Luau/native UI APIs, editor inspection/history, and generic UI setters.
- **Consumers:** Retained root layout, WGPU project UI vertices/clips, embedded viewport sizing, pointer inversion, and semantic diagnostic screen rectangles.
- **Invalidation:** Attach/remove changes exact retained membership; value changes advance only the matching project/editor layout domain. The reconciler caches the active slot by origin, so stable frames perform no canvas search or derived work.
- **Surfaces:** Shared public UI contract across scene TOML, Luau, generated declarations, native Odin, persistence, and editor inspection; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_canvas).
- **Source/tests:** `shared/types.odin`, `ecs/ui_components.odin`, `ui/ui.odin`, `render/wgpu.odin`; `ecs/ui_components_test.odin`, `project/project_test.odin`, `script/ui_components_test.odin`, `native/ui_test.odin`, `ui/ui_test.odin`.

### `scrapbot.ui_hstack`

- **Contract:** Horizontal child flow with gaps, proportional fill, minimum panes, optional draggable separators, title-drag panel ordering/transfers, and line-wrapped basis/grow/shrink resolution.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Retained UI layout, generic separator interaction, and generic panel-title reorder interaction.
- **Invalidation:** Membership, order, and flow-option mutations invalidate the affected hierarchy/layout domain; separator drags target pane sizes and completed panel drops normalize only affected public sibling orders. Stable frames perform no ordering work.
- **Surfaces:** Shared public UI contract across scene TOML, Luau, native Odin, and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_hstack-and-scrapbotui_vstack).
- **Source/tests:** `shared/types.odin`, `ecs/ui_components.odin`, `ui/ui.odin`; `project/project_test.odin`, `script/ui_components_test.odin`, `native/ui_test.odin`, `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_vstack`

- **Contract:** Vertical child flow with gaps, proportional fill, minimum panes, optional draggable separators, title-drag panel ordering/transfers, and line-wrapped basis/grow/shrink resolution.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Retained UI layout, generic separator interaction, and generic panel-title reorder interaction.
- **Invalidation:** Membership, order, and flow-option mutations invalidate the affected hierarchy/layout domain; separator drags target pane sizes and completed panel drops normalize only affected public sibling orders. Stable frames perform no ordering work.
- **Surfaces:** Shared public UI contract across scene TOML, Luau, native Odin, and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_hstack-and-scrapbotui_vstack).
- **Source/tests:** `shared/types.odin`, `ecs/ui_components.odin`, `ui/ui.odin`; `project/project_test.odin`, `script/ui_components_test.odin`, `native/ui_test.odin`, `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_scroll_area`

- **Contract:** Clipped viewport with retained fractional scroll position, smooth scrolling, nested routing, and scrollbar style.
- **Storage/lifecycle:** Dedicated typed UI storage plus reconciler-owned retained scroll state; authored component.
- **Producers:** Public project UI surfaces and editor composition; pointer wheel updates retained target/current offsets.
- **Consumers:** Layout clipping, pointer routing, painting, and scrollbar generation.
- **Invalidation:** Geometry/options invalidate layout/paint; wheel input dirties only the deepest eligible scroll area and subsequent smoothing frames.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_scroll_area).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_panel`

- **Contract:** Optional titled/collapsible framing whose direct panel-action buttons occupy the title band and whose unoccupied title band can opt into stack reordering or dock transfer.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Layout, disclosure and thresholded workspace interaction, dock-tab derivation, title/action placement, SDF painting.
- **Invalidation:** Title/collapse/geometry mutations invalidate affected layout and paint; drag visuals repaint only during the active gesture, completed drops mutate public parent/order and synchronously refresh retained parent links before relayout, and collapsed descendants remain ECS members but leave visible traversal.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_panel).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_dock_space`

- **Contract:** Independently styled tab rail physically joined to a shared padded content sheet behind the active direct dock-item or titled-panel child, with a stable active UUID, opt-in cross-container transfer target, and opt-in horizontal/vertical edge splitting.
- **Storage/lifecycle:** Dedicated typed UI storage plus bounded reconciler-owned tab hit/gesture state; authored component. Completed edge drops create runtime-origin project or editor-origin public layout, stack, and dock-space entities.
- **Producers:** Scene TOML, Luau/native mutation, project UI composition, and editor workspace composition.
- **Consumers:** Retained layout, tab and shared-sheet measurement/paint, pointer selection, UUID reparenting, public split-topology construction, generic drop state, and immutable UI events.
- **Invalidation:** Membership, active UUID, tab/sheet/split metrics, title/font, or item-parent changes invalidate only the affected UI domain. Hover/drag changes paint state; a completed transfer or split uses ordinary `ui_layout` structural invalidation. Stable frames do no tab discovery, split construction, or paint rebuild.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_dock_space).
- **Source/tests:** `shared/types.odin`, `ecs/ui_components.odin`, `ui/ui.odin`; `project/project_test.odin`, `script/ui_components_test.odin`, `native/ui_test.odin`, `ui/ui_test.odin`, `ui/diagnostic_driver_test.odin`.

### `scrapbot.ui_dock_item`

- **Contract:** Titled direct child of one dock space whose complete content becomes one selectable and optionally movable tab.
- **Storage/lifecycle:** Dedicated typed UI storage; authored component paired with ordinary public layout parenting.
- **Producers:** Scene TOML, Luau/native mutation, project UI composition, and editor workspace composition.
- **Consumers:** Parent dock-space tab measurement, active-child layout, transfer eligibility, reflection, and persistence.
- **Invalidation:** Title/movement changes invalidate targeted layout or paint; reparenting follows the canonical layout structural queue.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_dock_item).
- **Source/tests:** `shared/types.odin`, `ecs/ui_components.odin`, `ui/ui.odin`; `project/project_test.odin`, `script/ui_components_test.odin`, `native/ui_test.odin`, `scene_persistence_test.odin`.

### `scrapbot.ui_table`

- **Contract:** Row-major 1–64-column layout with gaps, proportional widths, and optional reusable column separators.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Retained table measurement/layout and generic separator interaction.
- **Invalidation:** Column/options/child changes invalidate table layout; separator drags update reusable column proportions.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_table).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_list`

- **Contract:** Full-width selectable child rows with shared rounded highlight styling, optional input-driven descendant-content filtering, uniform-row virtualization, drag/reorder/reparent, and flattened UUID tree metadata.
- **Storage/lifecycle:** Dedicated typed UI storage plus retained gesture, compact flow-order, and scroll-window state; authored component.
- **Producers:** Public project UI surfaces, editor entity/resource/system browsers, registry-driven component, reflected-enum, and UUID entity-reference pickers, and pointer interactions.
- **Consumers:** Selection, filtered tree flattening, virtual layout, drop classification/painting, editor bindings via generic `ui_state` events.
- **Invalidation:** Membership, tree metadata, referenced filter-input text, or searchable descendant content invalidates the affected list layout. Compact row order rebuilds only on that domain's structural/layout revision; scroll-only layout reuses it and visits the visible window plus overscan. Hover/selection/drag changes target interaction/paint state and completed drops advance a revision.
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

### `scrapbot.ui_viewport`

- **Contract:** Embeds a Texture, Model, or Material resource UUID—or the retained active World—inside an ordinary layout box, with optional World camera/root UUIDs plus orbit, distance, clear color, and interaction policy.
- **Storage/lifecycle:** Dedicated typed UI storage; authored component with reconciler-owned drag state and renderer-owned pooled color/depth targets and caches.
- **Producers:** Scene TOML, Luau/native UI APIs, editor composition, and generic ECS setters.
- **Consumers:** Retained viewport membership, shared pointer orbit/zoom interaction, WGPU offscreen rendering, and ordinary clipped UI paint.
- **Invalidation:** Membership follows structural dirty queues; value changes update the bounded active viewport set without rebuilding UI paint. Target dimensions resize only when the quantized laid-out size changes. Static Texture/Model/Material previews redraw only when component, target shape, exact resource version, or relevant registry revisions change; World targets consume the retained render list.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_viewport).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`, `render/wgpu_viewports.odin`; `ecs/ui_components_test.odin`, `ui/ui_retained_test.odin`, headless WGPU asset-preview diagnostics.

### `scrapbot.ui_icon`

- **Contract:** Resolves an icon-set resource UUID plus stable symbol name, applies a linear HDR tint, preserves the compiled plane aspect, and fits the result into the padded layout box with a non-negative inset.
- **Storage/lifecycle:** Dedicated typed UI storage; authored. Icon strings are World-owned and reclaimed with the component slot.
- **Producers:** Scene TOML, Luau/native UI APIs, editor composition, button and panel control composition.
- **Consumers:** Retained measurement/paint, icon-set symbol lookup, the shared MTSDF texture array, and WGPU UI vertex conversion.
- **Invalidation:** Component setters dirty only the affected UI domain. Icon-set registration/reimport advances a registry-wide monotonic revision; stable sets do not rebuild paint or upload atlas layers, while a changed entry uploads only its retained array layer.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_icon).
- **Source/tests:** `ecs/ui_components.odin`, `resources/icons.odin`, `ui/ui.odin`, `render/wgpu.odin`; `resources/resources_test.odin`, `ui/ui_test.odin`, headless WGPU icon framegrabs.

### `scrapbot.ui_text`

- **Contract:** Intrinsically measured font-selected MTSDF text with color, size, alignment, deterministic word wrapping, explicit newlines, and line height.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition.
- **Consumers:** Shared line breaking and intrinsic measurement, layout, glyph-atlas lookup, UI paint/vertex conversion.
- **Invalidation:** Text/font/size changes dirty measurement/layout and paint; color/alignment changes dirty paint or placement as applicable.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_text).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`, `project/fonts.odin`; `ui/ui_test.odin`, `ui/ui_retained_test.odin`.

### `scrapbot.ui_button`

- **Contract:** Text and/or reusable SDF-icon activation control consuming generic pointer/focus state, with an optional public popup-root target UUID.
- **Storage/lifecycle:** Dedicated typed UI storage; authored.
- **Producers:** Public project UI surfaces and editor composition, including reflected-container disclosures.
- **Consumers:** Measurement, hit testing, hover/active painting, activation bindings, inspector disclosures, panel title actions, and generic popup toggling.
- **Invalidation:** Content/style changes dirty layout/paint; pointer/keyboard edges target interaction state and activation revision.
- **Surfaces:** Shared public UI contract across projects and editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_button).
- **Source/tests:** `ecs/ui_components.odin`, `ui/ui.odin`; `ui/ui_test.odin`, `ui/diagnostic_driver_test.odin`.

### `scrapbot.ui_input`

- **Contract:** Single-line text/numeric editor with an optional leading/trailing icon, selection, navigation, validation, staged Enter-to-commit numeric typing, cancel-on-focus-transfer, and opt-in live numerical scrubbing. Prefix badges remain outermost; the icon stays fixed while text scrolls inside the remaining clipped content.
- **Storage/lifecycle:** Dedicated typed UI storage plus retained caret/selection/scrub state; authored component.
- **Producers:** Public project UI surfaces, editor reflected-field bindings, keyboard/pointer input.
- **Consumers:** Measurement, icon-resource resolution, focus/navigation order, editing/validation, paint, editor history bindings.
- **Invalidation:** Text/font/icon geometry changes target layout and paint; tint and other visual styles target paint. Numeric keyboard edits change only retained text/validity until submission, while live scrubbing advances change revisions and release advances submission without rebuilding unrelated UI.
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

### `scrapbot.ui_color_picker`

- **Contract:** Direct linear RGBA color editor with a saturation/value pad, hue track, optional alpha track, and optional HDR exposure track. `value` remains the canonical color; `exposure` is picker presentation state.
- **Storage/lifecycle:** Dedicated typed UI storage plus retained active gesture state; authored component.
- **Producers:** Public project UI surfaces, editor semantic Color/resource bindings, pointer interaction, Luau, and native extensions.
- **Consumers:** Retained hit testing, gradient/checker/thumb painting, `ui_state` change/submission revisions, editor preview/history, and scene persistence.
- **Invalidation:** Value/style mutation dirties only the picker paint stream; active drags update the exact component and advance change revisions, release advances submission once, and stable frames reuse unchanged paint/GPU streams.
- **Surfaces:** Shared public UI contract across scene TOML, Luau, native Odin, projects, and the editor; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_color_picker).
- **Source/tests:** `shared/types.odin`, `ecs/ui_components.odin`, `ui/ui.odin`, `ui/editor_reflection.odin`; `ui/ui_test.odin`, `project/project_test.odin`, `render/render_test.odin`.

### `scrapbot.ui_action`

- **Contract:** A non-empty bounded semantic action plus optional bounded payload inherited from the interacted entity through its UI layout ancestors.
- **Storage/lifecycle:** Dedicated typed UI storage; authored. World-owned strings are cloned on attachment and reclaimed on removal, despawn, or world destruction.
- **Producers:** Scene TOML, Luau/native deferred UI mutation, project composition, and editor composition where reusable controls need semantic meaning.
- **Consumers:** UI interaction publishing resolves the nearest ancestor action and copies it into the World-owned immutable event history. Luau, native extensions, and editor orchestration read that history independently.
- **Invalidation:** Adding or changing the component performs no retained hierarchy or paint work. Event strings allocate only when an interaction is published; stable frames do no action lookup or event append.
- **Surfaces:** Shared public UI contract across scene TOML, Luau, native Odin, projects, and editor composition; see the [public component reference](../../docs-website/src/content/docs/reference/components.md#scrapbotui_action).
- **Source/tests:** `shared/types.odin`, `ecs/ui_components.odin`, `ecs/ui_events.odin`, `ui/ui.odin`; `script/ui_components_test.odin`, `native/ui_test.odin`, `ui/ui_test.odin`.

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

### `scrapbot.internal.editor_transform_gizmo`

- **Contract:** Transient editor ownership, mode, space, drag axis, and interaction state attached to the currently manipulable selected entity.
- **Storage/lifecycle:** Dedicated editor-gizmo storage; internal derived component.
- **Producers:** Editor selection and transform-gizmo reconciliation while the shell is visible.
- **Consumers:** Gizmo rendering, picking, drag manipulation, and the generic read-only component inspector.
- **Invalidation:** Selection, editor visibility, and Transform membership add or remove the exact component; interaction changes mutate only its retained slot.
- **Surfaces:** Internal only; rejected from scene, Luau, native extension, and editor authoring surfaces, but runtime type inspection may show its read-only advanced card.
- **Source/tests:** `ecs/editor.odin`, `render/gizmo.odin`, `ui/editor_reflection.odin`; `ecs/editor_test.odin`, `render/gizmo_test.odin`, `ui/ui_test.odin`.
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
- `scrapbot.ui_state`, `scrapbot.internal.render_instance`, and `scrapbot.internal.editor_transform_gizmo` must only be produced by their owning engine systems.

See [ADR-007](../adr/ADR-007-use-id-keyed-component-storage.md), [ADR-024](../adr/ADR-024-update-derived-ecs-state-from-structural-changes.md), and [ADR-025](../adr/ADR-025-use-one-public-ecs-ui-contract.md).
