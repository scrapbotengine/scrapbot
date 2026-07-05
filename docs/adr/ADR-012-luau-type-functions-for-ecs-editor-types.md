# ADR-012: Luau Type Functions for ECS Editor Types

**Date:** 2026-07-02

## Context

Scrapbot scripts register ECS component schemas as runtime data, but authors also need useful editor types for component payloads inside systems. Maintaining separate payload type aliases and field maps is repetitive and easy to drift, especially for agent-authored gameplay code.

Earlier schema inference used marker values such as `ecs.vec3()` to smuggle payload types through Luau generics. That worked for simple Vec3 fields, but it made the runtime schema syntax less direct than the actual component declaration and did not scale cleanly to other field types.

Luau's new type solver supports user-defined type functions that can inspect table-property types and synthesize new table types during analysis. This gives Scrapbot a way to derive editor payload types from literal field schema tables while keeping runtime component declarations text-like and explicit.

## Decision

Scrapbot will use Luau type functions in `types/scrapbot.d.luau` to derive component payload editor types from field declarations created with `ecs.fields(...)`.

The preferred component authoring form is a single field-schema table using literal field type strings. The editor definition maps those field type literals to Luau payload types for component handles and typed query objects. Explicit `ecs.component<<T>>(...)` payload declarations remain supported for cases where the schema cannot express the desired editor shape yet.

Scrapbot's checked editor configuration enables Luau's new solver so these type functions are available in both command-line type checks and VS Code. Legacy marker-schema helpers remain available as compatibility shims, but new examples and docs should use `ecs.fields(...)`.

New component schema authoring must not reintroduce marker-value inference as the primary path. If field-schema inference breaks, the fix should be in the Luau definition file, type-check harness, or runtime bridge support, not by moving canonical examples back to `ecs.schema(...)` or `ecs.vec3()`.

## Consequences

Component schemas become more direct: runtime field declarations and editor payload inference use the same field map instead of a parallel marker DSL.

Scrapbot now depends on Luau new-solver behavior for the richest editor experience. The runtime scripting boundary still works without editor type checking, but contributors need a language server and type-check command that enable `LuauSolverV2`.

The definition file carries more responsibility. It contains type-function code that must be tested with editor-analysis fixtures, and future field kinds must update both runtime support and the type-function mapping.

Some analysis-only metadata is acceptable inside the Luau type surface when it keeps query ergonomics practical, but it must stay private and must not become gameplay API.

The marker-schema compatibility surface is temporary infrastructure. Keeping it working is useful for migration and regression coverage, but it should not shape future component API design.
