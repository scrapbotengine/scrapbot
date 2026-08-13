# State Ownership and Invalidation

**Last verified:** 2026-08-13

## Scene resource residency

| State | Authority | Derived consumers | Invalidation and stable-frame rule |
| --- | --- | --- | --- |
| Scene resource closure | Parsed scene plus project resource declarations | Runtime startup and transition staging | Recomputed only during project/scene discovery or hot reload; dependency-first and deduplicated |
| Active/staging residency references | Root runtime `Resource_Residency` | Registry admission and delayed eviction | Changes only at startup, transition staging/cancel/activation, or hot reload |
| Pending resource evictions | `Resource_Residency.evictions` | Per-frame retirement tick | Stable frames visit only pending entries; no project declaration or registry-capacity scan |
| Resident payload | `resources.Registry` entry | ECS handle resolution and backend caches | Admission/reimport replaces exact entries; retirement frees owned slices and advances generations/revisions |

Scrapbot separates authoritative project/runtime state from derived indexes, caches, render data, and editor views. A derived owner must update from explicit lifecycle or revision signals where feasible; stable frames must not rediscover unchanged state.

| State | Owner/source | Authority | Invalidation or lifetime |
| --- | --- | --- | --- |
| Project configuration, scene TOML, resource files, scripts, native source, assets | Project directory | Persistent authored source | Explicit Save/Revert, project load, or hot-reload file stamps. Reload and Revert stage replacement resources and worlds, then commit them together only after validation succeeds. |
| Scene catalog, active scene, and pending scene request | Root runtime or `Hot_Reload_State`; pending UUID originates in `script.Runtime` | Compact project scene metadata plus one active source identity | Recursive discovery at project load/reload rejects zero or duplicate UUIDs. Luau retains only the last pending UUID. The frame boundary consumes it after deferred commands, stages at most one candidate World, commits it atomically, then releases the old World. Failed staging retains active identity and ownership. |
| Component definitions and IDs | `component.Registry` | Runtime schema authority | Engine bootstrap plus native/Luau registration; registry revision changes on registration/replacement. |
| Luau/native systems and cached Luau queries | `script.Runtime`, `native.Extension_Set` | Runtime execution registries | Hard-capped heap-backed buffers are allocated during runtime/extension initialization, transferred with successful hot-reload replacement state, and released by their owning destroy procedures. |
| Deferred structural commands | Per-runtime and per-native-worker `ecs.Command_Buffer` | Ordered pending lifecycle mutations | Compact headers reference separate typed payload arrays. Spawn/add side arrays contain only present components, and schema component headers reference only supplied Number/Vec2/Vec3/Vec4 fields. Arrays grow geometrically, merge with payload/range remapping in schedule order, clear without releasing capacity each frame, and release at runtime/cache destruction. |
| Compiled native chunk plans | Each `native.Native_System` | Derived query/storage/field resolution | Bounded cache keyed by chunk terms and bindings; invalidated by World UUID, component-registry revision, newly appearing storage families, or extension-set replacement. Ordinary component membership churn retains the plan. |
| Entity identity and component values | `shared.World` / `ecs` | Active runtime authority | Typed ECS mutation, deferred command application, playback restore, or world replacement. |
| Engine time | `render.Run_Config.engine_time` | Run-global monotonic presentation clock outside ECS | Advances from every rendered frame delta regardless of project Pause; editor and engine presentation consume it, while project APIs do not. |
| Physical input frame and editor actions | Engine-owned ECS input singletons plus transient UI action adapter | Per-frame physical authority plus derived editor meaning | SDL commits held/pressed/released keyboard and pointer state once before systems. Luau, native systems, UI, and editor camera consume that snapshot. Focused text composition/repeat remains a UI-only side channel. The UI adapter resolves distinct Play, Pause, Stop, and Step actions—including F5–F8 aliases—with command-modified precedence; retained controls and modal tools then apply availability, capture, and propagation ownership. |
| Project clocks | Authored `scrapbot.clock` components plus `world.time` default snapshot | ECS project-time authority with one ABI-compatible selected snapshot | Every active non-editor clock advances from permitted simulation steps at its non-negative speed. Lowest stable scene order selects the system/shader default; Paused and Stopped redraws do no clock work. |
| Geometry/material/environment/icon-set descriptions and handles | `resources.Registry` | Runtime shared-resource authority | Generational handles plus content/topology versions. Geometry content includes LOD metadata, source- or exact-leaf-derived meshlets, a crack-aware cluster hierarchy with monotonic group errors, and a file-or-memory page source. Imported Geometry retains canonical counts and a position-only query proxy instead of complete CPU render vertices/source indices. Those structures rebuild only with that exact Geometry version, never on stable frames. See [Resource render state](#resource-render-state). |
| Texture/Model/Environment/Icon Set imported products | `asset_import` products plus `resources.Registry` | Derived from authored UUID recipes and asset/dependency contents | Ensured at import/check/build/run or asset hot reload; schema/content/settings fingerprints reuse unchanged products and atomic writes preserve last-good files. The common product envelope validates kind and chunk ranges before type-specific decoding. Model LOD, hierarchy, distance-field compilation, and shared `KHR_texture_transform` UV baking run only on invalidation. Model v21 reads its bounded catalog, fetches images from the image chunk, pins the complete terminal refinement-DAG frontier, eagerly exposes the evictable bootstrap tail, retains other detail-page ranges, and retains quantized distance-field descriptors without decoding either bulk payload. Generated semantic handles update at registration, while model-root revisions reconcile derived ECS children at bootstrap/reload or an explicit structural edit. |
| Authoring history and dirty UUID candidates | Editor UI state | In-memory authoring authority until Save/Revert | One transaction per completed gesture or structural operation. Structural batches own ordered entity snapshots, scene order, and before/after selection so subtree Duplicate/Delete apply atomically; playback mutations remain disposable. |
| Editor shell transport and workspace visibility | Editor UI state | Transient per-run tool state | Opening the shell pauses active playback and closing resumes it. Command-modified sidebar toggles flip retained left/right visibility booleans; a visual-state comparison mutates only the affected public dock-space layout, so stable frames perform no repeated workspace mutation. Playback-state changes update the retained viewport badge, frame, and status text. |
| Editor scene-camera pose, lens, orbit point, and focus request | Transient editor-camera ECS entity plus editor UI state | Per-run tool state with one-shot derived framing input | Captured fly/orbit movement and viewport-owned wheel input mutate only the editor camera. Camera motion comes exclusively from consecutive absolute positions in the canonical frame-local physical-input snapshot; it never enters SDL relative-mouse mode or reads SDL's independently accumulated relative-motion state. SDL confines the pointer and wraps it at window edges while the retained previous position absorbs each warp. MMB activation marks one start edge; the render path performs one canonical-geometry ray query at the initiating pointer and, on a hit, uses its distance to update the ECS camera's target along the unchanged view axis before applying orbit input. This preserves the initial framing; empty space retains the prior target. Stop captures this complete working state before authoring-world replacement and applies it to the reconciled replacement camera; project/world hot reload and explicit scene changes retain their own reset semantics. Accepted `F` input sets one request bit; the next camera phase clears it, visits retained instances for the ordered selected UUID set once, derives combined world bounds plus Transform fallbacks, updates the camera pose, and replaces the orbit point. Stable frames perform no ray query or selection-bounds traversal. |
| Editor entity selection and transform gesture | Editor UI ordered UUID set, active entity handle, monotonic selection revision, transient viewport gesture, WGPU identity target plus three-slot readback ring, transient `EditorTransformGizmo`, and frozen transform snapshots | Authoritative per-run tool state plus backend-owned derived identity/bounds evidence | Plain selection replaces the UUID set; Shift selection toggles membership and promotes the newest member as active. A viewport press remains armed until release or four pixels of motion. WGPU snapshots slot-to-root UUID ownership, renders the requested click or marquee into an integer identity target with its own depth, and asynchronously consumes only the scissored region. A marquee intersects visible identities with complete root-level projected-bounds containment before enclosed camera/light icons join the result. Null rendering uses the CPU scene-query fallback. Each later editor frame validates only selected UUIDs; world replacement drops missing members and rebinds the active handle. One revision invalidates browser rows, inspector identity, combined bounds, and GPU mask membership. Multi-transform gestures use the shared bounds center and publish one batch Undo/Redo transaction. Stable frames encode no identity pass, perform no readback, and do no selection membership scan or bounds rebuild. |
| Placement preview and rendered selection cue | Editor UI state plus WGPU retained instance records, dense selected slots, two-channel feedback mask, and engine-time sampling | Transient editor-derived state | An active valid Model drag resolves its frame-valued pointer through the backend-neutral scene query, rebuilds the editor overlay when contact/root changes, and reuses each primitive's resolved conventional data or virtual pinned proxy in the ghost channel. Release clears the preview. Selection revision changes scan current retained instances once and patch direct UUID or selected `model_owner` matches plus dense membership; later dirty slots update locally. The depth-independent mask redraws selected geometry from the same submission cache each frame, without changing Geometry cache policy, but stable selection performs no membership scan or instance upload. During Running and Paused, dashed selection samples run-global engine elapsed time independently of simulation; Stopped retains the solid outline. Hiding the editor retains selection but clears an active mask once, then skips stable hidden feedback passes. |
| Editor transform snapping and infinite grid | Editor UI state plus WGPU grid pipeline/uniform | Transient editor policy and derived backend presentation | One setting supplies placement/translation spacing plus enabled rotation and scale increments; the command modifier inverts it only for the active gesture. Gesture math quantizes against its frozen world/local basis before applying the Transform. Independently, while the editor is visible, WGPU draws six procedural plane vertices before transparency, depth-tests against the opaque world, and selects one clamped power-of-ten spacing level from camera height for the complete plane with a one-unit minimum. Minor lines crossfade into every tenth major line. Camera changes update one fixed uniform; hidden frames skip the pass, and no scene membership, line mesh, or persistent resource exists. |
| UI theme palettes, metrics, typography, and named recipes | Shared UI composition contract plus UUID-backed `resources.Registry.ui_themes` | Ephemeral composition input with versioned lookup, not retained UI authority | Scene parsing, Luau resolution, UUID-specific native host resolution, and editor composition consume the same engine-owned recipe vocabulary before typed ECS attachment or update. The resolved `ui_*` values are authoritative for layout and paint; the registry revision refreshes resource inspection only. No theme identity, ancestry cascade, stable-frame traversal, or renderer-side style store remains. |
| Retained UI hierarchy, authored canvas transform, intrinsic text lines, flex lines, popup rectangles, dock tabs, panel/split/control gestures, layout, interaction, and paint commands | `ui.State` | Derived from public UI ECS components and active font metrics | Structural dirty queue plus independent project/editor layout and paint revisions. World UUID replacement invalidates membership and layout even when the new world's numeric revisions coincide with the previous world. It clears entity-bound pointer captures while retaining the physical held-button baseline until release, preventing replacement content from receiving a synthetic press. Buttons activate on release-inside and cancel on release-outside. Intrinsic measurement, bounded basis/grow/shrink line packing, and direct-child dock-tab/stack-order resolution run only for an invalidated domain; the exact text breaks feed paint. The optional root `ui_canvas` slot is cached per origin; its revision resolves the logical viewport, output scale/alignment, and safe area once for all downstream consumers. Popup placement derives from the live anchor/viewport only after affected ECS open, anchor, or constraint changes. Dock transfers update authoritative item parent/active UUID; edge drops create authoritative public stack/dock topology and preserve the replaced sibling order; panel drops update authoritative parent/stack order. All reuse ordinary invalidation, and stable frames retain bounded gesture state without a World scan. |
| Immutable UI event history | `shared.World.ui_events` | Derived ordered interaction history | The UI interaction pass first dispatches a pointer edge through the hit ancestry until a reusable control cancels propagation, then appends actual published edges to a 256-entry ring with monotonic sequences. Luau, native extensions, and editor orchestration retain independent cursors. Overflow is explicit; world replacement resets the sequence space and destruction reclaims copied action strings. |
| `scrapbot.ui_state` components | UI reconciler | Derived, renderer-owned | Targeted interaction-dirty queue and retained node state; project code reads only. |
| Render-instance membership and retained render list | ECS render extraction | Derived from Transform/geometry/material/shadow membership, layered geometry-submission policy, and resource resolution | Structural/static dirty queue, separate exact Transform queue, project/asset/entity policy replacement, and resource revisions. Static extraction supersedes a same-frame Transform entry. Entity and slot reverse indexes are bidirectional ownership maps: delayed removal of a stale owner must never erase a newly reused slot's mapping. Batch appearance/disappearance advances topology exactly at the membership boundary. |
| GPU instances, conventional and virtual draw/visibility data, mesh and world distance fields, lights, shadows, postprocess targets, pipelines, and resource caches | WGPU backend | Derived backend state | Exact dirty queues, resource versions, resolved submission policy, camera/viewport revisions, target shape, capacity or meshlet-policy threshold changes, world replacement, or backend lifetime. Geometry caches are keyed by handle plus resolved path so different instances may consume both representations. Meshlet index/metadata/template state follows Geometry versions and retained batch capacity; each batch retains its resolved path, while current-frame counts reset from templates. Mesh fields remain file-backed until requested, then retain one packed storage buffer through that Geometry-cache lifetime. The debug-requested world field retains three snapped 32³ seed/distance cascades. Camera-cell movement scrolls retained seed coordinates, invalidates and seeds only exposed slabs, and propagates only affected cascades; viewport, topology, Geometry, instance, or Transform changes rebuild all cascades. Stable frames upload and dispatch nothing. Windowed runs add an SDL-backed surface; headless runs own an offscreen color target. Explicit live captures allocate bounded color/depth/visibility readbacks, then release them after the frame barrier. See [WGPU derived state](#wgpu-derived-state). |
| WGPU frame scratch | Odin frame thread's temporary allocator | Ephemeral backend state | Reclaimed at the beginning of every surface or offscreen frame, after the previous frame's extraction, streaming, encoding, profiling, live-debug publication, and deferred cleanup have completed. Page assembly, feedback sorting, dirty-cluster lists, and upload staging may borrow this memory only inside one frame. No retained renderer, resource, ECS, profile, or live-debug state may reference it. |
| Active-camera render policy | Authored `scrapbot.camera`; consumed by WGPU | Authoritative ECS bounds with derived world-scale, shadow-tier, virtual-geometry error, post-quality, target/execution/history, and exposure state | One controller consumes completed asynchronous scene spans exactly once, retains a fixed 20-sample p95 window plus filtered average, and advances one deterministic reversible quality step. Samples carry one generation; any output/policy change or different stable project-camera UUID clears both evidence sets and rejects delayed results. Missing timestamp support selects authored maxima. The editor fly camera contributes pose/lens but retains the project camera as policy owner. Effective scale and the physical game viewport select retained viewport-local world/depth/post targets; shadow resolution selects an active viewport inside fixed capacity; virtual error bounds the camera and shadow hierarchy frontiers; post quality bounds AO/SSR loops and fog steps. Target-size changes replace only size-dependent targets and reject temporal history. Final composition maps the local scene target into the physical game viewport before native-resolution UI. Stable outputs allocate nothing. Automatic exposure owns one persistent GPU scalar and performs no CPU readback. Disabled TAA or post features omit their history or dispatch work. Retained targets stay allocated across feature toggles. See ADR-052. |
| Adaptive directional shadows | Unified active-camera frame-budget policy and retained WGPU cascade state | Derived quantized raster size, stabilized projections, and refresh schedule over maximum-capacity layers | The shared ladder may select 2048, 1024, or 512 pixels within the authored adaptive-quality floor. The near layer refreshes every frame; farther layers refresh at bounded 2/4/8-frame cadences and otherwise retain their previous matrix and texture contents. Light activation, world/topology/Transform changes, camera discontinuities, and resolution changes force all layers current. Stable frames keep the same texture, views, and bind groups. Viewport/scissor, cascade stabilization, PCF coordinates, and virtual-shadow hierarchy thresholds consume the active size. |
| Global volumetric medium | Authored singleton `scrapbot.volumetric_fog`; consumed by WGPU | Authoritative generic ECS payload plus renderer-owned resolution-scaled scattering/transmittance target | Membership/value changes follow ordinary custom-component lifecycle and revisions. Postprocessing visits only the named storage's compact active set and copies the selected payload into the retained temporal uniform. Nonzero density dispatches the ray march; zero density skips it. A `resolution_scale` change explicitly invalidates size-dependent post targets; ordinary stable frames reuse them. |
| Composable presentation effects | Authored singleton `scrapbot.vignette`, `scrapbot.lens_flare`, and `scrapbot.lens_dirt`; consumed by WGPU | Three independent authoritative generic ECS payloads plus one renderer-owned uniform buffer | Membership/value changes follow ordinary custom-component lifecycle and revisions. Postprocessing visits only each named storage's compact active set and clamps the selected payloads. It uploads the fixed-size uniform only when those effective values, adaptive quality, bloom state, or debug suppression change. Stable frames allocate, rebuild, and upload nothing. Absent/zero effects take early shader branches. |
| Project/editor/overlay UI vertex buffers | WGPU backend | Derived from UI output streams | Independent monotonic stream revisions; stable streams retain CPU/GPU buffers. Target size, editor viewport, or authored canvas changes invalidate the project stream key. Project commands use the canvas's vector scale plus viewport translation and clipping; pointer input and diagnostics invert the same transform. The overlay contains projected transform handles, camera bodies/frusta, up to 256 fixed-apparent-size camera/light icons with bounded deterministic decluttering, and selected-light influence handles. Editor UI state owns world-tool pointer capture plus captured Transform/light values; active gestures retain the unfiltered window pointer across editor chrome, while writes use ordinary inspector/history ownership. Editor visibility clears overlays. The compositor paints project UI, viewport-clipped editor-world overlays, then editor chrome so docked tabs and panels occlude scene tools. |
| Embedded UI viewport membership, live targets, and resource thumbnails | `ui.State` / WGPU backend | Derived from authored `scrapbot.ui_viewport`, layout, and resource/World state | Structural UI dirtiness maintains compact viewport-node membership. Interactive surfaces use eight independently sized live targets, quantized from 64–1024 pixels per axis. Static Texture/Model/Material Inspector scenes cache by component, target shape, exact resource version, and relevant registry revisions; World targets consume the retained render list. Passive laid-out resource rows instead request a revision-keyed, least-recently-used 256-layer 64×64 texture-array cache. A miss renders once through an otherwise-idle live target, copies into the fixed 4 MiB cache, and invalidates the retained UI stream; stable hits do no render or upload work. Model previews prefer virtual submission, reusing eligible Geometry's pinned coarse proxy instead of materializing complete conventional data. Missing, evicted, or inadmissible thumbnails retain the atlas icon fallback. |
| System profiler snapshot | Root runtime | Derived diagnostic state | Samples every frame, rolls over 50 frames, publishes every five frames. |
| Performance diagnostics snapshot | Renderer/root runtime | Derived diagnostic state | Wall-clock frame-interval and active-CPU duration samples roll independently over 50 frames. Retained topology, asynchronous camera-visible batch and nonempty-meshlet-draw counts, visibility and retained-slice overflow counters, one full ordered pass-boundary span, one pre-UI scene span, per-pass attribution, and mutation-maintained world counters publish every five frames under one revision. |
| Engine failure reports | CLI process plus platform unwinder; instrumented call stack in development builds | Process-fatal invariants and unexpected renderer task failures | CLI startup installs one assertion/panic handler and optimized/development builds retain debug symbols. Fatal reports and renderer task failures that violate an engine resource invariant print the exact detection site and a best-effort bounded native stack; fatal invariants then trap, while task failures still unwind through their ordinary error result. `scrapbot-dev` additionally instruments Odin procedure entry/exit so both paths print a reliable source-level call chain. Expected project, asset, argument, and unsupported-capability failures remain ordinary structured diagnostics without crash noise. |
| Bounded render profile | CLI-owned `Profile_Collector`, populated by renderer/WGPU | Ephemeral diagnostic artifact | Explicit `scrapbot profile` lifetime only. Preallocated measured rows receive active CPU, frame-local counter, and structured pass-workload data directly and delayed full-frame, scene, and per-pass GPU timing by originating frame index. Profile-only feature overrides resolve a temporary camera/fog policy after ECS extraction without mutating authored data. Finalization derives summaries; destruction releases rows and adapter metadata. Ordinary runs have no collector and perform no profile work. |
| Live debug snapshot, capture job, and artifact plan | Root-owned `live_debug.Service`; renderer-owned provider resources | Immutable derived diagnostics plus one bounded pending command | Windowed editor lifetime or explicit `--live-debug` opt-in. The engine thread replaces one owned snapshot and consumes at most one 1–16-frame capture. WGPU allocates, encodes, maps, and releases requested color/depth readbacks inside that frame and dispatches visibility diagnostics into a dedicated fixed 4 MiB non-render buffer; null supports telemetry only. A loopback HTTP worker only authenticates, encodes, serves completed files, and updates mutex-protected request state; it never reads ECS, registry, renderer, or GPU owners directly. Stable frames perform one bounded snapshot copy only while enabled and no artifact work. Shutdown removes discovery and releases captured strings. See ADR-053. |
| Live entity origin counters | ECS world | Derived from entity lifecycle | Incremented on spawn and decremented on despawn; diagnostics read them without scanning entity capacity. |
| Editor browsers, rooted resource-directory state, inspector snapshots, reflected-container expansion, and UUID-picker candidate rows | Editor UI composition over component/resource registries, canonical payloads, and `file_browser.State` | Derived tooling view plus bounded filesystem metadata | The entity browser contains authored entities plus selected runtime entities. The Resource Browser scans only its current `resources/` directory during initialization or explicit navigation/refresh, retains at most 4,096 names/paths/sizes, then joins registry resources by source directory; stable frames do no filesystem work and browsing never loads payloads. Rows use atlas-backed type icons or laid-out Texture/Model/Material viewport previews from the fixed shared pool. All selected rows receive the public list selection treatment; one active row owns inspector composition and local gizmo orientation. Component cards and rows are runtime type-inspected with no per-component panel catalog. Selection or explicit structural invalidation rebuilds them; the 5 Hz running-value cadence refreshes values without rematerializing browser rows. Nested records and fixed arrays retain bounded reflection paths on pooled public disclosure/leaf controls; collapsed containers do not recurse or materialize descendants. The entity-reference popup enumerates and validates scene candidates only when opened, retains a missing/current reference for repair, and delegates filtering/virtualization to public UI components. Stable closed frames do no candidate work. Stopped values remain change-driven, focused inputs retain staged text, and active scrubs defer unrelated refresh. |
| Generated Luau declarations and native build products | `.scrapbot/` and build directories | Derived products | Regenerated from schemas/source and never hand-edited as authority. |

## Resource render state

Project resource load, editing, and hot reload update the registry. Material descriptions own cloned factors and image payloads. Environment descriptions own a cloned source panorama plus irradiance and specular cubes.

Render state resolves independent lighting and optional-background handles/settings. One monotonic environment revision invalidates the global WGPU binding only when selection, settings, or content changes.

Active-camera exposure is a separate compact input. Fixed exposure rewrites the environment uniform without rebuilding textures. Automatic exposure keeps that uniform neutral, meters only the active viewport after temporal resolve, and stores its adapted scalar in a backend-owned GPU buffer shared by bloom and composite.

Procedural solar elevation derives day/night presentation and fill in shaders. Above the horizon it also produces an ephemeral first directional-light input; it does not create an authored entity or component.

## WGPU derived state

### Instances and draws

Transform-only slots pack one dense 64-byte update with a destination slot. One upload feeds a dirty-only compute pass that expands matrices and bounds before culling.

If lifecycle churn exposes a mismatch between authoritative render-list membership and a Transform-dirty GPU slot, only that slot receives static reconciliation before its Transform update. This activates a missing GPU owner or retires stale GPU membership after slot reuse/removal; missing resources or batches remain errors. World replacement clears all retained GPU slots, including capacity beyond a smaller replacement world.

Static instance fields remain separately retained. Batch topology, geometry capacity, and exact structural changes drive their updates.

Adapters with indirect-first-instance additionally retain meshlet metadata, expanded index ranges,
camera/shadow visibility slices, a parallel debug-identity stream, and indirect templates.
Classic per-batch slices retain 256-byte dynamic-storage alignment. Meshlet and hierarchy-cluster
slices share one storage binding and allocate exact `cluster count × max(instance count, 1)`
cardinality, without multiplying every cluster by the classic alignment.
Any membership-count change in a meshlet batch invalidates this layout even when its classic
aligned visibility capacity still fits, because every cluster slice embeds the exact instance
cardinality.
Native multi-draw adapters address those templates directly. Other capable adapters retain a
bounded stream of compact `{instance slot, meshlet index}` records plus four triangle-count lanes
per compatible material span. Their vertex shaders pull indices and packed attributes from the
shared geometry arenas. Conventional meshlets use the same compact representation for camera and
shadow work. Fully resident virtual resources may retain indexed object-LOD shadows, while
streamed resources use page-local compact shadows. Geometry versions define command topology.
Batch membership capacity defines visibility allocation.

Only batches resolved to virtual submission use the cluster hierarchy. Automatic policy requires a
capable adapter, eligible hierarchy-bearing Geometry, and the stable source-triangle crossover;
forced virtual requests still fall back safely when those hard capabilities are absent.
Conventional batches select whole-primitive submission for single instances and ordinary meshlets
for reused batches. Those meshlets use native multi-draw or portable compaction according to
adapter capability. Policy changes invalidate only the retained batch layout, while camera motion
never changes the resolved path. Meshlet-oriented debug views may change visualization without
rewriting policy topology.

WGPU queries the device's storage-buffer binding limit during initialization. Retained cluster
metadata grows geometrically until another power of two would cross that limit, then uses the
largest legal record capacity. A live topology that fits therefore remains eligible even when its
geometric spare capacity would not; a topology whose live records do not fit retains the existing
whole-primitive fallback.

The compute culler projects monotonic hierarchy-group errors into pixels. It selects one complete
camera frontier outside a narrow 98%-to-102% overlap around the active error target and adjacent
levels inside it. Both complete opaque levels depth-test normally within the overlap. Native indexed
submission starts at one pixel; portable compact virtual submission starts at its measured two-pixel
floor because padded vertex pulling changes the cost/quality crossover. The coordinated frame-budget
controller may raise the effective target through bounded power-of-two tiers after render scale
reaches its floor. Shadow selection uses the same hierarchy with cascade-scaled thresholds,
preserving near detail while bounding distant-cascade work.

Stable frames copy separate active camera and shadow templates, run object-first compute culling,
and submit matching command ranges. Portable compact submission first appends bounded batch-local
instance candidates. Parallel camera and shadow dispatches then assign one ordinary meshlet or
hierarchy cluster to each invocation instead of making one instance invocation loop the complete
resource. Separate candidate, camera, and shadow bind groups reuse the baseline eight-storage-
buffer layout.

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
binding range even when the shared vertex/index buffers have grown beyond it. Compact virtual-page
allocations are hard-bounded to that advertised prefix; a failed fit defers refinement instead of
publishing shader-inaccessible arena offsets. Stable frames never scan, compact, hash, or upload
the arenas.

Imported mesh-distance samples remain in their independently addressable Model-product range. A
GPU consumer lazily invokes the canonical range loader, packs two signed 16-bit samples per storage
word, and retains that buffer plus its debug uniform and binding in the exact Geometry cache entry.
Geometry version replacement and cache retirement release the field with the render ranges. Stable
hits perform no file read, allocation, packing, or sample upload.

Logical eviction transfers page and cache ranges into arena-owned retirement queues. The ranges
remain allocator-owned and unavailable for reuse until a mapped post-geometry visibility copy
proves their last arena read complete. Completion-driven reclamation is change-driven; stable
frames with no retired ranges perform no retirement work.

Hierarchy metadata and each Geometry's file-or-memory page source are resource-owned. WGPU owns
canonical fast-path or page-local vertex/index arena ranges, residency, visible-use age, pending
immutable product-range reads, and the configured combined payload budget. Outstanding reads have
fixed job and byte ceilings. Completed-but-unadmitted payloads have a separate bounded staging
budget and age out when demand no longer owns them. A bounded, error-prioritized bootstrap tail is
loaded before ordinary streaming begins. Only its mandatory terminal groups remain pinned;
additional startup refinements may be reclaimed by the global residency policy. WGPU bounds those
optional refinements across all caches to three quarters of the configured page budget and owns the
remaining first-camera working set.

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
demand residency.

Geometry cache groups distinguish memory residency from drawable activation.
Newly complete groups pass a bounded demand-aware settling window and require every direct parent
to remain resident, active, and transition-complete before entering a 16-frame admission handoff.
The GPU combines that temporal progress with its steady projected-error overlap and depth-tests complete child/parent surfaces in
world and depth passes. Native and portable compact shadows select their resident hierarchy
frontier directly. Streamed portable resources retain an indexed proxy of the complete terminal
frontier for capability or capacity fallback.

The internal HDR alpha channel carries a
transition reactive marker, and temporal history encodes that marker alongside the existing
bloom-enable bit. The temporal resolver owns its depth-tolerance adjustment. Completion is the
point at which the child becomes the logical refinement. Active refinements retain their direct
coarse parents until release.

Feedback consumption shares fixed byte and group admission budgets across every readback completed in
one frame. Resident touches always update recency. Once the group budget is exhausted, nonresident
requests are counted as deferred without rebuilding missing-page or staging arrays that cannot be
used. Frame scratch is reclaimed before the next frame, so repeated pressure remains bounded in both
CPU work and memory.

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

The nearest cascade is current every frame. Farther cascades retain stabilized projections and depth contents between scheduled refreshes, with at most one far layer joining the near update on an ordinary frame. Any authoritative scene mutation or discontinuous view/policy change refreshes all four layers before reuse.

The layers retain 2048² capacity. A quantized active viewport bounds raster work without reallocating bindings. Cascade stabilization, receiver bias, PCF atlas remapping, and shadow hierarchy detail all use the same active resolution.

Frustum and LOD work uses the unjittered camera. TAA's eight projection samples remain within a quarter pixel. Retained history lives on the stable output grid, so reprojection uses unjittered current/previous camera matrices and removes the current sample offset before sampling history. A matching depth is selected from the local 2×2 history footprint, while YCoCg variance clipping limits stale color.

Retained Hi-Z depth tracks the exact camera projection that produced it and expands projected bounds by one pixel to remain conservative across TAA samples. Its power-of-two allocation pads non-power-of-two render targets with far depth, preserving complete edge coverage through every native mip reduction. An unchanged camera may use that pyramid directly. Camera motion or other retained-history invalidation instead selects a complete coarse virtual frontier, renders current-camera occluder depth, builds the pyramid, and refines detailed visibility in the same command buffer. The renderer then clears coarse depth and writes final detailed depth, so the proxy frontier is never observable color or retained scene depth.

### Postprocessing

Surface data, indirect diffuse, and reflection output are current-frame derived targets. Visibility-bitmask AO consumes depth plus mapped normals and attenuates only indirect diffuse. SSR consumes surface data and HDR color. AO and SSR quality tiers update only their next uniform and bounded shader loop; retained target allocation and bind groups remain unchanged.

The extracted camera's debug view, Hi-Z mip, and occlusion-evidence freeze flag are authoritative for a rendered view. While the editor is visible, optional transient Game controls replace them only on the retained render-list camera copy.

Non-lit output updates compact render/cull uniforms, skips temporal and presentation effects, and reuses existing targets. Hi-Z inspection reads the current retained pyramid after construction and adds no copy, readback, or pyramid rebuild.

Meshlet identity storage follows topology/capacity invalidation rather than frames. Its visible-instance allocation reserves an aligned diagnostic tail.

Meshlet Visibility writes rejected bounds there during the frame-valued cull. Occlusion Queries instead writes every performed query's projected rectangle, mip, compared depths, identity, and decision. Both copy the counter into an indirect line draw and publish it asynchronously.

While query freeze is active, the renderer leaves the latest valid tail and indirect count untouched. Current visibility, depth, and Hi-Z ownership remain frame-valued; freeze does not authorize stale depth reuse for culling. Leaving the view clears the diagnostic-valid flag and retained published count.

### Project spectral surfaces

The Shader resource owns spectral parameters and versioning. Its WGPU cache owns the
frequency-domain intermediate buffer, raw spatial displacement buffer, current and previous finalized
displacement/normal/crest/foam fields, uniform, bind groups, and pipeline association. Storage reserves
three fixed 64×64 bands; the authored one-to-three band count controls dispatched Z lanes and public
sampling. Adjacent bands partition wavelengths and share the same command sequence. Each raw spatial
band is frame-local FFT output; each finalized field band's normal lane publishes retained foam to
project shaders. The previous finalized field is the authoritative history input for the next
advance.

The default `scrapbot.clock` component is the project simulation-time authority, with `world.time`
retaining its high-precision boundary snapshot and `world.default_clock_uuid` retaining the selected
source identity so a default change adopts the replacement clock's own timeline. Project-shader
time helpers receive its elapsed time and frame index; shader delta is zero on a redraw without a simulation step. Each active
spectral Shader updates its uniform and encodes one horizontal plus one vertical inverse FFT followed
by one spatial finalization dispatch at most once per elapsed-time change, even when several
transparent draws share it. Before an advancing simulation overwrites the current field, a GPU copy
retains it as previous-frame deformation input. Paused redraws retain both fields without an upload,
copy, or dispatch.
Finalization derives the compression Jacobian, deposits breaking foam, and exponentially decays
the retained history after backtracing it through the Shader's uniform world-XZ foam-advection
velocity. Bilinear periodic sampling transports foam consistently across each band's physical patch
scale. No time advance means no foam mutation. Inactive and non-spectral
Shaders encode no spectral work and bind the renderer's shared zero field.

Changing the Shader version releases only that Shader's spectral state, including foam history, and
render pipeline. Resizing the scene target rebuilds only per-Shader scene/depth bind groups; the
spectral field survives.

The post-target set owns one viewport-sized `RG16Float` custom-surface motion texture. Transparent
custom shaders write previous viewport UVs; `[-1, -1]` is the invalid sentinel. The target clears
once per frame and TAA samples it directly, so stable frames do not create CPU extraction or
per-object uploads. Target resize recreates it with the other post targets.

### Water volumes

Each authored `scrapbot.water_volume` owns medium coefficients and horizontal bounds; its entity
Transform owns center and mean surface height. WGPU visits the compact custom-component active set,
resolves only candidate transforms, and selects by priority then scene order. The authored
`surface_displacement_bound` conservatively expands this broad phase around animated waves.

The renderer owns one 32-byte query uniform and one 16-byte retained query result. The render list's
entity-to-instance index locates the selected owner without a world scan. When that instance uses a
custom Shader, one compute invocation executes its canonical `scrapbot_vertex` deformation and
iteratively inverts horizontal displacement at the camera position. The result buffer owns current
height plus current/previous submersion; command ordering makes it directly visible to temporal
composition without CPU readback. The CPU mean plane only selects the bounded candidate; it does
not classify the camera medium. The temporal pass derives camera depth, ray exit, fog replacement,
caustic water column, and crossing rejection from the queried height. Candidate removal invalidates
the result. Receiver caustics still
use current depth, surface normals, directional-light state, and shadow maps inside the existing
temporal pass, so the height query adds no image target.

Virtual Geometry caches additionally own any terminal-frontier shadow-proxy index range. The proxy aliases
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
