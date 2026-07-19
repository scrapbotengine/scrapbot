---
name: scrapbot-testing
description: Use when testing or verifying Scrapbot changes, especially scene persistence and authoring savepoints, lifecycle integrity, CLI behavior, generated Luau types, example projects, ECS rendering, WGPU smoke tests, headless framegrabs, PNG artifacts, documentation builds, or before committing.
---

# Scrapbot Testing

Use this skill whenever Scrapbot must build, load projects, analyze generated Luau types, execute ECS systems, render through current backends, or produce a visually verifiable artifact.

## Default Verification

Run the normal suite first:

```sh
mise test
git diff --check
```

`mise test` currently builds the CLI, checks `src/scrapbot`, runs all Odin package tests with `-all-packages`, checks the CLI version, validates `examples/minimal`, and runs the null backend.

In a multi-agent workflow, individual agents run the narrow checks for their owned files. The integration owner runs `mise test`, generated-example checks, documentation builds, and any required WGPU verification against the combined branch.

For narrower loops, select packages by ownership:

```sh
odin build src/scrapbot_cli -out:bin/scrapbot
odin check src/scrapbot -no-entry-point
odin test src/scrapbot/resources
odin test src/scrapbot/ecs
odin test src/scrapbot/render
bin/scrapbot help run
```

Use `mise test` for `src/scrapbot/script` or the full package tree because Luau tests require the native linker flags from `mise.toml`.

## Structured Diagnostics

Prefer `--json` for agent-driven CLI checks:

```sh
bin/scrapbot check examples/minimal --json
bin/scrapbot build examples/minimal --json
bin/scrapbot run examples/minimal --backend null --headless --no-hot-reload --frames 1 --json
```

JSON mode emits one versioned document on stdout. Use `ok`, diagnostic `code`, and documented `result` fields for assertions and branching. Treat diagnostic messages as human-readable context; do not match their exact text. Check `schema_version` before consuming the envelope, and fall back to human output only when the command has no structured mode.

Keep `run` bounded with `--frames`. Structured success confirms command and runtime behavior, but renderer changes still require the WGPU smoke or framegrab checks described below.

For CPU/RAM growth investigations, request the opt-in structured runtime report:

```sh
bin/scrapbot run examples/ecs-showcase --backend null --headless --no-hot-reload --frames 10000 --runtime-stats --json
```

Compare allocated-slot fields across `runtime_stats.early_storage`, `late_storage`, and `final_storage`; compare `allocator_early_bytes` with `allocator_late_bytes`; check `allocator_final_bytes`; and inspect the early/late frame timing ratio. Ignore `live_entities` when the workload intentionally oscillates. These are engine-owned signals; direct Luau, SDL, WGPU, driver, GPU, and OS allocations require separate tooling.

## Choose An Example

- Use `examples/minimal` for fast CLI, project loading, scheduling, Luau/Odin integration, null backend, and basic WGPU smoke tests.
- Use `examples/ecs-showcase` for geometry, materials, render reconciliation, batching, lighting, lifecycle-heavy ECS behavior, and visual renderer changes.
- Use `examples/ui-showcase` for retained ECS UI hierarchy, box-model layout, horizontal/vertical stacks, smooth clipped scroll areas, SDF-rounded backgrounds, pointer-styled buttons, MTSDF text, and overlay/framegrab changes. Use `--ui-script` for deterministic headless hover, active, focus, typing, scrolling, and editor workflows; do not rely on OS pointer automation.

Validate an example with:

```sh
bin/scrapbot check examples/minimal
bin/scrapbot check examples/ecs-showcase
bin/scrapbot check examples/ui-showcase
bin/scrapbot run examples/minimal --backend null --headless --no-hot-reload --frames 1
```

`scrapbot check` also regenerates `.scrapbot/types/scrapbot.d.luau`. After changing Luau APIs or component schemas, run it for every affected example and inspect the generated output. It is ignored engine state; do not hand-edit or commit it.

## WGPU Window Smoke

Windowed WGPU opens an SDL3 window and may require graphics-service approval on macOS:

```sh
bin/scrapbot run examples/minimal --backend wgpu --window --frames 3
```

Use `--frames` for automated smoke checks so the command returns. Without `--frames`, windowed mode runs until the window closes.

## Headless WGPU Framegrabs

Headless framegrab renders the same resource-backed ECS path into an offscreen texture, reads back the final frame, and writes a PNG:

After changing instance storage, batching, culling, shadows, indirect drawing, postprocessing, UI geometry retention, or WGPU bind layouts, run `mise test-gpu`. It renders an 81-instance stress fixture through compute visibility and `--cpu-culling`, validates structured `render_stats`, instance upload reuse, and unchanged-frame UI vertex reuse, rejects visually empty output, and requires byte-identical PNG output.

