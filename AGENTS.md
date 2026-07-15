# Scrapbot Agent Guide

Scrapbot is an experimental, text-first game engine written in Odin with embedded Luau for project-local scripting. This file is the authoritative home for rules agents must follow before changing code. ADRs, FDRs, and skills are further reading, not replacements for these rules.

## Features

Please refer to the `README.md` for a high-level overview of the engine's features and roadmap. Detailed features, design decisions, and implementation details are documented in ADRs and FDRs in `docs/adr/` and `docs/fdr/`.

## Project Status

- This project is in super-early development.
- Breaking changes are 100% acceptable and we don't need to make changes backward-compatible unless specifically requested by the user.

## Worktrees And Multi-Agent Work

- Inspect `git status`, the current branch, and the relevant diff before editing. Existing changes belong to the user or another agent unless your task explicitly owns them.
- Preserve unrelated edits. Do not reset, overwrite, reformat, stage, or commit files outside your assigned scope.
- When coordinating multiple agents, partition work by ownership boundary and file set. Avoid assigning the same source file to multiple writers; give shared registries, generated files, documentation indexes, and integration tests to one integration owner.
- Give delegated tasks concrete acceptance criteria, allowed files, required records/skills, and verification commands. Ask each agent to report files changed, tests run, and unresolved risks.
- Treat agent output as a proposed change, not proof of correctness. The integrating agent reviews the combined diff, resolves cross-surface gaps, runs the appropriate integration checks, and owns the final commits.
- Use the orchestrator-provided worktree and branch. Do not create a nested worktree or switch branches unless the workflow explicitly assigns that responsibility.
- Keep commits coherent and run the tracked hooks. Never bypass validation with `--no-verify`.

## Architectural Invariants

- Built-in component changes are cross-surface changes. Audit shared types/defaults/validation, ECS storage and lifecycle, scene TOML, Luau queries and deferred mutation, generated Luau declarations, native ABI/wrappers, examples, tests, and public documentation.
- The editor is a first-party consumer of the public `scrapbot.ui_*` ECS components, not a second widget toolkit. Editor-only code may bind project meaning, selection, inspection, and history to generic interaction state; it must not own private versions of reusable controls, styles, layout behavior, or renderer mechanics. Read ADR-025 and use the `scrapbot-ui-development` skill for UI work.
- Project TOML, Luau, native Odin, and editor composition must produce and consume the same public UI component data. `scrapbot.ui_state` is renderer-owned and read-only.
- Renderer and UI membership changes use structural dirty queues, active sets, and component lifecycle hooks. Do not reintroduce complete-world reconciliation or storage-capacity scans into ordinary frames.
- Every entity has a stable project-wide UUID distinct from its editable name. Persistent references and UI parents use UUIDs, never names or transient storage indices.

## Documentation Ownership

- `README.md` is the feature/roadmap overview, `docs/adr/` records durable architecture decisions, and `docs/fdr/` records current feature behavior and rationale.
- `docs-website/` is the public user documentation. Update it in the same change when commands, project files, Luau/native APIs, editor behavior, rendering/testing workflows, or public UI behavior change.
- Prefer updating the canonical page and linking to it over duplicating exhaustive field lists. Build the site with `pnpm run build` from `docs-website/`.

## Agent Diagnostics

Prefer Scrapbot's structured CLI output when inspecting projects or verifying changes:

```sh
bin/scrapbot check <path> --json
bin/scrapbot build <path> --json
bin/scrapbot run <path> --frames <n> --json
```

- Treat `ok`, diagnostic `code`, and documented `result` fields as the automation contract.
- Branch on diagnostic codes and structured fields, never exact human-readable message text.
- Do not parse human CLI output when `--json` is available.
- Expect exactly one JSON document on stdout. Use `schema_version` before assuming an envelope shape.
- Keep automated runs bounded with `--frames`.
- Use a headless WGPU framegrab when correctness depends on rendered output; structured diagnostics do not replace visual verification.

## Odin Tooling

- Run `mise install` to provision the pinned Odin compiler, OLS language server, and `odinfmt` formatter.
- Format touched `.odin` files with `odinfmt <path> -w` before verification.
- Write one statement per line and use multiline control-flow bodies; `odinfmt` preserves semicolon-packed structure and cannot make compressed source readable by itself.
- Use `mise fmt-audit` to report formatting drift without modifying the worktree.
- The tracked pre-commit hook checks staged Odin blobs with `mise fmt-staged`. Never bypass it with `--no-verify`.
- Keep `ols.json` and `odinfmt.json` as the shared editor and formatting policy; do not replace them with editor-local defaults.
