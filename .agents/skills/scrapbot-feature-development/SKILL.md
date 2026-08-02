---
name: scrapbot-feature-development
description: Use when adding, changing, documenting, or auditing Scrapbot engine features, public APIs, ECS components, rendering, scripting, native extensions, examples, or project tooling. Covers cross-surface implementation, component documentation, generated types, and verification expectations.
---

# Scrapbot Feature Development

## Before Editing

1. Read the relevant roadmap section in `README.md`, open items in `docs/TODO.md`, and related ADRs/FDRs.
2. Trace the existing implementation end to end before choosing a design. Prefer established package boundaries and public APIs.
3. Call out material choices when multiple user-visible or architectural options remain. Breaking changes are acceptable, but accidental surface divergence is not.
4. Inspect the worktree and assigned scope. In multi-agent work, keep writers file-disjoint and leave shared registries, generated files, indexes, and integration checks to an explicit integration owner.
5. Read `docs/architecture/INDEX.md` and use the `scrapbot-architecture-inventory` skill when the work changes systems, components, ownership or invalidation, major data flows, or package responsibilities.

## Public Surface Audit

For every feature, decide explicitly which layers it affects:

- Core Odin implementation and ECS/runtime behavior.
- Luau runtime bindings and generated Luau declarations.
- Project-local Odin extension wrapper and raw extension ABI.
- Scene/project file parsing and validation.
- Standalone project-resource schemas, UUID references, registry lifetimes, and hot reload.
- CLI behavior and diagnostics.
- Example projects.
- README, TODO, ADRs, FDRs, and documentation website.

Do not assume every feature belongs on every surface. When one surface intentionally trails another, record that decision or follow-up rather than overlooking it.

For project-resource work, keep persistent identity separate from runtime storage: authored resources live outside ECS, scene/project files reference stable UUIDs, registries expose generational handles and versions, and ECS components hold resolved handles. Audit recursive discovery, duplicate/reference validation, disappearance/reappearance, packaging, hot reload, editor create/duplicate/rename/move/delete, reference-aware deletion, Save/Revert/Undo/Redo, and the distinction between authored and transient runtime resources. Lifecycle edits remain in-memory authoring until explicit Save; Save must derive create/write/delete operations from the disk baseline and commit them through the recoverable project transaction.

Project-resource, playback, persistence, world-replacement, and hot-reload changes must update `docs/architecture/resources.md` and/or `docs/architecture/lifecycle.md`. Record actual rollback boundaries: do not describe a replacement as transactional when a registry or other owner mutates before candidate validation and is not restored on failure.

For ECS UI work, also use the `scrapbot-ui-development` skill. The editor must remain a consumer of the public UI contract, and a public field is incomplete until every applicable authoring and runtime surface agrees.

For spatial hierarchy work, keep `scrapbot.transform.parent` UUID-based and local TRS as the only authored pose. Keep display order independent from live ECS storage handles; audit scene-block ordering, structural Save, and Undo/Redo when adding hierarchy reorder behavior. Also audit scene validation, Luau and native writeback, world-transform consumers (render instances, cameras, lights, picking, and gizmos), cycle rejection, parent removal, and world-pose-preserving editor reparent Undo/Redo. Use `tests/fixtures/ui/scene-hierarchy.json` for the visual tree companion; semantic drags can target the top/center/bottom of destination rows.

## Generated Luau Types

When changing built-in components, Luau APIs, query types, or component schemas:

1. Update the canonical type generator in `src/scrapbot/component/luau_types.odin`.
2. Build the CLI.
3. Run `bin/scrapbot check <example>` for every affected example.
4. Run `mise luau-workspace-types` when an example schema or shared Luau API changes. It refreshes the tracked repository-wide declaration aggregate used by the root VS Code workspace; project-local generated state remains ignored and must not be hand-edited or committed.
5. Inspect generated `.scrapbot/types/scrapbot.d.luau` output and run the Luau analyzer through the normal test suite.

Never hand-edit generated example declarations without changing their generator.

## Verification And Documentation

- Add focused unit and integration tests at the changed ownership boundaries.
- Use the `scrapbot-testing` skill for full-suite, example, WGPU, framegrab, and visual checks.
- Renderer work whose output can change across frames is incomplete until a consecutive capture
  range has been inspected. A successful final frame does not verify streaming, LOD, temporal
  history, animation, hot reload, or other transitional behavior.
- Update behavioral FDRs when a feature's supported behavior or design changes.
- Add or amend an ADR only for a durable architectural decision.
- Keep `README.md`, `docs/TODO.md`, examples, and the documentation website synchronized with shipped behavior.
- Keep `docs/architecture/` synchronized with architectural surfaces and run its inventory audit when applicable.
- Finish with `mise test`, `git diff --check`, and any feature-specific verification.
- When integrating delegated work, review the combined diff rather than trusting per-agent test reports; cross-surface omissions usually appear only at integration time.

## Documentation Audits

Treat `src/scrapbot/component/registry.odin` as the source of truth for machine component facts. Treat `docs/architecture/components.md` as the complete engineering directory and `docs-website/src/content/docs/reference/components.md` as the canonical public usage reference. Do not duplicate internal ownership/invalidation prose into the website or exhaustive public field/default documentation into the architecture directory.

When adding, removing, renaming, or changing an engine component:

1. Update the canonical component page with its registry name, public fields, scene name, Luau handle, native descriptor/access pattern, defaults, constraints, ownership, and renderer-only behavior where applicable.
2. Update the component's standardized entry in `docs/architecture/components.md` when its storage, lifecycle, producers, consumers, invalidation, surfaces, or implementation/test anchors change.
3. Run both `node .agents/skills/scrapbot-feature-development/scripts/check_component_docs.mjs` and `node .agents/skills/scrapbot-architecture-inventory/scripts/check_inventory.mjs`.
4. Check `reference/project-files.md`, `reference/luau-api.md`, `guides/native-extensions.md`, and `guides/ecs-ui.md` only for surface-specific behavior. Link to the component page instead of duplicating exhaustive field inventories.
5. Audit both `docs/GLOSSARY.md` and the public website glossary for stale feature-state language.
6. Build the documentation website with `pnpm run build` from `docs-website/`.
