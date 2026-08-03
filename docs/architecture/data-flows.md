# Major Data Flows

**Last verified:** 2026-08-03

## Project load and world bootstrap

```text
project.toml + scene/resource files + source assets
        │
        ├─ fingerprint/import ──> versioned Texture/Model/Environment/Icon products ─┐
        ├─ build/load native extensions ─┐
        └─ execute Luau registration ────┴─> component registry
                                                │
scene parse + schema validation + resource UUID resolution
                                                │
                                           ECS world
                                                │
                         structural/render dirty bootstrap queues
                                                │
                       retained UI + render list + backend caches
```

Native components register before Luau executes, so scripts can retrieve native handles. Asset import completes before runtime resource registration. Scene validation uses the combined engine/native/Luau registry.

Before bootstrap, Model import simplifies eligible primitive index streams, compacts each retained
level, and builds its crack-aware hierarchy. The sequential product writer emits material images,
pinned coarse pages, and evictable detail pages before writing a descriptor catalog containing the
LOD chain, position-only query data, hierarchy, and exact payload ranges.

Runtime loading validates the product kind, chunk directory, chunk headers, and every catalog
range. It buffers only catalog fields, reads material images from the image chunk, publishes
semantic Geometry subresources one primitive at a time, and promptly releases each decoded entry.
Geometry page bytes remain file-backed in the coarse or detail chunk.

At bootstrap or reload, Model roots reconcile imported nodes and primitives into derived
Transform/Geometry/Material entities. Later duplication, Undo/Redo, or resource replacement
increments a model-instance revision; reconciliation waits for that structural signal.

Resource descriptions remain outside ECS. Components store resolved runtime handles. Geometry
registration derives bounded meshlets from source geometry or exact compiled hierarchy leaves. It
accepts a validated compact catalog and file-backed page ranges for imported models or derives the
same hierarchy and in-memory page payloads for other producers. Imported entries retain canonical
counts and a position-only query proxy without ever decoding complete CPU render vertices or source
indices during a cache-hit bootstrap. Canonical vertex IDs, exact leaf topology, monotonic group
errors, page identities, page-source records, and pinned fallback flags remain versioned with the
Geometry entry.

Picking iterates exact leaf triangles against resident vertex positions or the query proxy. A
classic backend path asks the resource for a canonical view. Memory sources lend resident arrays;
file sources reconstruct vertices and leaf indices from all leaf-containing pages into a temporary
owned view. WGPU releases that view immediately after the invalidated Geometry version is uploaded.

WGPU consumes ordinary Geometry versions into aligned shared vertex/index ranges. A complete
Virtual Geometry that fits the remaining budget retains canonical vertex/index ranges plus
expanded page indices. Larger resources allocate page-local vertex and index ranges only for
resident pages, with the coarsest pages pinned.

GPU feedback identifies visible demand, bounded future-camera prefetch, and visible-use touches in
separate bounded lanes.
Imported misses enqueue immutable product ranges on the I/O worker. Versioned completions admit and
evict whole groups under bounded per-frame work and the combined payload budget. One priority-ordered
plan serves every eviction in the feedback batch. Demand may reclaim speculative residency;
prefetch uses spare capacity only. Completed groups stage residency separately from drawable
activation through a bounded demand-aware settling window. After direct-parent transitions settle,
a child and its complete parent remain drawable through one 16-frame admission handoff. Independently,
the GPU submits adjacent resident levels inside a narrow projected-error overlap band. World, depth,
and shadow passes assign exact complementary coverage to both transitions. TAA rotates and resolves
camera coverage over time; non-temporal views and shadows keep a stable spatial partition. Nested
admission handoffs serialize. An active child protects its direct parent fallback, and
release orders child before parent eligibility. Persistent dependency indices patch only affected
cluster ranges rather than regenerating a Geometry's complete GPU residency table.

