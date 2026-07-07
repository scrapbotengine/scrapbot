# FDR-003: Headless Validation and Test Runner

**Status:** Active
**Last reviewed:** 2026-07-07

## Overview

The headless validation and test runner lets users, CI systems, and agents check project correctness and script behavior without opening a window. It validates project metadata, script ECS declarations, the default scene, runs deterministic update frames, and exposes machine-readable validation details for editor and agent workflows.

**Odin migration note:** During the staged Odin rewrite, the Odin `test` command can discover test projects, validate manifests, replay script-visible input resources, route retained scene UI command/scroll input, consume editor-chrome pointer input before scripts observe it, replay editor play/pause and single-step buttons, replay first-pass editor entity-list/system-list/inspector scrolling, entity selection, inspector field selection, splitter dragging, scalar and vec3-lane inspector text editing, and translate gizmo dragging, run Luau-backed frame simulation, and evaluate first-pass final ECS field plus editor-state assertions. Rich editor-shell interactions such as native-backed fixtures still remain in the Zig implementation until those Odin subsystems land. The Odin `render`, `render-test`, and bounded hidden `run --backend wgpu` paths can now write first-pass image artifacts, metadata sidecars, and first-pass WebGPU editor chrome overlay vertices from ECS render data. The Odin `visual-test` command validates command shape, project loading, selected entity ids, expected/actual path safety, bounded Luau frame simulation, golden update, actual artifact output, image comparison, tolerance checks, metadata sidecars, and render extraction stats across the first-pass offscreen renderer paths. Odin visible software `run` now creates an SDL window, pumps quit/close events, drives the shared live-project frame tick for bounded and unbounded runs, presents software-rendered scene plus first-pass editor chrome pixels through an SDL texture, and routes first-pass editor pointer/keyboard/text input through the shared runtime input model. Visible WebGPU `run` also presents scene-derived frames, first-pass editor chrome overlays, and first-pass editor input routing through a persistent Odin `wgpu-native` surface context for bounded and unbounded runs, while the full editor window loop remains pending.

## Behavior

- `scrapbot check [path]` validates project metadata, project scripts, script-declared ECS types, schedule construction, and the default scene.
- `scrapbot check [path] --format=json` reports project metadata and the validated schedule batches, including phases, system ids, runner kinds, read/write sets, and before/after ordering declarations.
- `scrapbot step [path] [--frames N] [--dt seconds]` loads the default scene, runs startup once, runs the update schedule headlessly for the requested frame count, and reports final scene and simulation counts.
- `scrapbot step [path] --format=json` reports project metadata, final scene summary, simulation summary, schedule batches, and structured runtime diagnostics when a system fails.
- `scrapbot bench [path] [--frames N] [--dt seconds]` loads a project once, measures startup and repeated update frames without opening a window, and reports elapsed timing data plus headless render-planning statistics.
- `scrapbot bench [path] --format=json` reports benchmark timing, renderable count, render batch count, and UI primitive counts for scripts, agents, and CI logs.
- Automated scenario fixtures live under `tests/projects/` and use complete text-authored Scrapbot projects rather than sharing example projects.
- `scrapbot test [tests-path|project-path]` discovers text-authored test projects, reads each project's `test.scrapbot.toml`, steps the project headlessly, replays optional deterministic input frames, and checks declared ECS field expectations.
- `scrapbot test --format=json` reports each project case, simulation summary, per-field expected/actual assertion data, diagnostics, and a suite summary.
- `test.scrapbot.toml` may include `[[input.frame]]` records with one-based frame numbers, pointer position, wheel delta, viewport size, editor visibility, button state, keyboard state, and system profile count hints. These frames run through the same frame input, editor, scene UI scroll, command-event, and script-update routing used by live projects.
- `scrapbot render-test [path] [output.png] [--frames N] [--width PX] [--height PX] [--pixel-scale S]` renders the default scene offscreen, including UI overlays, reads the output image back, and verifies image shape, foreground coverage, visible components, and expected warm/cool color groups for automation. Multi-frame render tests run fixed `1/60` updates and verify the final frame.
- `scrapbot visual-test [path] [expected.png] [actual.png] [--frames N] [--width PX] [--height PX] [--pixel-scale S]` renders the default scene offscreen, compares the output image against a checked-in golden image with bounded tolerance, reports max channel delta, mean channel delta, and changed-pixel ratio, and returns non-zero when tolerances are exceeded. Multi-frame visual tests run fixed `1/60` updates and compare the final frame.
- `scrapbot visual-test --update [path] [expected.png]` deliberately refreshes a golden image from the current renderer output. Baseline updates are explicit and reviewable.
- Golden visual fixture projects live under `tests/golden/`. They are focused renderer fixtures, not user-facing examples.
- `SCRAPBOT_LEAK_CHECK=1` enables an internal engine heap leak guard for bounded CLI validation commands. It checks Scrapbot-owned Zig allocations and fails the command when command-scoped allocations leak.
- Future headless test commands can exercise scene and script live reload deterministically.
- Users can run project validation without initializing graphical presentation.
- Validation failures produce command-line diagnostics and non-zero process exit codes.
- Commands return appropriate process exit codes for automation.
- Headless commands avoid creating or mutating source files unless the command explicitly performs a repair, import, or generation action.

