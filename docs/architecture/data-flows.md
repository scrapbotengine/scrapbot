# Major Data Flows

**Last verified:** 2026-07-21

## Project load and world bootstrap

```text
project.toml + scene/resource files + source assets
        │
        ├─ fingerprint/import ──> versioned Texture/Model products ─┐
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

Native components register before Luau executes, allowing scripts to retrieve native handles. Asset import completes before runtime resource registration. Model roots then reconcile imported nodes and primitives into derived Transform/Geometry/Material ECS entities at bootstrap/reload; later root duplication, undo/redo, or resource replacement increments a model-instance revision and reconciles only after that structural signal. Scene validation occurs against the combined engine/native/Luau registry. Resource descriptions remain outside ECS; components store resolved runtime handles. Hot reload stages the replacement resource registry, world, script/native runtime, source set, and playback baseline independently; failure destroys the staged bundle, while success swaps the complete bundle atomically.

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

Input singletons are committed once before the schedule runs. Luau and native systems read the same immutable held/pressed/released snapshot and declare `scrapbot.keyboard_input` or `scrapbot.pointer_input` access without allocating synthetic entities or scanning entity storage.

Each native worker and the Luau runtime retain a private deferred-command buffer. A compact header stream preserves issue order while spawn, despawn, add-component, and remove-component payloads grow in separate typed arrays. Queued spawns and component additions pool only the custom/UI components actually present; schema-backed custom-component headers then reference separate Number, Vec2, Vec3, and Vec4 arrays containing only fields that were supplied. This keeps the fixed-capacity ABI staging structs at the extension boundary without retaining their unused capacity in the engine queue. Buffers start small, grow geometrically without an arbitrary command-count ceiling, merge with payload-index and field-range remapping in deterministic schedule order, and retain their per-array high-water capacities for reuse. Fixed limits apply to caller-owned ABI staging payloads, not to how many lifecycle commands a frame may produce or how much unused payload capacity each queued command reserves.

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
           compute cull + shadow + depth/world + bloom/composite
                                      │
                       retained UI streams + presentation
```

Cameras and bounded lights are compact frame inputs. Stable renderable membership and instance records are not re-extracted or uploaded without a mutation signal. WGPU reuses retained batch membership for Transform-only changes, uploads a compact position/rotation/scale/local-bounds record for each dirty slot, and expands only those slots into model matrices, normal matrices, and world bounds on the GPU before culling. When legal despawn/reuse churn leaves an authoritative retained slot inactive in the backend, the Transform path reconciles only that slot's static state before continuing. Render-list integrity checks enforce current entity generations and both entity-to-instance and slot-to-instance ownership. Material content revisions trigger a one-time dependent-instance pass only when material state changes. Static instance fields remain resident unless their own sources change.

## Performance diagnostics

```text
frame interval ──> fixed 50-frame rolling accumulator ──┐
WGPU timing / draw / visibility counters ──────────────┼─> revisioned snapshot every 5 frames
spawn/despawn-maintained entity-origin counts ─────────┘                │
                                                               public ECS UI panel
```

The editor formats values only when the snapshot revision changes. GPU timestamp values are asynchronous, and draw batches describe retained GPU-driven grouping rather than every API draw command in every pass.

## ECS UI and editor

```text
scene TOML / Luau / native Odin / editor composition
                         │
                  public ui_* components
                         │
       structural queue + project/editor revisions
                         │
     retained hierarchy → layout → interaction → paint
                         │
 uniform project-canvas/editor-viewport mapping
                         │
 read-only ui_state + independent GPU vertex streams
```

The editor adds transient editor-origin entities but uses the same components and mechanics as project UI. Editor-only code binds selection, history, project meaning, and commands to generic UI interaction. The project canvas keeps a uniform window-density scale inside the free-aspect game viewport; rendering, pointer inversion, and semantic diagnostic rectangles share that transform so embedded UI cannot be distorted or become spatially detached from interaction.

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
