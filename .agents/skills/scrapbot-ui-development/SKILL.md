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
- Compose panel title controls from ordinary direct-child `ui_button` entities with public icon and `panel_action` fields. Never add a singular close/remove payload, hit-test path, or paint path to `ui_panel`; multiple title actions must remain possible.
- Keep reusable interaction mechanics semantic-free. Emit engine-internal generic activation/change events from the shared UI pass for editor orchestration, and expose project-observable edges through public `ui_state` revisions; do not dispatch editor commands from button, panel, list, input, or checkbox mechanics.
- Share popup ancestry, placement, flip, and viewport-clamping helpers across consumers. Role-specific popup content may differ, but it must not duplicate geometry or containment algorithms.
- Add a reusable component or field when editor behavior could benefit a project. Do not repair editor layout through role-specific post-layout geometry mutation.
- Start constructors from the canonical public defaults. Keep every style overridable per entity; a zero corner radius must produce square geometry where the component supports corners.
- Use UUIDs for parent relationships and durable selection. Never bind UI hierarchy to entity names or storage indices.
- Queue project/native structural changes until the system step completes. Do not mutate query membership during iteration.
- Reuse removed component slots and release owned strings on removal/despawn. Do not add per-frame scans over storage capacity or whole-world reconciliation.
- Preserve the current editor look unless the user requests a visual change. Theme values belong in editor composition; control geometry and style fields remain public.
- Derive every component inspector card at runtime from live registry membership and its canonical typed payload. Odin-backed payloads use runtime struct-field inspection; project/native dynamic components use their registry schema as runtime type metadata. Do not add component-name branches, field lists, or per-component panel builders. Storage-kind adapters may locate payloads, validators may enforce component invariants, and reusable controls may specialize by field type or semantics, but none may own panel composition. Marker payloads naturally produce title-only cards; derived and unsupported values remain visible and read-only.
- Treat `component.Registry` storage kind and lifecycle as the canonical membership contract. Editor pickers and structural history must not maintain parallel component enums or authorability switches; component add/remove should snapshot and mutate only the affected storage.

## Verification

Format touched Odin files with `odinfmt`, then run narrow tests while iterating. Before handoff:

```sh
mise test
bin/scrapbot check examples/minimal --json
bin/scrapbot check examples/ui-showcase --json
bin/scrapbot check examples/ecs-showcase --json
git diff --check
```

Review generated `.scrapbot/types/scrapbot.d.luau` rather than editing it directly. Build `docs-website/` when behavior or public fields change.

Add focused tests at each changed boundary. Maintain the registry reflection contract so canonical struct fields cannot silently disappear from public schemas. Cover partial Luau updates, native read/write conversion, parser validation, deferred structural mutation, lifecycle cleanup, and editor use of the public component.

For visual changes, use a bounded headless WGPU framegrab. Capture the smallest useful 1:1 region for a control-level question and inspect it at original detail; use a full frame only for composition. Compare against a baseline when the requirement is no visual regression.

For interactive editor or project UI changes, use the semantic replay driver described in
`.agents/skills/scrapbot-testing/references/ui-diagnostics.md`. Prefer selectors by UUID or stable entity name; use visible text plus `occurrence` only when that is the public behavior under test. Add an `expect` action for the interaction state and a `capture` action for the exact control or panel, then inspect both the final tree dump and the target-cropped PNG.