Capable adapters retain cluster metadata and arena-global indirect templates. They select the
desired resident frontier and draw a coarse fallback while refinement is missing. Native
multi-draw consumes cluster commands directly. Other indirect-first-instance adapters compact
batch-local instance candidates, then test hierarchy clusters in parallel into bounded camera and
streamed-shadow records before vertex-pulling from the arenas. Shadow cascades use progressively
coarser hierarchy error thresholds, scaled again when adaptive shadow resolution selects a smaller
raster region. Fully resident portable resources retain classic indexed shadows.
Adapters without indirect-first-instance keep whole-primitive submission.

Hot reload stages the resource registry, world, script/native runtime, source set, and playback baseline independently. Failure destroys the staged bundle; success swaps it atomically.

## Simulation and scheduled mutation

```text
SDL/headless source → keyboard + pointer singleton snapshots
                                      │
playback transport → simulation delta → cached schedule plan
                                         │
                      non-conflicting native batches (parallel)
                                         │
            retained query plans + caller-owned 64-entity chunks
                                         │
                         explicit writable-lane masks
                                         │
                              Luau systems (serial barriers)
                                         │
                             per-system command buffers
                                         │
                          deterministic command application
                                         │
                typed storage + structural/render/UI dirty signals
```

Native chunk descriptors compile into retained per-system plans that resolve the candidate storage and typed field-array indices once. Ordinary chunks then traverse the retained active set and address fields directly; a world replacement, schema revision, or newly appearing storage family invalidates the plan. Chunks still copy supported fields into extension-owned scratch arrays and commit only explicitly marked writable lanes, so ABI amortization and SIMD do not expose ECS storage or broaden dirty propagation. Systems declare reads/writes; structural changes are deferred until iteration finishes.

## Component inspection and authoring

```text
selected entity + component-registry membership
                    │
          storage-kind payload locator
                    │
        ┌───────────┴────────────┐
Odin runtime struct fields   dynamic registry schema
        └───────────┬────────────┘
                    │
       generic panel/table/control pool
                    │
      validated component-scoped snapshot
                    │
       exact ECS mutation + undo/history
```

The editor has no component-specific panel catalog. Every attached registry definition produces a card from its runtime name and canonical payload shape; marker payloads produce title-only cards, while derived or unsupported fields remain read-only and start collapsed. Storage adapters locate canonical values but cannot choose rows. Reusable controls specialize only by reflected type or semantic metadata. Staged input remains local until commit; completed authored edits capture and apply only the affected registered-component snapshot rather than replacing the complete entity.

Input singletons are committed once before the schedule runs. Luau and native systems read the same immutable held/pressed/released snapshot and declare `scrapbot.keyboard_input` or `scrapbot.pointer_input` access without allocating synthetic entities or scanning entity storage.

Each native worker and the Luau runtime retain a private deferred-command buffer. A compact header stream preserves issue order. Spawn, despawn, add-component, and remove-component payloads grow in separate typed arrays.

Queued spawns and component additions pool only the custom/UI components actually present. Schema-backed headers reference separate Number, Vec2, Vec3, and Vec4 arrays containing only supplied fields.

Buffers start small, grow geometrically, merge with deterministic index/range remapping, and retain their high-water capacities. Fixed limits apply only to caller-owned ABI staging payloads, not to engine queue length or unused component capacity.

## Rendering

```text
typed ECS/resource mutation
        │
        ├─ membership/resource eligibility ─> structural/static render queue
        └─ Transform mutation ───────────────> exact Transform queue
                                                │
                                  retained backend-neutral render list
                                      │
                  static slots + Transform-only slots
                                      │
       retained static writes or one dense transform-update upload
                                      │
                  dirty-only GPU transform expansion
                                      │
             persistent WGPU instance/primitive/meshlet draw databases
                                      │
                retained per-batch classic/meshlet selection
                                      │
                         mixed object/cluster compute cull
                         ├─ compact visible instances or cluster records
                         └─ opt-in rejection records ─> indirect bounds overlay
                                      │
                 shadow + depth/sky/world + camera-selected debug/postprocessing
                                      │
 optional Shader spectrum → GPU inverse FFT → displacement/crest field ─┐
                opaque scene copy + depth + environment ────────────────┤
                                                                       ▼
                                                           project shader hooks
                                      │
                     sorted depth-tested transparent composition
                                      │
                         retained UI streams
                           ┌──────────┴──────────┐
                 SDL/WGPU surface          offscreen texture
                    + present           + optional readback
```

