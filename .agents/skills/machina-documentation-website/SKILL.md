---
name: machina-documentation-website
description: Use when adding, changing, reviewing, or documenting Machina's docs website, especially built-in engine components, scene-authored component schemas, runtime-only components/resources, docs-website content pages, Starlight navigation, or docs validation. Trigger this alongside feature work whenever a Machina component id, field, default, authoring rule, runtime-only rule, UI primitive, input resource, renderer setting, camera/light/shadow component, geometry/material component, or project-local example component changes.
---

# Machina Documentation Website

## Principle

Treat docs website updates as part of the feature, not optional cleanup. If a change adds or changes built-in components, scene-authored fields, defaults, validation semantics, or runtime-only component behavior, update `docs-website/` in the same slice unless there is a concrete reason the behavior is intentionally undocumented.

## Component Documentation Workflow

1. Read `docs-website/AGENTS.md` before editing docs-site files.
2. Inspect the implementation instead of trusting stale docs:
   - `src/runtime.zig` for component ids, field names, field types, and runtime storage.
   - `src/root.zig` for scene loading, default values, singleton checks, validation rules, and runtime-only authoring restrictions.
   - `src/ui_layout.zig` for retained UI layout, hit testing, command routing, scroll, clipping, and canvas behavior.
   - `src/render.zig` and `src/shaders/` for rendering-facing component behavior.
   - `examples/`, `tests/projects/`, and relevant FDRs for supported authoring patterns.
3. Update `docs-website/src/content/docs/reference/components.md` for every built-in or intentionally documented project-local component change.
4. If the behavior needs more than a table note, update or add the relevant concept/workflow page and wire it into `docs-website/astro.config.mjs` sidebar if it is a new page.
5. Keep source docs consistent: update README, FDRs, ADRs, glossary, examples, or `docs/TODO.md` when the repository rules require it.
6. Run docs validation from `docs-website/`:

```bash
pnpm install
pnpm run build
```

Use `pnpm install` only when dependencies are missing or stale. For local preview, follow `docs-website/AGENTS.md` and use `astro dev --background`.

## What To Document For Components

For each component, document enough for a user or agent to author valid scene data without reading Zig:

- Component id exactly as registered, such as `machina.ui.rect`.
- Field names, scene/schema types, and important defaults.
- Whether the component is scene-authored, runtime-only, legacy, singleton, marker-only, or engine-owned.
- Valid string or enum-like values, such as canvas scale modes or stack directions.
- Required companion components or common composition patterns.
- Behavioral notes that affect authoring, validation, rendering, input routing, or live reload.
- Migration guidance when replacing legacy components, such as preferring geometry plus material over `machina.render.cube`.

Do not expose backend implementation details or private renderer/editor paths. Keep the docs at the engine API level.

## Placement Guidelines

- Use `docs-website/src/content/docs/reference/components.md` as the index for built-in component ids and fields.
- Use `docs-website/src/content/docs/rendering/` for camera, lights, shadows, renderer settings, geometry, materials, batching, and visual behavior.
- Use `docs-website/src/content/docs/concepts/` for ECS, scene authoring, and project model explanations.
- Use `docs-website/src/content/docs/workflow/` for diagnostics, testing, live reload, and development workflows.
- Use `docs-website/src/content/docs/editor-ui/` for editor shell, debug overlay, inspector, and editor-facing retained UI behavior.
- Update `docs-website/astro.config.mjs` when adding a page that should appear in the sidebar.

## Writing Style

- Write user-facing docs, not implementation notes.
- Explain behavior in terms of what project authors can do, what Machina does, and what effect users will see.
- Do not use internal planning or implementation phrases in docs-website content, such as "current slice", "renderer path", "Zig source", "private path", "future slice", or "implementation detail".
- Mention source files, engine internals, or backend mechanics only when the documentation is explicitly for contributors; component reference pages should stay at the public engine API level.
- Prefer concrete examples and compact tables for reference pages.
- Call out runtime-only components clearly so users do not author them in scene files.
- Preserve Machina terminology from `docs/GLOSSARY.md`.
- Keep examples aligned with current scene syntax and component registration rules.
- Avoid promising roadmap items as shipped behavior; move future work to `docs/TODO.md` when it needs tracking.
