# Runtime and Authoring Lifecycle

**Last verified:** 2026-07-21

This matrix records which authority changes at each major boundary. “World replacement” means a validated next world is built before the active world is destroyed and rebound. “Targeted mutation” means stable slots and retained consumers update from dirty queues/revisions.

## Lifecycle matrix

<!-- inventory:lifecycle-boundaries:start -->
| Boundary | Trigger | ECS world | Resource registry | Luau/native runtime | Derived UI/render state | Failure/rollback contract |
| --- | --- | --- | --- | --- | --- | --- |
| Project load | `scrapbot run`, check/build paths needing a full project | Parse/validate scene, build scene-origin entities with stable UUIDs, reconcile imported Model roots into derived runtime children, bootstrap structural/render/UI dirtiness | Ensure Texture/Model products; register built-ins, fonts, textures, models, generated model subresources, authored materials and LOD geometry; resolve ECS handles | Build native extensions when needed, register engine/native/project components, initialize shared deferred-command storage even when Luau is absent, execute Luau when present, validate world | UI/render consumers bootstrap from explicit initial dirtiness | Abort before renderer loop; atomic importer writes retain prior valid products |
| Scene entity creation | Editor `+`, duplicate, structural Undo/Redo | Create scene-origin entity with a new/stored UUID and scene order; add authored components through authoring snapshots | Existing resource handles are resolved into reference components | No runtime/code reload | Exact UI/render membership and editor browsers become dirty | Failed operation leaves history/source baseline unchanged |
| Runtime spawn | Deferred Luau/native command | Apply after system iteration; create runtime-origin UUID/entity, attach payload components, publish structural dirtiness | Payload may contain already-resolved generational handles | Command buffer preserves query safety and deterministic application order | Exact render/UI membership reconciles after command application | Invalid/stale commands are rejected or ignored without corrupting active indexes |
| Component add/remove/value mutation | Editor, Luau/native writeback, deferred command | Typed storage mutation bumps component revision and exact structural/render/UI signals | Resource-reference changes validate/replace handles; resource content itself remains registry-owned | Writes require declared access; structural changes remain deferred during scheduled iteration | Targeted retained slots/hierarchy/layout/paint/cache records update | Validation failure rejects mutation or authoring transaction |
| Despawn | Deferred command or editor structural operation | Mark exact consumers dirty, detach Transform children, remove UUID map entry, release component/custom/UI/render slots, increment entity generation, recycle entity index | Registry resources outlive entity references | Scheduled iteration is protected by deferred command application | UI subtree/state and render instance are released; browsers refresh from revisions | Stale entity generation makes the command a no-op |
| Enter Play | Play from stopped authoring | Capture scene-origin entity snapshots and component revisions; begin disposable simulation from current in-memory authored state | Capture authored Material base color and emissive values by UUID | Keep loaded code/runtime and schedule; simulation becomes active | Editor indicates playback; ordinary derived state remains retained | Baseline capture must succeed before playback begins |
| Pause | Pause during playback | Preserve current simulated ECS values; no simulation delta advances | Preserve current runtime resource values | Runtime stays loaded; scheduled project systems do not advance | Editor/UI/render frames may continue for inspection | No persistence boundary |
| Step | Step while paused | Advance exactly one simulation delta, then remain paused | Apply resource mutations produced by that step | Execute one scheduled project-system frame | Reconcile only changes produced by the step | System error aborts the frame through normal runtime error handling |
| Stop | Stop during playback | Build a world from the in-memory baseline, restore resolved Geometry/Material handles and component revisions, validate, replace active world, rebind runtime | Restore captured authored Material values by UUID; increment versions only on changed content | Keep Luau/native runtime and compiled code loaded | World replacement bootstraps new exact memberships; editor preserves valid selection where possible | Validate next world before destroying active world |
| Save | Explicit stopped-mode Save | Serialize only dirty scene UUID candidates against disk baseline | Prepare create/write/delete operations for dirty authored resource UUIDs | No runtime/code reload | Mark authoring transactions clean only after commit succeeds | Validate candidate references, then use recoverable multi-file commit; failure leaves sources/history dirty |
| Revert | Explicit stopped-mode Revert | Reload scene from disk, validate against current registry/runtime schema, replace world and rebind runtime | Reload authored materials/LOD geometry from disk; deactivate disappeared entries by generation/version | Keep existing Luau/native runtime and schedule | Rebuild derived membership from replaced world; clear/repair editor authoring state and selection | Parse/register/validate next state before active world replacement where supported |
| Script-only hot reload | Script file stamp changes alone | Keep active world and entity identity | Keep registry resources | Build replacement Luau/native registration state from script path; on success replace/rebind runtime and invalidate schedule | Component/system registry revisions refresh affected editor views | On failure restore/reload last-good script runtime and keep active world |
| Project/world hot reload | Project, scene, asset, resource, extension binary/source stamp changes | Build and validate a next world from disk, reconcile Model-derived children, then replace active world | Ensure imports; re-register fonts/textures/models/materials/LOD geometry in stable slots; increment versions/generations/topology as required | Rebuild native extensions and script runtime, then atomically replace runtime/extension/schedule ownership | New world bootstraps structural/render/UI state; backend caches follow resource revisions | Failed imports preserve product files; failed replacement destroys candidate world/runtime and retains/restores the last-good runtime |
| Shutdown | Renderer loop exits or command fails | Destroy world storages, maps, strings, snapshots, and dirty queues | Destroy cloned geometry/material/font data and registry arrays | Destroy Luau runtime, extension libraries/source sets, executor, command buffers | Destroy UI retained state, renderer/backend resources, platform window | Defers unwind ownership in reverse construction order |
<!-- inventory:lifecycle-boundaries:end -->