```sh
bin/scrapbot run examples/minimal --backend wgpu --headless --frames 2 --framegrab /tmp/scrapbot-framegrab.png
bin/scrapbot run examples/ecs-showcase --backend wgpu --headless --frames 20 --framegrab /tmp/scrapbot-showcase.png
bin/scrapbot run examples/ui-showcase --backend wgpu --headless --frames 2 --framegrab /tmp/scrapbot-ui.png
bin/scrapbot run examples/ecs-showcase --backend wgpu --editor --headless --frames 20 --framegrab /tmp/scrapbot-editor.png
bin/scrapbot run examples/ecs-showcase --backend wgpu --editor --headless \
  --ui-script tests/fixtures/ui/component-picker.json \
  --ui-dump /tmp/scrapbot-component-picker-tree.json \
  --framegrab /tmp/scrapbot-component-picker.png
```

Use `tests/fixtures/ui/component-picker.json` when changing component authoring, live component mutation, registry-driven discovery, namespace grouping, panel title actions, or component-menu rendering. It proves running-mode attachment/removal, Stop-time disposal, stopped-mode membership changes, picker hover feedback, and reusable title-icon button targeting through `target.part = "panel_action"`.

Use `tests/fixtures/ui/playback-authoring.json` when changing Play, Step, Stop, authoring baselines, dirty-state preservation, or world replacement. It creates an unsaved scene entity, runs a complete Play/Stop round trip, and asserts that the authored entity remains visible.

Use `tests/fixtures/ui/authoring-history.json` when changing Undo, Redo, Save, Revert, savepoint-based dirty state, or disk-scene restoration. It edits a scene Transform, traverses away from and back to the clean history cursor, reverts from disk, asserts the original value, and captures the complete transport group.

Use `tests/fixtures/ui/resource-inspector.json` when changing project-resource loading, material UUID resolution, inline resource inspection, or the resource-reference picker. It stops simulation, selects an authored material entity, opens the ECS-built resource menu, asserts known authored materials, and captures the menu tightly.

Use `tests/fixtures/ui/resource-browser.json` when changing the editor resource browser, resource selection, identity fields, usage reporting, or dedicated resource inspection. It stops simulation, semantically selects the resource-row occurrence of Icosphere, asserts its editable Name and Path fields, and captures the Resources panel tightly. Pair it with the structural lifecycle unit test when changing create, duplicate, rename, move, delete, Find Usage, or Undo/Redo.

Use `tests/fixtures/ui/resource-to-entity-selection.json` when changing editor selection ownership or inspector routing. It selects an authored resource, then the same-named scene entity, and proves that the entity inspector replaces the resource inspector.

Use `tests/fixtures/ui/resource-inputs.json` when changing inline resource input bindings or playback behavior. It edits one material channel through typing and another through whole-control scrubbing while simulation is running, waits through inspector refreshes, and asserts both live values.

Use `tests/fixtures/ui/editor-shortcuts.json` when changing editor visibility or transport command shortcuts. It drives the same editor keyboard input used by the platform, verifies Pause, resume, and the temporary pause caused by closing and reopening over a running game. Pair it with the state-machine and playback-restoration unit tests for Stop, Step, world replacement, and hidden close-time transitions.

Use `tests/fixtures/ui/playback-warning.json` when changing playback-mode chrome or disposable-edit messaging. It captures the complete editor root during playback so the top-bar tint, viewport frame, and status treatment can be reviewed together. Pair it with the transport unit test, which crosses transport states and asserts the exact status copy plus both playback and stopped style tokens.

Use `tests/fixtures/ui/system-profiler.json` when changing system registration, provenance, timing publication, or the editor profiler. It asserts the complete engine profiler topology in the ECS UI and captures the Systems panel.

Use `tests/fixtures/ui/scene-hierarchy.json` when changing Transform parenting, scene-tree composition, disclosure icons, hierarchy indentation, or reusable list/tree drag-and-drop. It performs center reparenting, cross-parent edge insertion, and a transformless-source reparent before capturing the complete Scene panel. Pair it with parser cycle/missing-parent tests, ECS world-transform resolution tests, the generic list drop/lander-line test, and editor parent/order Undo/Redo coverage.

Use `tests/fixtures/ui/ui-performance.json` for repeatable editor-UI performance comparisons. It selects the Sun inspector, sustains a numeric scrub across 30 input frames, and captures the Systems panel after the rolling profiler publishes. Pair it with `--ui-dump`, then read `__scrapbot_editor_system_time_2` from the dump for the `scrapbot.ui` average. Treat timings as same-machine before/after evidence; the deterministic hierarchy and no-refresh-during-scrub tests enforce the underlying retained traversal contract in CI.

