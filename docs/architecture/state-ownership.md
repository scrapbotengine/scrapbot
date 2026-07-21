# State Ownership and Invalidation

**Last verified:** 2026-07-21

Scrapbot separates authoritative project/runtime state from derived indexes, caches, render data, and editor views. A derived owner must update from explicit lifecycle or revision signals where feasible; stable frames must not rediscover unchanged state.

| State | Owner/source | Authority | Invalidation or lifetime |
| --- | --- | --- | --- |
| Project configuration, scene TOML, resource files, scripts, native source, assets | Project directory | Persistent authored source | Explicit Save/Revert, project load, or hot-reload file stamps. |
| Component definitions and IDs | `component.Registry` | Runtime schema authority | Engine bootstrap plus native/Luau registration; registry revision changes on registration/replacement. |
| Luau/native systems and cached Luau queries | `script.Runtime`, `native.Extension_Set` | Runtime execution registries | Hard-capped heap-backed buffers are allocated during runtime/extension initialization, transferred with successful hot-reload replacement state, and released by their owning destroy procedures. |
| Compiled native chunk plans | Each `native.Native_System` | Derived query/storage/field resolution | Bounded cache keyed by chunk terms and bindings; invalidated by World UUID, component-registry revision, newly appearing storage families, or extension-set replacement. Ordinary component membership churn retains the plan. |
| Entity identity and component values | `shared.World` / `ecs` | Active runtime authority | Typed ECS mutation, deferred command application, playback restore, or world replacement. |
| Frame time | `world.time` | Current runtime resource | Advanced once per permitted simulation step. |
| Geometry/material descriptions and handles | `resources.Registry` | Runtime shared-resource authority | Project resource load/edit/hot reload; generational handles and content/topology versions expose changes. |
| Authoring history and dirty UUID candidates | Editor UI state | In-memory authoring authority until Save/Revert | One transaction per completed gesture or structural operation; playback mutations remain disposable. |
| Retained UI hierarchy, layout, interaction, and paint commands | `ui.State` | Derived from public UI ECS components | Structural dirty queue plus independent project/editor layout and paint revisions. |
| `scrapbot.ui_state` components | UI reconciler | Derived, renderer-owned | Targeted interaction-dirty queue and retained node state; project code reads only. |
| Render-instance membership and retained render list | ECS render extraction | Derived from Transform/geometry/material/shadow membership and resource resolution | Structural dirty queue, exact render-mutation queue, and resource revisions. |
| GPU compact transform stream, expanded instance table, draw database, visibility, indirect args, pipelines, resource caches | WGPU backend | Derived backend state | Exact dirty render slots update compact transform inputs or static fields; a dirty-only compute pass expands matrices and bounds before culling. Batch-key/topology revisions, geometric capacity growth, and backend lifetime govern full rebuilds. |
| Project/editor/overlay UI vertex buffers | WGPU backend | Derived from UI output streams | Independent monotonic stream revisions; stable streams retain CPU/GPU buffers. |
| System profiler snapshot | Root runtime | Derived diagnostic state | Samples every frame, rolls over 50 frames, publishes every five frames. |
| Performance diagnostics snapshot | Renderer/root runtime | Derived diagnostic state | Wall-clock frame-interval and active-CPU duration samples roll independently over 50 frames; renderer and mutation-maintained world counters publish every five frames under one revision. |
| Live entity origin counters | ECS world | Derived from entity lifecycle | Incremented on spawn and decremented on despawn; diagnostics read them without scanning entity capacity. |
| Editor browsers and inspector snapshots | Editor UI composition | Derived tooling view | The entity browser contains authored entities plus an explicitly selected runtime entity. Selection or explicit structural invalidation rebuilds it; the 5 Hz running-value cadence refreshes inspector values without rematerializing browser rows. Stopped values remain change-driven, focused inputs retain staged text, and active scrubs defer unrelated refresh. |
| Generated Luau declarations and native build products | `.scrapbot/` and build directories | Derived products | Regenerated from schemas/source and never hand-edited as authority. |

## Stable-frame invariant

An ordinary unchanged frame must not:

- scan complete entity/component storage to rediscover membership;
- rebuild an unchanged retained hierarchy, render list, draw database, or UI paint stream;
- hash complete output merely to learn that it did not change;
- regenerate unchanged CPU/GPU vertices or instance records;
- upload unchanged buffers.

Ordinary Transform value writes enqueue exact render extraction only. Component membership, resource binding, and render eligibility changes additionally enqueue structural reconciliation. Runtime slot and scene-order allocation are monotonic or free-list based and must not scan historical entity capacity per spawn.

Accept full bootstrap/rebuild work at explicit boundaries such as initial world construction, world replacement, resource topology changes, or geometrically growing backend storage. Document any new stable-frame exception in the relevant ADR/FDR and protect it with deterministic work counters rather than wall-clock thresholds.

See [ADR-024](../adr/ADR-024-update-derived-ecs-state-from-structural-changes.md), [ADR-030](../adr/ADR-030-identify-project-resources-by-uuid-outside-the-ecs.md), and [ADR-034](../adr/ADR-034-keep-gpu-visibility-backend-owned.md).