## Design Decisions

### 1. Make validation a core runtime capability

**Decision:** Project validation is part of the engine binary, not an external lint script.
**Why:** Interactive and headless modes need identical rules. It follows ADR-003.
**Tradeoff:** The engine must keep validators available without depending on editor-only systems.

### 2. Keep headless mode independent from presentation

**Decision:** Validation and tests run without requiring a window or GPU surface.
**Why:** CI and agent workflows need reliable execution in non-graphical environments. It follows ADR-003 and ADR-005.
**Tradeoff:** Some rendering behavior requires separate snapshot or backend-specific tests.

### 3. Prefer offscreen render assertions for visual checks

**Decision:** The broad visual verification command uses offscreen PNG output by default and pixel analysis instead of screenshotting a headful window.
**Why:** Offscreen rendering is easier to run in agent and CI workflows, and parsing the output artifact can catch regressions like missing foreground content or collapsed multi-object renders.
**Tradeoff:** Pixel analysis is still coarse and does not replace targeted golden-image or semantic render tests.

### 4. Add focused golden visual fixtures for renderer-sensitive output

**Decision:** Golden visual tests use complete text-authored projects under `tests/golden/`, checked-in PNG baselines, explicit `--update` regeneration, and tolerant image comparison instead of byte-for-byte equality.
**Why:** Renderer-sensitive features such as postprocess, UI layout, editor chrome, shadows, and clipping need stronger regression checks than foreground coverage. Keeping each fixture as a normal project preserves the same source-text workflow and startup behavior as other tests.
**Tradeoff:** Golden fixtures can still vary across graphics backends and GPUs, so they should stay focused, small, and tolerance-based. Broad example smoke coverage remains on `render-test`.

### 5. Add deterministic stepping and manifest assertions before full test scripting

**Decision:** Script and interaction behavior tests use a small `test.scrapbot.toml` manifest with frame count, timestep, optional deterministic input frames, and ECS field equality assertions instead of introducing a full test scripting DSL.
**Why:** Agents and CI need a small, reliable way to prove script systems, retained UI routing, and editor/game input ownership mutate ECS state and surface runtime diagnostics. Keeping the replay frames and assertions text-first makes them easy to inspect and patch. This follows ADR-003 and ADR-006.
**Tradeoff:** The manifest currently supports direct component field equality and frame-level input replay, not arbitrary predicates, setup/teardown hooks, platform event fuzzing, or multi-scene flows.

### 6. Keep gameplay test fixtures separate from examples

**Decision:** Game-shaped automated fixtures live in `tests/projects/`, not under `examples/`.
**Why:** Examples are user-facing smoke projects, while tests need purpose-built scenes and scripts that can change to cover edge cases without implying supported sample content.
**Tradeoff:** Some project files are duplicated between examples and tests until package/shared-fixture tooling exists.

## Related

- **ADRs:** ADR-001, ADR-003, ADR-005, ADR-006, ADR-009
- **FDRs:** FDR-001, FDR-002, FDR-004, FDR-005, FDR-006, FDR-010

## Open Questions

- Should snapshot rendering be part of validation, testing, or a separate command?