Windowed WGPU owns SDL input and an OS presentation surface. Headless WGPU never creates
SDL state or a surface: it requests the native adapter directly, submits the same retained
renderer workload into an offscreen target, and allocates a map-readable buffer only for an
explicit framegrab or capture sequence.

### Environment and lights

Cameras and lights are compact frame inputs. One authored `scrapbot.world_environment` component selects:

- an optional lighting Environment;
- an independently optional visible-background Environment;
- the procedural haze sky and HDR sun when the enabled background UUID is empty.

Editor mutation and validated Luau writeback update the authoritative ECS payload and bump only that entity's component revision. The `scrapbot.environment` phase retains the singleton entity and revision. It scans membership only after structural changes and copies settings only after value changes.

Active-camera pose and FOV construct the background ray basis. Fixed camera exposure multiplies world-environment exposure in the shared environment uniform. Exposure or atmosphere edits rewrite that uniform without rebuilding imported textures.

Backend-neutral extraction converts an above-horizon procedural sun into the first bounded directional-light input. This remains active when image-based lighting is imported separately; only an imported visible background replaces the procedural sky and its sun. WGPU then uses the ordinary GGX and cascaded-shadow paths without creating another authored entity. Below the horizon, the derived direct light disappears and both the sky and analytic environment lighting transition toward night.

Explicit ECS lights remain additive. Only the first directional render light owns the current shadow cascades and directional volumetric scattering. Later directional lights are direct, unshadowed surface contributions.

Scenes that need one coherent sun should use either the procedural environment sun or one authored directional light, not both.

WGPU retains active point lights in a geometrically growing buffer and rebuilds 16×9×24 cluster membership only after point-light, camera, viewport, or capacity changes. Four stabilized camera-relative projections feed independent shadow-cull lanes and depth-array layers.

One optional `scrapbot.volumetric_fog` component supplies a global exponential height medium. Postprocessing reads only that component storage's compact active set and clamps the reflected payload. A separately timed half-resolution compute pass folds 16 temporally rotated low-discrepancy ray samples into scattering/transmittance; the full-resolution temporal pass depth-aware upsamples that result before history accumulation.

Each sample uses the first directional light and a 2×2 UV-space filtered lookup into the same four shadow cascades as opaque rendering. Both paths cross-fade the final 10% of each cascade into its successor and fade the final cascade to unshadowed. Opt-in local scattering reads every relevant point light from the existing GPU-built cluster for that sample. A low-discrepancy spatial offset rotates across the eight-frame temporal sequence so fixed ray slices do not appear as bands; there is no duplicate light list. The half-resolution fog target is retained and recreated only with the other post targets. Local fog volumes remain follow-up work.

### Instances and materials

Stable renderable membership and instance records are not re-extracted or uploaded without a mutation signal. Transform-only changes upload compact position/rotation/scale/local-bounds records, then expand only those slots into GPU matrices and world bounds.

If legal despawn/reuse churn leaves an authoritative retained slot inactive, the Transform path reconciles only that slot's static state. Bidirectional integrity checks enforce current entity generations and slot ownership.

Material revisions trigger one dependent-instance pass. WGPU replaces only that Material handle/version's factor uniform, bind group, and owned image textures. Stable materials and static instance fields remain resident.

Shader revisions replace only that Shader handle/version's composed WGPU module and pipelines. Blended custom-material batches are collected from retained render instances, sorted against the active camera, and encoded after opaque world shading. The pass samples a retained opaque-color copy and read-only scene depth while preserving the opaque depth buffer.

