# ADR-001: Agent-Native Text-First Project Model

**Date:** 2026-07-01

## Context

Scrapbot is intended to be a game engine that works well for both humans and coding agents. Traditional game engines often hide important project state in binary scene files, editor-only databases, opaque import metadata, or mutation-heavy workflows that are difficult to review, merge, validate, and repair.

For agentic workflows to be practical, project state needs to be inspectable without launching the editor, editable with ordinary file tools, stable under version control, and validated by deterministic commands. Binary files are still appropriate for source assets such as images, audio, models, and fonts, and for generated caches, but not for engine-authored project structure.

## Decision

Scrapbot projects use a text-first project model. Engine-authored state such as scenes, prefabs, materials, UI layouts, input maps, scripts, build settings, and project metadata is stored in documented text formats with stable schemas.

Binary data is limited to source assets and generated artifacts. Generated artifacts live outside the authoritative project model and must be reproducible from source files or safely disposable.

The engine treats human editing, agent editing, command-line validation, editor mutation, and version-control review as first-class workflows over the same files.

## Consequences

Project changes become diffable, reviewable, mergeable, and scriptable. Agents can inspect and modify project state without needing editor automation for every change.

The engine must provide strong diagnostics for malformed or semantically invalid files. Text formats must be designed for long-term stability, not just convenience during early development.

Editor features must write clean, stable output rather than arbitrary serialized memory dumps. This adds discipline to editor implementation but prevents the editor from becoming the only safe way to modify a project.
