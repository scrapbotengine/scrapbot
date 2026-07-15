---
name: scrapbot-ui-development
description: Use when adding, changing, debugging, reviewing, or documenting Scrapbot ECS UI components, layout, controls, interaction state, styling, reconciliation, project TOML UI, Luau UI APIs, native UI payloads, or editor UI composition. Enforces one reusable public UI contract across projects and the editor.
---

# Scrapbot UI Development

## Start From The Contract

1. Read `docs/adr/ADR-025-use-one-public-ecs-ui-contract.md` and the relevant sections of `docs/fdr/FDR-007-ecs-ui.md` and `docs/fdr/FDR-008-editor-shell.md`.
2. Inspect `AGENTS.md`, the current diff, and the full component path before editing.
3. Decide whether the change affects component data, renderer mechanics, editor-only meaning, or composition. Put reusable behavior in the public component/runtime path; keep only project meaning and tool binding in editor adapters.

## Preserve One Public Surface

For every public `scrapbot.ui_*` field or component, audit the applicable owners:

- `src/scrapbot/shared/types.odin`: canonical structs, defaults, and validation.
- `src/scrapbot/component/registry.odin`: public schema metadata and generated declarations.
- `src/scrapbot/ecs/ui_components.odin` and `ecs/commands.odin`: typed storage, deferred mutation, free-slot reuse, string ownership, dirty marking, removal, and despawn.
- `src/scrapbot/project/parse.odin`: scene TOML decoding and validation.
- `src/scrapbot/script/`: Luau queries, partial updates that preserve omitted fields, deferred spawn/add/remove, and generated types.
- `src/scrapbot/extension_api/`, `native/`, and `extension/`: fixed-layout ABI payloads, conversions, defaults, helpers, and round-trip tests.
- `src/scrapbot/ui/`: generic layout, interaction, and paint behavior, plus editor composition that consumes those public components.
- Examples, README/TODO, FDR/ADR, and `docs-website/`.

`scrapbot.ui_state` is the exception: the renderer owns it and projects only read it. Use monotonic revisions for durable activation/change/submit/cancel edges; transient booleans describe the latest UI pass.

## Reuse Rules

- Build editor chrome from ordinary public components and typed ECS setters. Private helpers may apply a theme or compose a tree, but must not own duplicate widget storage, layout algorithms, interaction mechanics, or styles.
- Add a reusable component or field when editor behavior could benefit a project. Do not repair editor layout through role-specific post-layout geometry mutation.
- Start constructors from the canonical public defaults. Keep every style overridable per entity; a zero corner radius must produce square geometry where the component supports corners.
- Use UUIDs for parent relationships and durable selection. Never bind UI hierarchy to entity names or storage indices.
- Queue project/native structural changes until the system step completes. Do not mutate query membership during iteration.
- Reuse removed component slots and release owned strings on removal/despawn. Do not add per-frame scans over storage capacity or whole-world reconciliation.
- Preserve the current editor look unless the user requests a visual change. Theme values belong in editor composition; control geometry and style fields remain public.

## Verification

Format touched Odin files with `odinfmt`, then run narrow tests while iterating. Before handoff:

```sh
mise test
bin/scrapbot check examples/minimal --json
bin/scrapbot check examples/ui-showcase --json
bin/scrapbot check examples/ecs-showcase --json
git diff --check
```

Review generated `types/scrapbot.d.luau` rather than editing it directly. Build `docs-website/` when behavior or public fields change.

Add focused tests at each changed boundary. Maintain the registry reflection contract so canonical struct fields cannot silently disappear from public schemas. Cover partial Luau updates, native read/write conversion, parser validation, deferred structural mutation, lifecycle cleanup, and editor use of the public component.

For visual changes, use a bounded headless WGPU framegrab. Capture the smallest useful 1:1 region for a control-level question and inspect it at original detail; use a full frame only for composition. Compare against a baseline when the requirement is no visual regression.
