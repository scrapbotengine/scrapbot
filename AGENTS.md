# Scrapbot Agent Guide

Scrapbot is an experimental, text-first game engine written in Odin with embedded Luau for project-local scripting. This file is the authoritative home for rules agents must follow before changing code. ADRs, FDRs, and skills are further reading, not replacements for these rules.

## Features

Please refer to the `README.md` for a high-level overview of the engine's features and roadmap. Detailed features, design decisions, and implementation details are documented in ADRs and FDRs in `docs/adr/` and `docs/fdr/`.

## Work Tracking

- `docs/TODO.md` is the concise, agent-readable backlog of current actionable engineering work. Read the relevant section before feature, refactor, performance, or hardening work so the active change accounts for known follow-ups and does not duplicate an existing task.
- Keep `docs/TODO.md` synchronized in the same change: add legitimate follow-up work discovered during implementation or review, rewrite partially completed items to describe only what remains, and remove completed items. Do not preserve checked-item history; Git owns completion history.
- Keep tasks short and link to an ADR, FDR, issue, benchmark, or public document when details or acceptance criteria do not fit on one line. Use the `todo-list` skill when maintaining the file.
- `README.md` owns the broad public roadmap; `docs/TODO.md` owns the narrower actionable engineering backlog; ADRs and FDRs own decisions and behavior. Link between them instead of duplicating exhaustive plans.
- The backlog is context, not implicit authorization to perform unrelated work. The user's current request and the active task scope take precedence.

## Project Status

- This project is in super-early development.
- Breaking changes are 100% acceptable and we don't need to make changes backward-compatible unless specifically requested by the user.

## Architectural Invariants