### Camera-selected postprocessing

The active camera owns the world-render ceiling/floor, GPU target, adaptive post-quality floor, fixed/automatic exposure, TAA, current-frame fast AA, AO, SSR, and bloom switches. The editor fly camera contributes pose and lens while inheriting this policy.

Before layout, WGPU drains completed asynchronous timestamp readbacks. The scene span runs from the earliest executed timed pass boundary through final composition, before native-resolution UI. One controller processes each sample exactly once, filters it, and applies asymmetric hysteresis to one ordered world-scale, shadow-resolution, or post-quality step. Samples retain their render-policy generation, so delayed evidence from any previous output or camera cannot affect current state. Authored values remain ceilings and floors; adapters without timestamp queries select maxima.

WGPU derives one output layout and one effective world-render layout after that control step. The world, depth, Hi-Z, and post chain use the scaled layout. Final composition maps the complete scaled grid back onto the native output target. The native-resolution UI pass then paints project UI, editor-world overlays clipped to the Game viewport, and editor chrome in that order. Editor tabs and panels therefore occlude gizmos and camera visualizers when they cover the Game surface.

When the camera selects Hi-Z inspection, WGPU builds the ordinary current-frame pyramid and then samples the requested mip directly into the HDR world target. The debug pass expands each stored texel to its exact screen footprint; selecting another mip changes only the compact render uniform.

When the camera selects Occlusion Queries, the GPU culler appends exact query evidence into the meshlet diagnostic tail. Object rejection writes one record. Surviving objects write one record for each meshlet whose Hi-Z test executes. The overlay consumes the same GPU records through one indirect line draw.

Freezing leaves the last valid diagnostic range and indirect count resident while ordinary visibility continues to use current safety gates. Disabling freeze resumes replacement. Leaving the view invalidates the evidence.

Global volumetric fog is scene-owned rather than camera-owned. It composes before temporal resolution and bloom, stops at scene depth or its authored distance bound, and becomes a shader no-op when absent or at zero density.

World shading writes:

- HDR color;
- octahedral view normal, roughness, and metallic surface data;
- the indirect-diffuse portion of the HDR result.

AO reconstructs view positions from depth. Each sample marks a constant-thickness angular interval in a 32-sector visibility bitmask, then a joint depth/normal filter attenuates only indirect diffuse.

SSR ray-marches depth and samples confirmed current-frame HDR hits. The result feeds temporal resolution with confidence weighting.

When automatic exposure is enabled, one GPU workgroup samples 256 stratified pixels inside the active viewport, reduces their log luminance, and exponentially adapts a persistent clamped scalar. The scalar remains GPU-resident and is shared by bloom extraction and final composition. Temporal HDR history stays scene-linear.

Changing effective render scale replaces only size-dependent targets and rejects temporal history. Stable frames reuse the targets and their bindings. Disabling TAA removes jitter and history traffic. Disabling automatic exposure, AO, SSR, or bloom skips that compute dispatch. These value changes never reconcile renderable membership or rebuild imported textures.

## Performance diagnostics

```text
frame interval ──> fixed 50-frame rolling accumulator ──┐
WGPU timing / draw / visibility / Hi-Z state ──────────┼─> revisioned snapshot every 5 frames
spawn/despawn-maintained entity-origin counts ─────────┘                │
                                                               public ECS UI panel
```

The editor formats values only when the snapshot revision changes. GPU timestamp and visibility values are asynchronous. `GPU FRAME` runs from the earliest executed timed pass boundary through the final executed timed pass boundary, including UI when present. `GPU SCENE` shares that beginning and ends after final composition, before UI. Individual pass spans remain attribution and are not added to manufacture either duration.

Retained batches describe geometry/material/LOD topology. Draw submissions count compatible
command spans encoded for one pass. Camera-visible batches count selected batches with at least one
object surviving object-level visibility. Visible meshlet draws count indirect meshlet commands
with at least one surviving instance. These camera counters remain separate from shadow-cascade
visibility and from repeated API work across depth, shadow, and world passes.

