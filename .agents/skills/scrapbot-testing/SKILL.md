---
name: scrapbot-testing
description: Use when testing or verifying Scrapbot changes, especially CLI behavior, generated Luau types, example projects, ECS rendering, WGPU smoke tests, headless framegrabs, PNG artifacts, documentation builds, or before committing.
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
bin/scrapbot run examples/minimal --frames 1 --json
```

JSON mode emits one versioned document on stdout. Use `ok`, diagnostic `code`, and documented `result` fields for assertions and branching. Treat diagnostic messages as human-readable context; do not match their exact text. Check `schema_version` before consuming the envelope, and fall back to human output only when the command has no structured mode.

Keep `run` bounded with `--frames`. Structured success confirms command and runtime behavior, but renderer changes still require the WGPU smoke or framegrab checks described below.

## Choose An Example

- Use `examples/minimal` for fast CLI, project loading, scheduling, Luau/Odin integration, null backend, and basic WGPU smoke tests.
- Use `examples/ecs-showcase` for geometry, materials, render reconciliation, batching, lighting, lifecycle-heavy ECS behavior, and visual renderer changes.
- Use `examples/ui-showcase` for retained ECS UI hierarchy, box-model layout, horizontal/vertical stacks, SDF-rounded backgrounds, pointer-styled buttons, MTSDF text, and overlay/framegrab changes. Hidden framegrabs intentionally have no pointer interaction; verify hover/active paint selection with UI tests or a bounded visible-window smoke.

Validate an example with:

```sh
bin/scrapbot check examples/minimal
bin/scrapbot check examples/ecs-showcase
bin/scrapbot check examples/ui-showcase
bin/scrapbot run examples/minimal
```

`scrapbot check` also regenerates `types/scrapbot.d.luau`. After changing Luau APIs or component schemas, run it for every affected example and review the generated diffs. Do not hand-edit generated declarations.

## WGPU Window Smoke

Windowed WGPU opens an SDL3 window and may require graphics-service approval on macOS:

```sh
bin/scrapbot run examples/minimal --backend wgpu --window --frames 3
```

Use `--frames` for automated smoke checks so the command returns. Without `--frames`, windowed mode runs until the window closes.

## Headless WGPU Framegrabs

Headless framegrab renders the same resource-backed ECS path into an offscreen texture, reads back the final frame, and writes a PNG:

```sh
bin/scrapbot run examples/minimal --backend wgpu --headless --frames 2 --framegrab /tmp/scrapbot-framegrab.png
bin/scrapbot run examples/ecs-showcase --backend wgpu --headless --frames 20 --framegrab /tmp/scrapbot-showcase.png
bin/scrapbot run examples/ui-showcase --backend wgpu --headless --frames 2 --framegrab /tmp/scrapbot-ui.png
bin/scrapbot run examples/ecs-showcase --backend wgpu --editor --headless --frames 20 --framegrab /tmp/scrapbot-editor.png
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

Use `view_image` on the PNG when visual inspection matters.

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

For documentation changes, build the website from its own directory:

```sh
cd docs-website
pnpm run build
```

## Notes For Future Agents

- Prefer `mise test` over reconstructing the suite manually.
- Prefer versioned `--json` output over parsing human-readable CLI output.
- Keep GPU commands out of the default suite while they require GUI/window-system approval.
- Use `/tmp` for generated framegrabs and temporary test artifacts unless the user asks to keep them.
- If a WGPU command fails in the sandbox with SDL display, XPC, or window-system errors, rerun it with approval rather than changing renderer code.
- Use enough frames to expose animated behavior, but keep automated runs bounded with `--frames`.
- When changing test expectations, update `README.md`, FDRs, TODO, or this skill if the testing contract changed.
