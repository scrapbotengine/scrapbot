---
name: scrapbot-testing
description: Use when testing or verifying Scrapbot changes, especially CLI behavior, Odin package tests, WGPU renderer smoke tests, headless framegrabs, PNG artifacts, examples, or before committing changes in this repository.
---

# Scrapbot Testing

Use this skill whenever you need confidence that Scrapbot still builds, loads example projects, renders through the current backends, or produces verifiable framegrab artifacts.

## Default Verification

Run the normal suite first:

```sh
mise test
git diff --check
```

`mise test` currently builds the CLI, checks `src/scrapbot`, runs all Odin package tests with `-all-packages`, checks the CLI version, validates `examples/minimal`, and runs the null backend.

For narrower loops:

```sh
odin build src/scrapbot_cli -out:bin/scrapbot
odin check src/scrapbot -no-entry-point
odin test src/scrapbot/render
bin/scrapbot help run
```

Do not run `odin test src/scrapbot -all-packages` directly unless you also pass the Luau native linker flags from `mise.toml`; the script package links against the vendored Luau static libraries. Prefer `mise test` for full-package tests.

## CLI Smoke Tests

Use `examples/minimal` as the default project fixture:

```sh
bin/scrapbot check examples/minimal
bin/scrapbot run examples/minimal
bin/scrapbot run examples/minimal --backend wgpu
```

The final command should fail until `--window` or `--framegrab` is provided. That is intentional and verifies the WGPU backend does not silently pretend to run without an output target.

## WGPU Window Smoke

Windowed WGPU opens an SDL3 window and needs approval outside the normal sandbox on macOS:

```sh
bin/scrapbot run examples/minimal --backend wgpu --window --frames 3
```

Use `--frames` for automated smoke checks so the command returns. Without `--frames`, windowed mode runs until the window closes.

## Headless WGPU Framegrabs

Headless framegrab renders the WGPU cube scene into an offscreen texture, reads back the final frame, and writes a PNG:

```sh
bin/scrapbot run examples/minimal --backend wgpu --headless --frames 2 --framegrab /tmp/scrapbot-framegrab.png
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
- Visual inspection shows the example project's colored cube renderables on the dark clear color.

Use `view_image` on the PNG when visual inspection matters.

## What Counts As Tested

For ordinary code/docs changes:

- `mise test`
- `git diff --check`

For renderer or WGPU changes, also run at least one relevant GPU smoke:

- Window path: `--backend wgpu --window --frames 3`
- Headless artifact path: `--backend wgpu --headless --frames 2 --framegrab /tmp/scrapbot-framegrab.png`

For framegrab or PNG writer changes, run:

- `odin test src/scrapbot/render`
- the headless framegrab command
- `file`/`xxd` checks
- visual inspection with `view_image`

## Notes For Future Agents

- Prefer `mise test` over reconstructing the suite manually.
- Keep GPU commands out of the default suite while they require GUI/window-system approval.
- Use `/tmp` for generated framegrabs and temporary test artifacts unless the user asks to keep them.
- If a WGPU command fails in the sandbox with SDL display, XPC, or window-system errors, rerun it with approval rather than changing renderer code.
- When changing test expectations, update `README.md`, FDRs, TODO, or this skill if the testing contract changed.
