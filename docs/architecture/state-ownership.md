# State Ownership and Invalidation

**Last verified:** 2026-08-05

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
| Geometry/material/environment/icon-set descriptions and handles | `resources.Registry` | Runtime shared-resource authority | Generational handles plus content/topology versions. Geometry content includes LOD metadata, source- or exact-leaf-derived meshlets, a crack-aware cluster hierarchy with monotonic group errors, and a file-or-memory page source. Imported Geometry retains canonical counts and a position-only query proxy instead of complete CPU render vertices/source indices. Those structures rebuild only with that exact Geometry version, never on stable frames. See [Resource render state](#resource-render-state). |
| Texture/Model/Environment/Icon Set imported products | `asset_import` products plus `resources.Registry` | Derived from authored UUID recipes and asset/dependency contents | Ensured at import/check/build/run or asset hot reload; schema/content/settings fingerprints reuse unchanged products and atomic writes preserve last-good files. The common product envelope validates kind and chunk ranges before type-specific decoding. Model LOD simplification and compaction run only on invalidation. Model v17 reads its bounded catalog, fetches images from the image chunk, pins the complete terminal refinement-DAG frontier, and retains other detail-page ranges without decoding render payloads. Generated semantic handles update at registration, while model-root revisions reconcile derived ECS children at bootstrap/reload or an explicit structural edit. |
| Authoring history and dirty UUID candidates | Editor UI state | In-memory authoring authority until Save/Revert | One transaction per completed gesture or structural operation; playback mutations remain disposable. |
| UI theme palettes, metrics, typography, and named recipes | Shared UI composition contract plus UUID-backed `resources.Registry.ui_themes` | Ephemeral composition input with versioned lookup, not retained UI authority | Scene parsing, Luau resolution, UUID-specific native host resolution, and editor composition consume the same engine-owned recipe vocabulary before typed ECS attachment or update. The resolved `ui_*` values are authoritative for layout and paint; the registry revision refreshes resource inspection only. No theme identity, ancestry cascade, stable-frame traversal, or renderer-side style store remains. |
| Retained UI hierarchy, authored canvas transform, intrinsic text lines, flex lines, popup rectangles, dock tabs, panel/split/control gestures, layout, interaction, and paint commands | `ui.State` | Derived from public UI ECS components and active font metrics | Structural dirty queue plus independent project/editor layout and paint revisions. Intrinsic measurement, bounded basis/grow/shrink line packing, and direct-child dock-tab/stack-order resolution run only for an invalidated domain; the exact text breaks feed paint. The optional root `ui_canvas` slot is cached per origin; its revision resolves the logical viewport, output scale/alignment, and safe area once for all downstream consumers. Popup placement derives from the live anchor/viewport only after affected ECS open, anchor, or constraint changes. Dock transfers update authoritative item parent/active UUID; edge drops create authoritative public stack/dock topology and preserve the replaced sibling order; panel drops update authoritative parent/stack order. All reuse ordinary invalidation, and stable frames retain bounded gesture state without a World scan. |
| Immutable UI event history | `shared.World.ui_events` | Derived ordered interaction history | The UI interaction pass appends only actual edges to a 256-entry ring with monotonic sequences. Luau, native extensions, and editor orchestration retain independent cursors. Overflow is explicit; world replacement resets the sequence space and destruction reclaims copied action strings. |
| `scrapbot.ui_state` components | UI reconciler | Derived, renderer-owned | Targeted interaction-dirty queue and retained node state; project code reads only. |
| Render-instance membership and retained render list | ECS render extraction | Derived from Transform/geometry/material/shadow membership and resource resolution | Structural/static dirty queue, separate exact Transform queue, and resource revisions. Static extraction supersedes a same-frame Transform entry. Entity and slot reverse indexes are bidirectional ownership maps: delayed removal of a stale owner must never erase a newly reused slot's mapping. Batch appearance/disappearance advances topology exactly at the membership boundary. |
| GPU instances, whole-primitive and meshlet draw/visibility data, lights, shadows, postprocess targets, pipelines, and resource caches | WGPU backend | Derived backend state | Exact dirty queues, resource versions, camera/viewport revisions, target shape, capacity or meshlet-policy threshold changes, world replacement, or backend lifetime. Meshlet index/metadata/template state follows Geometry versions and retained batch capacity; each batch retains its classic/meshlet selection, while current-frame counts reset from templates. Windowed runs add an SDL-backed surface; headless runs own only an offscreen color target and allocate readback storage on explicit capture. See [WGPU derived state](#wgpu-derived-state). |
| Active-camera render policy | Authored `scrapbot.camera`; consumed by WGPU | Authoritative ECS bounds with derived world-scale, shadow-tier, post-quality, target/execution/history, and exposure state | One controller consumes completed asynchronous scene spans exactly once and advances one deterministic reversible quality step. Samples carry one generation; any output/policy change or different stable project-camera UUID resets evidence and rejects delayed results. Missing timestamp support selects authored maxima. The editor fly camera contributes pose/lens but retains the project camera as policy owner. Effective scale selects retained world/depth/post targets; shadow resolution selects an active viewport inside fixed capacity; post quality bounds AO/SSR loops and fog steps. Scale changes replace only size-dependent targets and reject temporal history. Stable outputs allocate nothing. Automatic exposure owns one persistent GPU scalar and performs no CPU readback. Disabled TAA or post features omit their history or dispatch work. Retained targets stay allocated across feature toggles. See ADR-052. |
| Adaptive directional-shadow resolution | Unified active-camera frame-budget policy; owned by WGPU | Derived quantized raster size over retained maximum-capacity layers | The shared ladder may select 2048, 1024, or 512 pixels within the authored adaptive-quality floor. A tier change shares the controller generation and cooldown. Owner changes or disabled adaptation restore 2048. Stable frames keep the same texture, views, and bind groups; viewport/scissor, cascade texel stabilization, PCF coordinates, and virtual-shadow hierarchy thresholds consume the active size. |
| Global volumetric medium | Authored singleton `scrapbot.volumetric_fog`; consumed by WGPU | Authoritative generic ECS payload plus renderer-owned half-resolution scattering/transmittance target | Membership/value changes follow ordinary custom-component lifecycle and revisions. Postprocessing visits only the named storage's compact active set and copies the selected payload into the retained temporal uniform. Nonzero density dispatches the half-resolution ray march; zero density skips it. Target size follows explicit post-target invalidation, not ordinary stable frames. |
| Composable presentation effects | Authored singleton `scrapbot.vignette`, `scrapbot.lens_flare`, and `scrapbot.lens_dirt`; consumed by WGPU | Three independent authoritative generic ECS payloads plus one renderer-owned uniform buffer | Membership/value changes follow ordinary custom-component lifecycle and revisions. Postprocessing visits only each named storage's compact active set and clamps the selected payloads. It uploads the fixed-size uniform only when those effective values, adaptive quality, bloom state, or debug suppression change. Stable frames allocate, rebuild, and upload nothing. Absent/zero effects take early shader branches. |
| Project/editor/overlay UI vertex buffers | WGPU backend | Derived from UI output streams | Independent monotonic stream revisions; stable streams retain CPU/GPU buffers. Target size, editor viewport, or authored canvas changes invalidate the project stream key. Project commands use the canvas's vector scale plus viewport translation and clipping; pointer input and diagnostics invert the same transform. The compositor paints project UI, viewport-clipped editor-world overlays, then editor chrome so docked tabs and panels occlude scene tools. |
| Embedded UI viewport membership and targets | `ui.State` / WGPU backend | Derived from authored `scrapbot.ui_viewport`, layout, and resource/World state | Structural UI dirtiness maintains compact viewport-node membership. Layout refreshes only bounded visible surfaces. WGPU reuses eight independently sized target slots, quantized from 64–1024 pixels per axis. Static Texture/Model/Material preview scenes cache by component, target shape, exact resource version, and relevant registry revisions; World targets consume the retained render list. |
| System profiler snapshot | Root runtime | Derived diagnostic state | Samples every frame, rolls over 50 frames, publishes every five frames. |
| Performance diagnostics snapshot | Renderer/root runtime | Derived diagnostic state | Wall-clock frame-interval and active-CPU duration samples roll independently over 50 frames. Retained topology, asynchronous camera-visible batch and nonempty-meshlet-draw counts, visibility and retained-slice overflow counters, one full ordered pass-boundary span, one pre-UI scene span, per-pass attribution, and mutation-maintained world counters publish every five frames under one revision. |
| Bounded render profile | CLI-owned `Profile_Collector`, populated by renderer/WGPU | Ephemeral diagnostic artifact | Explicit `scrapbot profile` lifetime only. Preallocated measured rows receive active CPU, frame-local counter, and structured pass-workload data directly and delayed full-frame, scene, and per-pass GPU timing by originating frame index. Profile-only feature overrides resolve a temporary camera/fog policy after ECS extraction without mutating authored data. Finalization derives summaries; destruction releases rows and adapter metadata. Ordinary runs have no collector and perform no profile work. |
| Live debug snapshot, capture job, and artifact plan | Root-owned `live_debug.Service`; renderer-owned provider resources | Immutable derived diagnostics plus one bounded pending command | Windowed editor lifetime or explicit `--live-debug` opt-in. The engine thread replaces one owned snapshot and consumes at most one 1–16-frame capture. WGPU allocates, encodes, maps, and releases requested color readbacks inside that frame; null supports telemetry only. A loopback HTTP worker only authenticates, encodes, serves completed files, and updates mutex-protected request state; it never reads ECS, registry, renderer, or GPU owners directly. Stable frames perform one bounded snapshot copy only while enabled and no artifact work. Shutdown removes discovery and releases captured strings. See ADR-053. |
| Live entity origin counters | ECS world | Derived from entity lifecycle | Incremented on spawn and decremented on despawn; diagnostics read them without scanning entity capacity. |
| Editor browsers, inspector snapshots, reflected-container expansion, and UUID-picker candidate rows | Editor UI composition over component registry and canonical payloads | Derived tooling view | The entity browser contains authored entities plus an explicitly selected runtime entity. Component cards and rows are runtime type-inspected with no per-component panel catalog. Selection or explicit structural invalidation rebuilds them; the 5 Hz running-value cadence refreshes values without rematerializing browser rows. Nested records and fixed arrays retain bounded reflection paths on pooled public disclosure/leaf controls; collapsed containers do not recurse or materialize descendants. The entity-reference popup enumerates and validates scene candidates only when opened, retains a missing/current reference for repair, and delegates filtering/virtualization to public UI components. Stable closed frames do no candidate work. Stopped values remain change-driven, focused inputs retain staged text, and active scrubs defer unrelated refresh. |
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

Adapters with indirect-first-instance additionally retain meshlet metadata, expanded index ranges,
camera/shadow visibility slices, a parallel debug-identity stream, and indirect templates.
Classic per-batch slices retain 256-byte dynamic-storage alignment. Meshlet and hierarchy-cluster
slices share one storage binding and allocate exact `cluster count × max(instance count, 1)`
cardinality, without multiplying every cluster by the classic alignment.
Native multi-draw adapters address those templates directly. Other capable adapters retain a
bounded camera stream of compact `{instance slot, cluster index}` records plus one non-indexed
indirect command per compatible material span. Their vertex shaders pull cluster indices and
packed attributes from the shared geometry arenas. A separate indexed shadow template lets those
adapters reuse the GPU-selected object LOD in four conservative cascade lists. Geometry versions
define command topology. Batch membership capacity defines visibility allocation.

Hierarchy-bearing batches always use cluster submission on indirect-first-instance adapters because
they select geometric detail even for one instance. Ordinary meshlet batches retain the two-instance
amortization threshold. Membership crossing that threshold invalidates only the retained batch
layout. Meshlet-oriented debug views transiently force remaining eligible batches through the
detailed path without rewriting topology.

WGPU queries the device's storage-buffer binding limit during initialization. Retained cluster
metadata grows geometrically until another power of two would cross that limit, then uses the
largest legal record capacity. A live topology that fits therefore remains eligible even when its
geometric spare capacity would not; a topology whose live records do not fit retains the existing
whole-primitive fallback.

The compute culler projects monotonic hierarchy-group errors into pixels. It selects one complete
camera frontier outside a narrow 98%-to-102% overlap around a fixed one-pixel target and adjacent
levels inside it. Both complete opaque levels depth-test normally within the overlap. Shadow
selection uses the same hierarchy with cascade-scaled error thresholds, preserving near detail
while bounding distant-cascade work.

Stable frames copy separate active camera and shadow templates, run object-first compute culling,
and submit matching command ranges. Portable compact submission first appends bounded batch-local
instance candidates. Parallel camera and shadow dispatches then assign one hierarchy cluster to
each invocation instead of making one instance invocation loop the complete hierarchy. Separate
candidate, camera, and shadow bind groups reuse the baseline eight-storage-buffer layout.

Mixed frames encode classic, native-cluster, and portable compact work in the same visibility pass.
Stable frames do not rescan resources, rebuild cluster metadata, upload debug identities, or
regenerate compact records on the CPU. Adapters without indirect-first-instance and layouts above
the bounded visibility capacity use the retained whole-primitive database. Streamed virtual
Geometry has no complete canonical allocation, so its classic command references the immutable
indexed proxy assembled from pinned coarse pages. Capacity pressure therefore lowers detail
without producing an empty world or depth draw.

The retained batch count follows topology invalidation. Camera-visible batches, nonempty meshlet
draws, selected virtual clusters, and hierarchy-threshold rejections are frame-valued GPU counters.
The first surviving object atomically sets its selected batch's bit. The first surviving instance
for a cluster command advances that indirect count from zero. CPU-reference culling derives visible
batches from existing per-batch counts and reports no virtual-cluster selection.

### Resource caches

Resource caches replace stale generations by stable handle index. A material entry owns its generated textures/views, factor uniform, and bind group as one lifetime. Borrowed first-class Texture entries remain separately owned.

Geometry cache entries own aligned ranges rather than GPU buffers. One WGPU vertex arena and one
index arena own the backing buffers, aligned first-fit free lists, high-water marks, and cumulative
mutation counters. Exact version hits do no allocator or upload work. Replacement commits new
ranges only after all uploads succeed; stale handles are reclaimed when the registry's geometry
topology revision changes. Growth is geometric and copies retained bytes before replacing the
backing buffer. Vertex-pulling bind groups advertise no more than the device's maximum storage
binding range even when the shared vertex/index buffers have grown beyond it. Stable frames never
scan, compact, hash, or upload the arenas.

Hierarchy metadata and each Geometry's file-or-memory page source are resource-owned. WGPU owns
canonical fast-path or page-local vertex/index arena ranges, residency, visible-use age, pending
immutable product-range reads, and the configured combined payload budget. Coarsest streamed pages
are pinned.

Imported Geometry query positions and exact leaf topology remain resource-owned. Picking borrows
them without allocation. A WGPU cache miss may request an owned canonical view reconstructed from
leaf-containing product pages; the cache upload consumes and releases it in the same call. Stable
cache hits neither reconstruct nor read CPU geometry. Memory-backed procedural/runtime Geometry
instead lends its resident canonical arrays.

GPU demand requests, future-camera prefetch requests, and cadence-sampled visible-use touches arrive
through separate bounded lanes in the asynchronous visibility ring. WGPU owns smoothed camera-motion
history; cuts, world changes, missing history, and stable cameras disable prediction. Feedback schedules
file-backed refinement on one renderer-owned I/O worker; handle/generation/version-tagged
completions are discarded when stale. Demand-first, group-atomic admission uses one ordered eviction
plan per feedback batch, protects stronger recent demand, and never lets speculative prefetch evict
demand residency. Geometry cache groups distinguish memory residency from drawable activation.
Newly complete groups pass a bounded demand-aware settling window and wait for direct-parent
transitions to settle, then enter a 16-frame admission handoff. The GPU combines that temporal
progress with its steady projected-error overlap and depth-tests complete child/parent surfaces in
world and depth passes. Native cluster shadows select their hierarchy directly; streamed portable
shadows use a pinned-root indexed proxy. The internal HDR alpha channel carries a
transition reactive marker, and temporal history encodes that marker alongside the existing
bloom-enable bit. The temporal resolver owns its depth-tolerance adjustment. Completion is the
point at which the child becomes the logical refinement. Active
refinements retain their direct coarse parents until release.

Residency owns which complete groups fit in the payload budget, not geometric quality. Pressure may
defer refinement or evict lower-priority detail, but it cannot raise the camera error target. The
coordinated render-quality controller owns render scale; the resulting physical viewport height is
an explicit input to projected-error selection.

WGPU owns a compact active-transition queue. It advances only those groups and patches their
persistent group-to-cluster and refinement-to-parent dependents at transition boundaries. Stable
frames do no page scan, file read, geometry upload, complete transition scan, or residency-table
rebuild.

Batch bind groups are released before cache storage is cleared. Exact lighting/background handle or content-version changes rebuild only the shared environment binding. The sky camera/projection uniform uploads only after an exact value change.

### Lights, shadows, and visibility

Changed point lights upload into geometrically growing storage. Camera, viewport, light, or capacity changes trigger deterministic cluster reconstruction. Every cluster can reference the complete retained light list.

Fragment lookup includes the rendered viewport origin and extent, so editor chrome cannot offset cluster selection. Four camera-relative shadow matrices own independent visibility slices and texture-array layers.

The layers retain 2048² capacity. A quantized active viewport bounds raster work without reallocating bindings. Cascade stabilization, receiver bias, PCF atlas remapping, and shadow hierarchy detail all use the same active resolution.

Frustum and LOD work uses the unjittered camera. TAA's eight projection samples remain within a quarter pixel. Retained history lives on the stable output grid, so reprojection uses unjittered current/previous camera matrices and removes the current sample offset before sampling history. A matching depth is selected from the local 2×2 history footprint, while YCoCg variance clipping limits stale color. Retained Hi-Z depth tracks the exact jittered projection that produced it and expands projected bounds by one pixel to remain conservative across TAA samples.

### Postprocessing

Surface data, indirect diffuse, and reflection output are current-frame derived targets. Visibility-bitmask AO consumes depth plus mapped normals and attenuates only indirect diffuse. SSR consumes surface data and HDR color. AO and SSR quality tiers update only their next uniform and bounded shader loop; retained target allocation and bind groups remain unchanged.

The extracted camera's debug view, Hi-Z mip, and occlusion-evidence freeze flag are authoritative for a rendered view. While the editor is visible, optional transient Game controls replace them only on the retained render-list camera copy.

Non-lit output updates compact render/cull uniforms, skips temporal and presentation effects, and reuses existing targets. Hi-Z inspection reads the current retained pyramid after construction and adds no copy, readback, or pyramid rebuild.

Meshlet identity storage follows topology/capacity invalidation rather than frames. Its visible-instance allocation reserves an aligned diagnostic tail.

Meshlet Visibility writes rejected bounds there during the frame-valued cull. Occlusion Queries instead writes every performed query's projected rectangle, mip, compared depths, identity, and decision. Both copy the counter into an indirect line draw and publish it asynchronously.

While query freeze is active, the renderer leaves the latest valid tail and indirect count untouched. Current visibility, depth, and Hi-Z ownership remain frame-valued; freeze does not authorize stale depth reuse for culling. Leaving the view clears the diagnostic-valid flag and retained published count.

### Project spectral surfaces

The Shader resource owns spectral parameters and versioning. Its WGPU cache owns the
frequency-domain intermediate buffer, raw spatial displacement buffer, finalized
displacement/normal/crest field, uniform, bind groups, and pipeline association.

Simulation time is frame-valued. Each active spectral Shader updates its uniform and encodes one
horizontal plus one vertical inverse FFT followed by one spatial finalization dispatch at most once
per frame, even when several transparent draws share it. Finalization derives the compression
Jacobian used for crest foam. Inactive and non-spectral Shaders encode no spectral work and bind the
renderer's shared zero field.

Changing the Shader version releases only that Shader's spectral state and render pipeline. Resizing the scene target rebuilds only per-Shader scene/depth bind groups; the spectral field survives.

Virtual Geometry caches additionally own any root-page shadow-proxy index range. The proxy aliases
the already-pinned page-vertex allocation, is rebuilt only with that Geometry version, and is
released with the cache. It does not create another vertex authority or stable-frame upload.

The active camera's effective render scale sizes the world, depth, Hi-Z, surface, temporal, AO, reflection, fog, bloom, and exposure inputs. At scale `1`, WGPU borrows the native output depth target. Lower scales lazily own one matching depth target. Final composition stretches the complete scaled grid into the native output target, preserving editor-viewport coordinates. Project UI, editor-world overlays clipped to the Game viewport, and editor chrome are then painted at native resolution in that order.

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