Hi-Z state is an explicit enum: unavailable, below threshold, scene changed, camera changed, warming up, or active. Object and meshlet occlusion counts remain separate so a zero can be interpreted without guessing which eligibility or safety gate applied.

### Bounded render profiles

```text
fixed-delta warmup + measured replay
                 │
     active CPU sample by frame ───────────────┐
     tagged asynchronous GPU timestamps ───────┼─> exact per-frame rows
     viewport / resolution / renderer counters ┘           │
                                                   profile.json + overview

optional fresh deterministic replay ──> lossless 1:1 frame sequence
```

`scrapbot profile` is an opt-in diagnostic path, not an ECS system or ordinary-frame observer. The measurement pass never maps render-target pixels. Timestamp readbacks keep their originating renderer-frame index and patch the matching preallocated row. Bounded batch drains happen outside measured active CPU duration.

A requested capture range starts from a fresh project world and writes images during a second replay. Those readback stalls cannot contaminate the telemetry report.

Post-run tools consume the artifact without engine access. The analyzer ranks GPU-pass p95 values, prints representative target/dispatch/draw/sample workloads, totals frame-local counters, and rejects comparisons with different adapters or render dimensions. The sweep driver orchestrates independent profile bundles at each requested resolution and writes a compact scaling report.

## ECS UI and editor

```text
shared built-in theme ─────┐
UUID-backed project theme ─┼─ engine-owned ordered recipes
                           │
     ┌─────────────────────┼─────────────────────┐
scene TOML            Luau component map   native host callback
     └───────────────────┼───────────────────┘
              editor composition
                         │
              explicit entity overrides
                         │
           fully resolved public ui_* components
                         │
       structural queue + project/editor revisions
                         │
     retained hierarchy → intrinsic/flex/dock layout → interaction → paint
                         │
        immutable World event history
          ┌──────────────┼──────────────┐
       Luau cursor   native cursor   editor cursor
                         │
 uniform project-canvas/editor-viewport mapping
                         │
 read-only ui_state + system cursor intent + independent GPU vertex streams
```

Theme recipes are consumed only while loading, composing, or explicitly restyling entities. Scene directives select a built-in name or validated project UUID and create typed component defaults before component sections override fields. Luau resolves against the same runtime registry and returns a mutable component map; native Odin delegates built-in and project UUID resolution to distinct typed host callbacks that fill caller-owned ABI payloads. All paths share the engine-owned recipe vocabulary, preserve hierarchy and behavior fields, and leave no retained theme dependency. Theme registry versions refresh editor resource inspection, never layout or paint. The editor selects reduced-dark surface, chrome-bar, control-state, semantic-frame, and named semantic-color tokens from that same contract; it adds geometry, content, and project meaning but owns no separate visual constants.

An invalidated layout domain measures text and button leaf content with the
active font, packs optional wrapped stack lines from child basis and outer
size, and resolves each line's grow or shrink factors before descendant layout.
Text paint consumes the same deterministic line breaks. All scratch storage is
bounded; an unchanged domain repeats none of this work.

A dock space measures one tab for each direct public dock-item or titled-panel
child and lays out only the active child below that strip. A docked panel uses
its panel title as the tab and suppresses the redundant internal title band.
The same component optionally paints a dedicated tab-rail background and one
rounded content sheet behind that child, insets the child with public padding,
and extends a square active-tab strip over the sheet to remove the seam.
Alpha-zero sheet color leaves renderer-backed or otherwise self-painting
content unobscured while retaining independently themed rail chrome.
Cross-container drag completion changes the item's ordinary UUID parent and,
when applicable, the destination active UUID and stack order. The structural
dirty queue rebuilds retained parent links before the same-frame relayout, then
the interaction emits the ordinary drop state and immutable event contract.
An enabled directional edge drop replaces the destination at the same sibling
position with a runtime/editor-origin public HStack or VStack, reparents the
existing space into one fill child, creates a public sibling dock space for the
dropped item, and lets the ordinary stack separator own resizing. Scene and
runtime origins share the project UI parent domain for this generated
topology; editor origin remains isolated. The editor's Browse, Game, Inspect,
and movable tool panels are consumers of this exact path.

