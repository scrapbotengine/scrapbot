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

## Public Surface Audit

For every feature, decide explicitly which layers it affects:

- Core Odin implementation and ECS/runtime behavior.
- Luau runtime bindings and generated Luau declarations.
- Project-local Odin extension wrapper and raw extension ABI.
- Scene/project file parsing and validation.
- CLI behavior and diagnostics.
- Example projects.
- README, TODO, ADRs, FDRs, and documentation website.

Do not assume every feature belongs on every surface. When one surface intentionally trails another, record that decision or follow-up rather than overlooking it.

For ECS UI work, also use the `scrapbot-ui-development` skill. The editor must remain a consumer of the public UI contract, and a public field is incomplete until every applicable authoring and runtime surface agrees.

## Generated Luau Types

When changing built-in components, Luau APIs, query types, or component schemas:

1. Update the canonical type generator in `src/scrapbot/component/luau_types.odin`.
2. Build the CLI.
3. Run `bin/scrapbot check <example>` for every affected example.
4. Review generated `types/scrapbot.d.luau` diffs and run the Luau analyzer through the normal test suite.

Never hand-edit generated example declarations without changing their generator.

## Verification And Documentation

- Add focused unit and integration tests at the changed ownership boundaries.
- Use the `scrapbot-testing` skill for full-suite, example, WGPU, framegrab, and visual checks.
- Update behavioral FDRs when a feature's supported behavior or design changes.
- Add or amend an ADR only for a durable architectural decision.
- Keep `README.md`, `docs/TODO.md`, examples, and the documentation website synchronized with shipped behavior.
- Finish with `mise test`, `git diff --check`, and any feature-specific verification.
- When integrating delegated work, review the combined diff rather than trusting per-agent test reports; cross-surface omissions usually appear only at integration time.

## Documentation Audits

Treat `docs-website/src/content/docs/reference/components.md` as the canonical public inventory of engine-provided components. Treat `src/scrapbot/component/registry.odin` as its source of truth.

When adding, removing, renaming, or changing an engine component:

1. Update the canonical component page with its registry name, public fields, scene name, Luau handle, native descriptor/access pattern, defaults, constraints, ownership, and renderer-only behavior where applicable.
2. Run `node .agents/skills/scrapbot-feature-development/scripts/check_component_docs.mjs` to catch registry entries missing from the canonical page.
3. Check `reference/project-files.md`, `reference/luau-api.md`, `guides/native-extensions.md`, and `guides/ecs-ui.md` only for surface-specific behavior. Link to the component page instead of duplicating exhaustive field inventories.
4. Audit both `docs/GLOSSARY.md` and the public website glossary for stale feature-state language.
5. Build the documentation website with `pnpm run build` from `docs-website/`.
