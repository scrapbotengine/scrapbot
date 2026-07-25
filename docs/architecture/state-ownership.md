# State Ownership and Invalidation

**Last verified:** 2026-07-25

Scrapbot separates authoritative project/runtime state from derived indexes, caches, render data, and editor views. A derived owner must update from explicit lifecycle or revision signals where feasible; stable frames must not rediscover unchanged state.

| State | Owner/source | Authority | Invalidation or lifetime |
| --- | --- | --- | --- |
| Project configuration, scene TOML, resource files, scripts, native source, assets | Project directory | Persistent authored source | Explicit Save/Revert, project load, or hot-reload file stamps. Reload and Revert stage replacement resources and worlds, then commit them together only after validation succeeds. |
| Component definitions and IDs | `component.Registry` | Runtime schema authority | Engine bootstrap plus native/Luau registration; registry revision changes on registration/replacement. |
| Luau/native systems and cached Luau queries | `script.Runtime`, `native.Extension_Set` | Runtime execution registries | Hard-capped heap-backed buffers are allocated during runtime/extension initialization, transferred with successful hot-reload replacement state, and released by their owning destroy procedures. |
| Deferred structural commands | Per-runtime and per-native-worker `ecs.Command_Buffer` | Ordered pending lifecycle mutations | Compact headers reference separate typed payload arrays. Spawn/add side arrays contain only present components, and schema component headers reference only supplied Number/Vec2/Vec3/Vec4 fields. Arrays grow geometrically, merge with payload/range remapping in schedule order, clear without releasing capacity each frame, and release at runtime/cache destruction. |
| Compiled native chunk plans | Each `native.Native_System` | Derived query/storage/field resolution | Bounded cache keyed by chunk terms and bindings; invalidated by World UUID, component-registry revision, newly appearing storage families, or extension-set replacement. Ordinary component membership churn retains the plan. |
| Entity identity and component values | `shared.World` / `ecs` | Active runtime authority | Typed ECS mutation, deferred command application, playback restore, or world replacement. |
| Frame time | `world.time` | Current runtime resource | Advanced once per permitted simulation step. |
| Geometry/material/environment descriptions and handles | `resources.Registry` | Runtime shared-resource authority | Generational handles plus content/topology versions. See [Resource render state](#resource-render-state). |
| Texture/Model imported products | `asset_import` products plus `resources.Registry` | Derived from authored UUID recipes and asset/dependency contents | Ensured at import/check/build/run or asset hot reload; schema/content fingerprints reuse unchanged products, atomic writes preserve last-good files, and model-root revisions reconcile derived ECS children at bootstrap/reload or an explicit structural edit. |
| Authoring history and dirty UUID candidates | Editor UI state | In-memory authoring authority until Save/Revert | One transaction per completed gesture or structural operation; playback mutations remain disposable. |
| Retained UI hierarchy, layout, interaction, and paint commands | `ui.State` | Derived from public UI ECS components | Structural dirty queue plus independent project/editor layout and paint revisions. |
| `scrapbot.ui_state` components | UI reconciler | Derived, renderer-owned | Targeted interaction-dirty queue and retained node state; project code reads only. |
| Render-instance membership and retained render list | ECS render extraction | Derived from Transform/geometry/material/shadow membership and resource resolution | Structural/static dirty queue, separate exact Transform queue, and resource revisions. Static extraction supersedes a same-frame Transform entry. Entity and slot reverse indexes are bidirectional ownership maps: delayed removal of a stale owner must never erase a newly reused slot's mapping. Batch appearance/disappearance advances topology exactly at the membership boundary. |
| GPU instances, draw/visibility data, lights, shadows, postprocess targets, pipelines, and resource caches | WGPU backend | Derived backend state | Exact dirty queues, resource versions, camera/viewport revisions, target shape, capacity growth, world replacement, or backend lifetime. Windowed runs add an SDL-backed surface; headless runs own only an offscreen color target and allocate readback storage on explicit capture. See [WGPU derived state](#wgpu-derived-state). |
| Active-camera render policy | Authored `scrapbot.camera`; consumed by WGPU | Authoritative ECS value with derived backend target/execution/history/exposure state | World render scale, fixed/automatic exposure, TAA, current-frame fast AA, AO plus its bounded sample-quality tier, SSR, and bloom are per-camera policy. The editor fly camera contributes pose/lens but inherits the active project camera's policy. Render scale selects a retained world/depth/post grid while final composition and UI use the native output grid. A scale change replaces only size-dependent targets and rejects history; stable scale reuses them. Automatic exposure owns one persistent GPU scalar and performs no CPU readback; disabling it restores scalar `1` once. TAA-mode changes reject history; disabled TAA omits jitter and history sampling, while disabled automatic exposure/AO/SSR/bloom omit their compute dispatches. AO quality updates one uniform and bounded shader loop, without target recreation. Retained postprocess targets stay allocated across feature toggles to avoid allocation churn. |
| Global volumetric medium | Authored singleton `scrapbot.volumetric_fog`; consumed by WGPU | Authoritative generic ECS payload plus renderer-owned half-resolution scattering/transmittance target | Membership/value changes follow ordinary custom-component lifecycle and revisions. Postprocessing visits only the named storage's compact active set and copies the selected payload into the retained temporal uniform. Nonzero density dispatches the half-resolution ray march; zero density skips it. Target size follows explicit post-target invalidation, not ordinary stable frames. |
| Project/editor/overlay UI vertex buffers | WGPU backend | Derived from UI output streams | Independent monotonic stream revisions; stable streams retain CPU/GPU buffers. Target size or editor viewport changes invalidate the project stream key. Project commands use one uniform canvas scale plus viewport translation and clipping; pointer input and diagnostics invert the same transform. |
| Embedded UI viewport membership and targets | `ui.State` / WGPU backend | Derived from authored `scrapbot.ui_viewport`, layout, and resource/World state | Structural UI dirtiness maintains compact viewport-node membership. Layout refreshes only bounded visible surfaces. WGPU reuses eight independently sized target slots, quantized from 64–1024 pixels per axis. Static Texture/Model/Material preview scenes cache by component, target shape, exact resource version, and relevant registry revisions; World targets consume the retained render list. |
| System profiler snapshot | Root runtime | Derived diagnostic state | Samples every frame, rolls over 50 frames, publishes every five frames. |
| Performance diagnostics snapshot | Renderer/root runtime | Derived diagnostic state | Wall-clock frame-interval and active-CPU duration samples roll independently over 50 frames; renderer and mutation-maintained world counters publish every five frames under one revision. |
| Bounded render profile | CLI-owned `Profile_Collector`, populated by renderer/WGPU | Ephemeral diagnostic artifact | Explicit `scrapbot profile` lifetime only. Preallocated measured rows receive active CPU, frame-local counter, and structured pass-workload data directly and delayed GPU timing by originating frame index. Profile-only feature overrides resolve a temporary camera/fog policy after ECS extraction without mutating authored data. Finalization derives summaries; destruction releases rows and adapter metadata. Ordinary runs have no collector and perform no profile work. |
| Live entity origin counters | ECS world | Derived from entity lifecycle | Incremented on spawn and decremented on despawn; diagnostics read them without scanning entity capacity. |
| Editor browsers and inspector snapshots | Editor UI composition over component registry and canonical payloads | Derived tooling view | The entity browser contains authored entities plus an explicitly selected runtime entity. Component cards and rows are runtime type-inspected with no per-component panel catalog. Selection or explicit structural invalidation rebuilds them; the 5 Hz running-value cadence refreshes values without rematerializing browser rows. Stopped values remain change-driven, focused inputs retain staged text, and active scrubs defer unrelated refresh. |
| Generated Luau declarations and native build products | `.scrapbot/` and build directories | Derived products | Regenerated from schemas/source and never hand-edited as authority. |

## Resource render state

Project resource load, editing, and hot reload update the registry. Material descriptions own cloned factors and image payloads. Environment descriptions own a cloned source panorama plus irradiance and specular cubes.

Render state resolves independent lighting and optional-background handles/settings. One monotonic environment revision invalidates the global WGPU binding only when selection, settings, or content changes.

Active-camera exposure is a separate compact input. Fixed exposure rewrites the environment uniform without rebuilding textures. Automatic exposure keeps that uniform neutral, meters only the active viewport after temporal resolve, and stores its adapted scalar in a backend-owned GPU buffer shared by bloom and composite.

Procedural solar elevation derives day/night presentation and fill in shaders. Above the horizon it also produces an ephemeral first directional-light input; it does not create an authored entity or component.

## WGPU derived state

### Instances and draws

Transform-only slots pack one dense 64-byte update with a destination slot. One upload feeds a dirty-only compute pass that expands matrices and bounds before culling.

If lifecycle churn exposes a retained render slot whose GPU slot is inactive, only that slot receives static reconciliation before its Transform update. Missing resources or batches remain errors. World replacement clears all retained GPU slots, including capacity beyond a smaller replacement world.

Static instance fields remain separately retained. Batch topology, geometry capacity, and exact structural changes drive their updates.

### Resource caches

Resource caches replace stale generations by stable handle index. A material entry owns its generated textures/views, factor uniform, and bind group as one lifetime. Borrowed first-class Texture entries remain separately owned.

Batch bind groups are released before cache storage is cleared. Exact lighting/background handle or content-version changes rebuild only the shared environment binding. The sky camera/projection uniform uploads only after an exact value change.

### Lights, shadows, and visibility

Changed point lights upload into geometrically growing storage. Camera, viewport, light, or capacity changes trigger deterministic cluster reconstruction. Every cluster can reference the complete retained light list.

Fragment lookup includes the rendered viewport origin and extent, so editor chrome cannot offset cluster selection. Four camera-relative shadow matrices own independent visibility slices and texture-array layers.

Frustum and LOD work uses the unjittered camera. TAA's eight projection samples remain within a quarter pixel. Retained history lives on the stable output grid, so reprojection uses unjittered current/previous camera matrices and removes the current sample offset before sampling history. A matching depth is selected from the local 2×2 history footprint, while YCoCg variance clipping limits stale color. Retained Hi-Z depth tracks the exact jittered projection that produced it and expands projected bounds by one pixel to remain conservative across TAA samples.

### Postprocessing

Surface data, indirect diffuse, and reflection output are current-frame derived targets. Visibility-bitmask AO consumes depth plus mapped normals and attenuates only indirect diffuse. SSR consumes surface data and HDR color. AO and SSR quality tiers update only their next uniform and bounded shader loop; retained target allocation and bind groups remain unchanged.

The active camera's render scale sizes the world, depth, Hi-Z, surface, temporal, AO, reflection, fog, bloom, and exposure inputs. At scale `1`, WGPU borrows the native output depth target. Lower scales lazily own one matching depth target. Final composition stretches the complete scaled grid into the native output target, preserving editor-viewport coordinates; project UI, gizmos, and editor chrome are then painted at native resolution.

Global fog is integrated into the temporal resolve with 16 low-discrepancy sub-step samples rotated across the eight-frame temporal sequence. It reconstructs each ray from depth, evaluates exponential world-height density, and samples the first directional light's cascaded shadows with a 2×2 UV-space filter and adjacent-cascade cross-fades.

Opt-in point-light scattering reads the existing GPU cluster table at each midpoint and evaluates every relevant local light. Fog owns no duplicate light list, history, or intermediate target; TAA stabilizes its composed result when enabled.

Temporal color and depth use two retained texture pairs. Each frame resolves into one pair while sampling the other, then swaps their roles without a full-resolution GPU copy. The resolve's exact 3×3 current-color neighborhood lives only in a dispatch-local 10×10 workgroup tile; it adds no retained owner or invalidation path. Automatic exposure, bloom, and composite select the current output through prebuilt bind groups. Resize, depth-view replacement, world replacement, and detected camera cuts reject history.

Half-resolution AO targets and their depth/surface bindings retain a stable output shape. They rebuild only when output dimensions or the sampled depth view change.

## Stable-frame invariant

An ordinary unchanged frame must not:

- scan complete entity/component storage to rediscover membership;
- rebuild an unchanged retained hierarchy, render list, draw database, or UI paint stream;
- hash complete output merely to learn that it did not change;
- regenerate unchanged CPU/GPU vertices or instance records;
- upload unchanged buffers.

Ordinary Transform value writes enqueue only the exact Transform queue. Component membership, resource binding, shadows, and render eligibility use the structural/static queue; that queue supersedes redundant same-frame Transform work. Runtime slot and scene-order allocation are monotonic or free-list based and must not scan historical entity capacity per spawn.

Accept full bootstrap/rebuild work at explicit boundaries such as initial world construction, world replacement, resource topology changes, or geometrically growing backend storage. Document any new stable-frame exception in the relevant ADR/FDR and protect it with deterministic work counters rather than wall-clock thresholds.

See [ADR-024](../adr/ADR-024-update-derived-ecs-state-from-structural-changes.md), [ADR-030](../adr/ADR-030-identify-project-resources-by-uuid-outside-the-ecs.md), and [ADR-034](../adr/ADR-034-keep-gpu-visibility-backend-owned.md).
