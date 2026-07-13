---
name: scrapbot-feature-development
description: Use when adding or changing Scrapbot engine features, public APIs, ECS behavior, rendering, scripting, native extensions, examples, or project tooling. Covers cross-surface implementation, documentation, generated types, and verification expectations.
---

# Scrapbot Feature Development

## Before Editing

1. Read the relevant roadmap section in `README.md`, open items in `docs/TODO.md`, and related ADRs/FDRs.
2. Trace the existing implementation end to end before choosing a design. Prefer established package boundaries and public APIs.
3. Call out material choices when multiple user-visible or architectural options remain. Breaking changes are acceptable, but accidental surface divergence is not.

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