The retained UI tests instrument layout and paint only under `ODIN_TEST`. Keep their large-tree node and edge visit assertions intact: they are the deterministic CI guard against quadratic child discovery, while the value-mutation matrix ensures already-attached component updates do not trigger structural synchronization. Do not replace either contract with a wall-clock threshold.

Framegrabs are losslessly compressed and preserve 1:1 pixels. The complete frame remains 1280×720. When a visual question concerns one control, label, gizmo, or panel, request a top-left-origin crop instead of passing the entire frame through image inspection:

```sh
bin/scrapbot run examples/ui-showcase --backend wgpu --headless --frames 2 \
  --framegrab /tmp/scrapbot-ui-panel.png \
  --framegrab-region 40,40,560,600
```

On macOS, this still creates a hidden SDL3 window internally for Metal adapter bootstrap. It therefore needs the same window-system approval as visible SDL runs. Do not add this command to the default `mise test` unless the environment can run it without GUI approval.

Verify the generated artifact:

```sh
file /tmp/scrapbot-framegrab.png
xxd -l 16 /tmp/scrapbot-framegrab.png
```

Expected basics:

- `file` reports `PNG image data, 1280 x 720, 8-bit/color RGBA`.
- `xxd` starts with `8950 4e47 0d0a 1a0a`.
- Visual inspection matches the selected fixture and changed behavior.

Use `view_image` only when the conclusion depends on visual inspection. Start with its default/high detail and one overview image per visual checkpoint. Do not request `original` detail for a complete frame by default. For a named pixel-level concern, generate the tightest useful 1:1 framegrab region and inspect that region at original detail. Reuse an existing artifact when the rendered state has not changed, and avoid emitting several near-identical screenshots in one turn.

For interactive UI bugs, prefer a semantic script plus `--ui-dump`. A script is a versioned JSON object with an `actions` array. Actions may `click`, `hover`, `scroll`, `type`, `drag` by `delta_x`/`delta_y` or toward a semantic `destination`, send a `key`, `wait`, `expect`, or select a `capture` target. Targets match UUID, entity name, or visible text and may choose a zero-based `occurrence`; the driver automatically reveals targets through clipped ancestor scroll areas. Use destination drags for reusable lists, trees, and other target-oriented gestures so layout changes do not invalidate pixel offsets. A target `capture` overrides full-frame output unless an explicit `--framegrab-region` was supplied. Inspect `driver_action_index`, `driver_action`, and `driver_target` in a failure dump before changing code.

Use `tests/fixtures/ui/reflected-inspector.json` to verify that a registry-driven field edit reaches project ECS state, marks stopped authoring dirty, and restores exactly through Undo. Extend its unit companion in `src/scrapbot/ui/ui_test.odin` when adding a new reflected field shape or specialized picker.

When reproducing or verifying an editor/UI interaction bug, read
[`references/ui-diagnostics.md`](references/ui-diagnostics.md) and follow its replay-dump-capture loop. Do not claim a visual fix from layout arithmetic or a successful process exit alone: assert the semantic state and inspect the smallest relevant 1:1 PNG.

For renderer changes, inspect the artifact for:

- Nonblank output, expected framing, and coherent depth ordering.
- Geometry topology, face winding, normals, and transforms.
- Material colors, lighting contrast, and point/directional light contributions.
- Stable layout and expected entity visibility across multiple frames.
- Complete editor chrome and a clipped live project viewport that fills all available center space when `--editor` is used.
- The invariant that a lit material with no ambient, directional, or point contribution renders black.
- Expected batching/resource sharing when frame statistics are relevant.

## What Counts As Tested

For ordinary code/docs changes:

- `mise test`
- `git diff --check`

For renderer, geometry, material, light, camera, or render-ECS changes, also run a relevant WGPU smoke:

- Window path: `--backend wgpu --window --frames 3`
- Headless artifact path: `--backend wgpu --headless --frames 2 --framegrab /tmp/scrapbot-framegrab.png`

For framegrab or PNG writer changes, run:

- `odin test src/scrapbot/render`
- the headless framegrab command
- `file`/`xxd` checks
- visual inspection with `view_image`

For generated Luau API or schema changes, run:

- `mise build`
- `bin/scrapbot check` for every affected example
- `mise test`
- review of generated declaration diffs

For public ECS UI component changes, run all three example checks and verify TOML parsing, Luau query/partial mutation, native payload round-tripping, lifecycle cleanup, and editor composition. Use the `scrapbot-ui-development` skill for the ownership checklist.

For documentation changes, build the website from its own directory:

```sh
cd docs-website
pnpm run build
```

For lifecycle or suspected CPU/RAM growth changes, also run:

```sh
mise test-soak
```

