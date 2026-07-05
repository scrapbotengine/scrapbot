# ADR-010: Local and Qualified IDs for Script ECS Extensions

**Date:** 2026-07-01

## Context

Scrapbot will let scripts define new component and system types. Those types need stable identifiers for scene files, reload validation, editor tooling, diagnostics, package reuse, and system scheduling.

Implicit project namespaces would hide an important authoring decision and create ambiguity once projects depend on reusable packages. At the same time, forcing every local project component to use a package-style dotted namespace adds ceremony before a project has any reusable package boundary.

The engine must reserve its own built-in component and system namespace without blocking project and package authors from choosing their own naming scheme.

## Decision

Script-defined component and system types use explicit ids in one of two forms.

Project-local ids are single lowercase ASCII identifier segments, such as `spin` or `inventory_item`. They are only stable inside the current project and are not valid for reusable packages.

Qualified ids have two or more lowercase ASCII segments, such as `com.example.stamina` or `local_project.dialogue_state`. Reusable packages must use qualified ids, preferably under a namespace they own, such as a reverse-DNS name.

Scrapbot reserves `scrapbot.*` for engine-owned types. The engine does not provide, recommend, or infer a default project namespace; `game.*` has no special behavior beyond being an explicitly chosen qualified id.

## Consequences

Scene files, scripts, editor tools, and reload diagnostics can refer to component and system types without relying on hidden defaults.

Project authors can use short local ids while prototyping and can intentionally move to qualified ids when code becomes reusable. Moving a local type into a package requires an explicit migration from the local id to the qualified id.

Lua bindings and other future scripting bindings must expose registration APIs that distinguish project, package, and engine registration contexts. They must reject `scrapbot.*` for project/package code, reject local ids for package code, and treat duplicate registrations as reload-compatible only when the definition is unchanged.
