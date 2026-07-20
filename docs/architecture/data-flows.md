# Major Data Flows

**Last verified:** 2026-07-20

## Project load and world bootstrap

```text
project.toml + scene/resource files
        │
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

Native components register before Luau executes, allowing scripts to retrieve native handles. Scene validation occurs against the combined engine/native/Luau registry. Resource descriptions remain outside ECS; components store resolved runtime handles.

## Simulation and scheduled mutation

```text
playback transport → simulation delta → cached schedule plan
                                         │
                      non-conflicting native batches (parallel)
                                         │
                              Luau systems (serial barriers)
                                         │
                             per-system command buffers
                                         │
                          deterministic command application
                                         │
                typed storage + structural/render/UI dirty signals
```

Queries start from the smallest applicable custom-component active set. Systems declare reads/writes; structural changes are deferred until iteration finishes.

## Rendering

```text
typed ECS/resource mutation
        │
        ├─ membership/resource eligibility ─> structural render queue
        └─ Transform/value mutation ─────────> exact extraction queue
                                                │
                                  retained backend-neutral render list
                                      │
                           dirty stable render slots
                                      │
              static instance writes or compact transform writes
                                      │
                  dirty-only GPU transform expansion
                                      │
                      persistent WGPU instance/draw database
                                      │
           compute cull + shadow + depth/world + bloom/composite
                                      │
                       retained UI streams + presentation
```

Cameras and bounded lights are compact frame inputs. Stable renderable membership and instance records are not re-extracted or uploaded without a mutation signal. WGPU reuses retained batch membership for Transform-only changes, uploads a compact position/rotation/scale/local-bounds record for each dirty slot, and expands only those slots into model matrices, normal matrices, and world bounds on the GPU before culling. Static instance fields remain resident unless their own sources change.

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
 read-only ui_state + independent GPU vertex streams
```

The editor adds transient editor-origin entities but uses the same components and mechanics as project UI. Editor-only code binds selection, history, project meaning, and commands to generic UI interaction.

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

Play/Step capture an in-memory authoring baseline. Running/paused mutations are disposable. Stop restores the in-memory baseline without reloading code; Revert rebuilds authoring state from disk.

See [FDR-001](../fdr/FDR-001-runtime-cli.md), [FDR-005](../fdr/FDR-005-system-scheduling.md), [FDR-007](../fdr/FDR-007-ecs-ui.md), [FDR-008](../fdr/FDR-008-editor-shell.md), and [FDR-009](../fdr/FDR-009-project-resources.md).