The soak parses Scrapbot's JSON result, compares allocated storage across early/late/final checkpoints, allows at most 64 KiB of engine-allocator growth and post-teardown retention, and uses a generous 1.5x late/early frame-cost threshold. Its frame count and thresholds can be steered through `SCRAPBOT_SOAK_FRAMES`, `SCRAPBOT_SOAK_MAX_ALLOCATOR_GROWTH`, `SCRAPBOT_SOAK_MAX_FINAL_ALLOCATOR_BYTES`, and `SCRAPBOT_SOAK_MAX_CPU_GROWTH`.

`mise test-sanitize` runs the full Odin package tree under AddressSanitizer on Linux. It is explicitly skipped on macOS because the current Odin and Apple sanitizer runtimes are incompatible.

## World Integrity And Lifecycle Reproduction

Call `ecs.validate_world_integrity` after the mutation under investigation when diagnosing entity, component-index, UUID-map, free-slot, active-set, dirty-queue, editor-back-reference, UI-hierarchy, or resource-handle corruption. Include `ecs.format_world_integrity_failure` in the assertion so the failing entity and related slot remain visible.

Tests validate every deferred command flush and playback restoration automatically. To enable the same checks in another diagnostic build, pass `-define:SCRAPBOT_WORLD_INTEGRITY_CHECKS=true`; do not enable it for ordinary release frames because it intentionally scans structural ownership.

`scrapbot.test_seeded_editor_lifecycle_preserves_world_integrity` runs 600 deterministic authoring and playback operations from seed `0x5c4a9b71d203e8f6`. Preserve the seed and failing step in new assertions. When fixing a lifecycle failure, strengthen the validator or sequence at the ownership boundary rather than adding a late array guard.

## Scene Persistence Reproduction

When changing Save, Revert, Undo/Redo savepoints, scene serialization, dirty candidate tracking, or authored/runtime provenance, preserve the contracts in `src/scrapbot/scene_persistence_test.odin`:

- `test_scene_persistence_scales_candidate_work_and_preserves_value_blocks` uses a 512-entity fixture and fixed seed `0x7a914e2dc6b8035f`. Keep candidate-work assertions based on unique dirty UUIDs, never wall-clock duration or whole-scene entity counts.
- `test_scene_persistence_write_failure_never_changes_original` and `test_scene_persistence_rejects_invalid_generated_toml_before_write` prove the last valid file survives both writer failure and invalid generated content.
- `test_scene_persistence_structural_roundtrip_covers_every_scene_component` is the schema-drift guard. Extend it whenever a scene component or serialized field is added.
- `test_scene_persistence_savepoints_roundtrip_through_undo_redo_and_revert` crosses the editor history clean cursor and disk boundary. Keep the checked-in `authoring-history.json` semantic fixture as the rendered editor companion.

For exact-text assertions, change only the intended UUID block, require a byte-identical second Save, preserve untouched comments/formatting, and assert that runtime/editor entities never reach disk. Use `save_scene_world_with_writer` only inside package tests to inject a failure; production callers must keep the atomic writer.

## Project Save Transaction Reproduction

When one Save can touch both scene and resource files, preserve the transaction contracts in `src/scrapbot/project/save_transaction_test.odin` and `src/scrapbot/project_save_test.odin`:

- Prepare and parse every candidate before the first destination changes; validate scene resource references against the complete candidate project state.
- Inject an ordinary error at every pre-commit filesystem checkpoint and require every original file plus all transaction markers, stages, and backups to be restored exactly.
- Inject a crash on both sides of the committed marker. Project recovery must roll backward before it and preserve the complete new file set after it.
- Exercise resource create, move, and delete explicitly. A move is one Delete plus one create-only Write; rollback restores the old path and removes the new path, committed recovery keeps only the new path, and create-only writes must reject existing destinations.
- Reload a jointly changed scene and resource registry, compare the authored values, and require a byte-identical repeated Save.

Do not weaken project atomicity to per-file atomic renames. Production editor and hot-reload Save paths must use `save_project_world`; `save_project_materials` and `save_scene_world` remain narrow wrappers for package-level compatibility and focused tests.

## Notes For Future Agents

- Prefer `mise test` over reconstructing the suite manually.
- Prefer versioned `--json` output over parsing human-readable CLI output.
- Keep GPU commands out of the default suite while they require GUI/window-system approval.
- Use `/tmp` for generated framegrabs and temporary test artifacts unless the user asks to keep them.
- Prefer structured diagnostics plus `file`/size checks before loading image pixels into the conversation.
- Preserve agent choice: use a full frame for composition, a 1:1 region for detail, and never downsample the only verification artifact.
- If a WGPU command fails in the sandbox with SDL display, XPC, or window-system errors, rerun it with approval rather than changing renderer code.
- Use enough frames to expose animated behavior, but keep automated runs bounded with `--frames`.
- When changing test expectations, update `README.md`, FDRs, TODO, or this skill if the testing contract changed.