Every stack resolves direct children by public `stack_order`; `reorderable`
controls interaction rather than deterministic layout order. Movable panels
arm from their unoccupied title band; release within the threshold keeps
collapse-click behavior, crossing the threshold without a valid destination
cancels, and a completed drag normalizes affected sibling orders or makes the
panel a dock-space tab. Docked panel tabs can target reorderable stacks in the
opposite direction. The same stack may independently expose resize separators.
Gesture paint is transient and stable frames repeat no sorting, hit-geometry
construction, layout, or upload work.

During an active panel gesture, a dock tab hit resolves the nearest
reorderable stack in that item's retained descendant hierarchy. That target is
available even when the tab is inactive and its descendants are not laid out.
The drop therefore reparents into the tab's ordinary public stack; only
dock-space chrome outside an accepting tab targets creation of a sibling tab.
The accepting tab header paints the dock space's public drop background when
the inactive descendant cannot paint its insertion line. Backend-neutral move
and not-allowed cursor intents distinguish compatible targets from dead space.

Visible `ui_viewport` nodes additionally populate a compact retained target list. WGPU assigns each visible node an independently sized pooled target. Texture UUIDs use an aspect-preserving GPU pass; Model and Material UUIDs build isolated renderer-owned preview scenes; empty resource UUIDs render the retained active World. The UI shader samples those targets as ordinary clipped paint commands. Shared UI interaction mutates orbit/distance directly on the component; static resources redraw only when target state, quantized size/aspect, exact resource version, or relevant registry revisions change.

The editor adds transient editor-origin entities but uses the same components and mechanics as project UI. Editor-only code binds selection, history, project meaning, and commands to generic UI interaction. An optional public root `scrapbot.ui_canvas` resolves the project's logical viewport, output scale/alignment, safe area, and clipping inside the free-aspect game viewport. Rendering, embedded viewports, pointer inversion, and semantic diagnostic rectangles share that exact transform so explicit stretch behaves consistently and every other mode remains spatially attached to interaction. Projects without a canvas retain the legacy top-left 1280×720 fit.

The interaction pass publishes activation, change, submission, cancellation, and drag/drop edges into a World-owned bounded ring. `scrapbot.ui_action` resolves from the exact control or nearest layout ancestor and supplies optional project semantics without changing control mechanics. Readers use monotonic sequences and never consume entries destructively; project Luau/native adapters filter editor-origin events, while editor orchestration reads the same history through its own cursor.

The retained interaction pass derives a backend-neutral cursor intent from the topmost reusable control and any active workspace gesture after applying project-canvas pointer inversion. The windowed renderer maps pointer, text-edit, directional-resize, move, and not-allowed intents to cached SDL system cursors; headless runs retain the same UI interaction behavior without initializing the platform cursor boundary.

## Authoring persistence

```text
completed stopped-mode gesture
        │
UUID-addressed authoring transaction + dirty candidates
        │
Undo/Redo previews the active ECS/resource state
        │
Save compares against disk baseline
        │
prepare scene/resource create-write-delete operations
        │
recoverable project transaction → atomic source replacement
```

Play/Step capture an in-memory authoring baseline. Running/paused mutations are disposable. Stop restores the in-memory baseline without reloading code; Revert stages disk resources and a validated replacement world, then commits both together without reloading Luau or native code. A failed Revert preserves the complete live resource/world pair.

See [FDR-001](../fdr/FDR-001-runtime-cli.md), [FDR-005](../fdr/FDR-005-system-scheduling.md), [FDR-007](../fdr/FDR-007-ecs-ui.md), [FDR-008](../fdr/FDR-008-editor-shell.md), and [FDR-009](../fdr/FDR-009-project-resources.md).