- Built-in component changes are cross-surface changes. Audit shared types/defaults/validation, ECS storage and lifecycle, scene TOML, Luau queries and deferred mutation, generated Luau declarations, native ABI/wrappers, examples, tests, and public documentation.
- The editor is a first-party consumer of the public `scrapbot.ui_*` ECS components, not a second widget toolkit. Editor-only code may bind project meaning, selection, inspection, and history to generic interaction state; it must not own private versions of reusable controls, styles, layout behavior, or renderer mechanics. Read ADR-025 and use the `scrapbot-ui-development` skill for UI work.
- Component inspector cards are runtime type-inspected. Their membership, titles, field rows, and generic controls must be derived from the live component registry plus the canonical typed payload (or the registry's dynamic schema for project/native components). Never add component-name branches or per-component panel builders. Storage adapters may locate canonical payloads, and validation or reusable controls may specialize by field type and semantics, but neither may define a component's panel shape.
- Project TOML, Luau, native Odin, and editor composition must produce and consume the same public UI component data. `scrapbot.ui_state` is renderer-owned and read-only.
- All systems that maintain derived state from ECS components, resources, or other authoritative data must be change-driven where feasible. Use component lifecycle hooks, structural dirty queues, compact active sets, monotonic revisions, and targeted in-place mutation so ordinary-frame work is proportional to actual changes. A stable frame must not perform complete-world or storage-capacity scans, rebuild an unchanged derived structure, hash a complete retained output, regenerate unchanged CPU/GPU data, or repeat an unchanged upload. Renderer and UI membership, extraction, hierarchy, paint, and GPU streams are current examples of this invariant; read ADR-024 before changing these paths.
- If a complete scan or rebuild is genuinely unavoidable, keep it outside ordinary stable frames or behind explicit invalidation. Document the reason, scope, and expected bound in the relevant ADR or FDR, and add deterministic tests proving both that unchanged frames do no derived work and that a single mutation touches only the smallest feasible affected set. Compact naturally frame-valued inputs and backend-required command encoding are acceptable exceptions; convenience is not.
- Every entity has a stable project-wide UUID distinct from its editable name. Persistent references and UI parents use UUIDs, never names or transient storage indices.

## Documentation Ownership

- `README.md` is the feature/roadmap overview, `docs/adr/` records durable architecture decisions, and `docs/fdr/` records current feature behavior and rationale.
- `docs/architecture/` is the present-tense source inventory for engine systems, components, resources/registries, runtime/authoring lifecycle, state ownership/invalidation, major data flows, and package responsibilities. Read its `INDEX.md` before architectural work and use the `scrapbot-architecture-inventory` skill whenever those inventories may change.
- Keep the architecture inventory updated in the same change as system/profile phases, component registration or lifecycle, project/runtime resource kinds, UUID/handle/version semantics, playback/persistence/hot-reload boundaries, authoritative/derived ownership, dirty queues/revisions/caches, frame/load/save/render/UI flows, or package-boundary changes. Run `node .agents/skills/scrapbot-architecture-inventory/scripts/check_inventory.mjs`; a passing name audit does not replace reviewing the prose relationships against source.
- Source code is authoritative for machine facts such as registered names, fields, lifecycle, phase order, and ownership. `docs/architecture/` owns the complete engineering directory—producers, consumers, invalidation, boundaries, and source/test anchors—while `docs-website/` owns public authoring syntax, fields/defaults, constraints, and examples. Link across those boundaries; do not maintain competing prose or hand-authored JSON/YAML catalogs of the same facts.
- Every registered engine component and fixed engine system phase must have a standardized per-entry architecture contract. Every public engine component must also appear in the canonical website component inventory; internal components must not appear there as authorable APIs. Keep these coverage rules executable in the architecture inventory audit.
- `docs-website/` is the public user documentation. Update it in the same change when commands, project files, Luau/native APIs, editor behavior, rendering/testing workflows, or public UI behavior change.
- `docs-website/src/content/docs/reference/components.md` is the canonical inventory of engine-provided components; `src/scrapbot/component/registry.odin` is its source of truth. Run `node .agents/skills/scrapbot-feature-development/scripts/check_component_docs.mjs` after component changes.
- Prefer updating the canonical page and linking to it over duplicating exhaustive field lists. Build the site with `pnpm run build` from `docs-website/`.

## Agent Diagnostics

Prefer Scrapbot's structured CLI output when inspecting projects or verifying changes:

```sh
bin/scrapbot check <path> --json
bin/scrapbot build <path> --json
bin/scrapbot run <path> --backend null --headless --no-hot-reload --frames <n> --json
bin/scrapbot run <path> --backend wgpu --editor --headless --ui-script <actions.json> --ui-dump /tmp/ui-tree.json --framegrab /tmp/ui.png --json
```

- Treat `ok`, diagnostic `code`, and documented `result` fields as the automation contract.
- Branch on diagnostic codes and structured fields, never exact human-readable message text.
- Do not parse human CLI output when `--json` is available.
- Expect exactly one JSON document on stdout. Use `schema_version` before assuming an envelope shape.
- Keep automated runs bounded with `--frames`.
- Use a headless WGPU framegrab when correctness depends on rendered output; structured diagnostics do not replace visual verification.
- For interactive UI/editor bugs, prefer a semantic `--ui-script` over manual clicks or guessed coordinates. Target controls by stable UUID, internal name, or visible text; pair it with `--ui-dump` and a target `capture` action so failures preserve both the reconciled tree and the smallest useful 1:1 PNG.

## Odin Tooling

- Run `mise install` to provision the pinned Odin compiler, OLS language server, and `odinfmt` formatter.
- Format touched `.odin` files with `odinfmt <path> -w` before verification.
- Write one statement per line and use multiline control-flow bodies; `odinfmt` preserves semicolon-packed structure and cannot make compressed source readable by itself.
- Use `mise fmt-audit` to report formatting drift without modifying the worktree.
- The tracked pre-commit hook checks staged Odin blobs with `mise fmt-staged`. Never bypass it with `--no-verify`.
- Keep `ols.json` and `odinfmt.json` as the shared editor and formatting policy; do not replace them with editor-local defaults.