## Origin and persistence rules

| Entity/resource origin | Included in playback baseline | Saved to project | Stop behavior |
| --- | --- | --- | --- |
| Scene entity | Yes | Yes, when changed while stopped and explicitly saved | Restored to captured in-memory state |
| Runtime entity | No | No unless explicitly converted/kept by an authoring operation | Disappears when baseline world replaces playback world |
| Editor entity | No | Never | Reconciled by editor composition around world replacement |
| Authored project Material | Base color and emissive captured | Yes, by dirty resource UUID | Captured base color and emissive restored by UUID |
| Authored LOD Geometry | Referenced by scene baseline | Existing source remains authoritative; inline authoring is currently limited | Registry entry/handle remains; world reference is restored |
| Authored Texture/Model | Referenced by Material/Model-root UUID | Source declaration and asset remain authoritative | Registry product remains; Model-derived children are reconciled with the restored world |
| Transient/built-in runtime resource | Referenced only through captured scene handles where applicable | No | Registry lifetime continues; captured handles are restored if valid |

## Boundary invariants

- **Stable identity:** Persistent entity/resource references are UUIDs. Runtime entity/resource handles are generational and never serialized as authority.
- **Deferred structure:** Scheduled systems do not mutate structural storage while queries are iterating; command buffers apply afterward in deterministic order.
- **Optional scripting:** A project may run only native systems. The runtime still owns initialized shared command storage because native batches merge deferred mutations through the same application boundary as Luau.
- **Change-driven derivation:** Ordinary frames consume dirty queues, active sets, and revisions. Full rebuilds belong to explicit world/bootstrap/reload boundaries.
- **Stopped authoring:** Undo/Redo and dirty candidates describe in-memory authored state. Only explicit Save changes project files.
- **Disposable playback:** Running/paused simulation changes are temporary. Stop restores the Play baseline without loading code or disk state.
- **Disk authority:** Revert and project/world hot reload are the boundaries that reread scene/resource source files.
- **Transactional replacement:** Construct and validate replacement state before destroying active world/runtime ownership whenever the boundary permits it.
- **Selection safety:** Editor selection is UUID-based and must be cleared or rebound after world replacement; transient indexes must never survive replacement as references.

## Primary implementation and tests

| Concern | Source | Tests |
| --- | --- | --- |
| Project parse/load and resource-reference validation | `project/project.odin`, `project/parse.odin`, `project/resources.odin` | `project/project_test.odin`, `check_project_test.odin` |
| World bootstrap and structural dirtiness | `ecs/world.odin` | `ecs/world_test.odin`, `ecs/integrity_test.odin` |
| Deferred spawn/despawn/component mutation | `ecs/commands.odin`, `script/commands.odin` | `script/commands_test.odin`, `ecs/world_test.odin` |
| Native-only project runtime | `script/script.odin`, `hot_reload.odin`, `scrapbot.odin` | `script/script_test.odin`, `examples/ecs-stress` bounded run |
| Editor authoring/history | `ui/editor_authoring.odin`, `ecs/authoring.odin` | `ui/ui_test.odin`, `ecs/editor_test.odin` |
| Play/Stop baseline | `playback.odin`, `render/render.odin` | `playback_test.odin`, `render/render_test.odin` |
| Save/Revert | `project_save.odin`, `scene_serialize.odin`, `scene_structural_save.odin`, `project/save_transaction.odin` | `project_save_test.odin`, `scene_save_test.odin`, `scene_persistence_test.odin`, `project/save_transaction_test.odin` |
| Hot reload and last-good replacement | `hot_reload.odin` | `hot_reload_test.odin`, `runtime_reset_test.odin` |

See [Resources and registries](resources.md), [Major data flows](data-flows.md), [State ownership](state-ownership.md), and [FDR-008](../fdr/FDR-008-editor-shell.md).
