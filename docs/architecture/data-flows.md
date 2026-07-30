# Major Data Flows

**Last verified:** 2026-07-30

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

At bootstrap or reload, Model roots reconcile imported nodes and primitives into derived Transform/Geometry/Material entities. Later duplication, Undo/Redo, or resource replacement increments a model-instance revision; reconciliation waits for that structural signal.

Resource descriptions remain outside ECS. Components store resolved runtime handles.

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
                      persistent WGPU instance/draw database
                                      │
       compute cull + shadow + depth/sky/world + camera-selected postprocessing
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

### Camera-selected postprocessing

The active camera owns the manual world-render ceiling, optional GPU-budgeted dynamic-resolution floor/target, fixed/automatic exposure, TAA, current-frame fast AA, AO, SSR, and bloom switches. The editor fly camera contributes pose and lens while inheriting this policy.

Before layout, WGPU drains any completed asynchronous timestamp readbacks. Dynamic resolution processes every newly completed scalable-GPU sample exactly once, filters it, and applies asymmetric hysteresis in quantized 5% steps. Samples retain their render-policy generation, so delayed evidence from an old scale or camera cannot affect the new controller state. Native project/editor UI time is excluded. The authored `resolution_scale` remains the ceiling, the authored minimum remains the floor, and unsupported timestamps select the ceiling.

WGPU derives one output layout and one effective world-render layout after that control step. The world, depth, Hi-Z, and post chain use the scaled layout. Final composition maps the complete scaled grid back onto the native output target, then project UI, gizmos, and editor chrome render at native resolution.

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
WGPU timing / draw / visibility counters ──────────────┼─> revisioned snapshot every 5 frames
spawn/despawn-maintained entity-origin counts ─────────┘                │
                                                               public ECS UI panel
```

The editor formats values only when the snapshot revision changes. GPU timestamp values are asynchronous, and draw batches describe retained GPU-driven grouping rather than every API draw command in every pass.

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

A dock space measures one tab for each direct public dock-item child and lays
out only the active child below that strip. Cross-group drag completion changes
the item's ordinary UUID parent and destination active UUID, then emits the
same drop state and immutable event contract used by other project UI. Region
splitting remains ordinary HStack/VStack layout. The editor's Browse, Game, and
Inspect regions are consumers of this exact path.

Visible `ui_viewport` nodes additionally populate a compact retained target list. WGPU assigns each visible node an independently sized pooled target. Texture UUIDs use an aspect-preserving GPU pass; Model and Material UUIDs build isolated renderer-owned preview scenes; empty resource UUIDs render the retained active World. The UI shader samples those targets as ordinary clipped paint commands. Shared UI interaction mutates orbit/distance directly on the component; static resources redraw only when target state, quantized size/aspect, exact resource version, or relevant registry revisions change.

The editor adds transient editor-origin entities but uses the same components and mechanics as project UI. Editor-only code binds selection, history, project meaning, and commands to generic UI interaction. An optional public root `scrapbot.ui_canvas` resolves the project's logical viewport, output scale/alignment, safe area, and clipping inside the free-aspect game viewport. Rendering, embedded viewports, pointer inversion, and semantic diagnostic rectangles share that exact transform so explicit stretch behaves consistently and every other mode remains spatially attached to interaction. Projects without a canvas retain the legacy top-left 1280×720 fit.

The interaction pass publishes activation, change, submission, cancellation, and drag/drop edges into a World-owned bounded ring. `scrapbot.ui_action` resolves from the exact control or nearest layout ancestor and supplies optional project semantics without changing control mechanics. Readers use monotonic sequences and never consume entries destructively; project Luau/native adapters filter editor-origin events, while editor orchestration reads the same history through its own cursor.

The retained interaction pass derives a backend-neutral cursor intent from the topmost reusable control after applying project-canvas pointer inversion. The windowed renderer maps that intent to cached SDL system cursors; headless runs retain the same UI interaction behavior without initializing the platform cursor boundary.

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
