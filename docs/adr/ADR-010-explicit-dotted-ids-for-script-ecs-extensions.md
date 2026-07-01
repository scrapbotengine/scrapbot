# ADR-010: Explicit Dotted IDs for Script ECS Extensions

**Date:** 2026-07-01

## Context

Machina will let scripts define new component and system types. Those types need stable identifiers for scene files, reload validation, editor tooling, diagnostics, package reuse, and system scheduling.

Implicit project namespaces would make early examples convenient, but they would also hide an important authoring decision and create ambiguity once projects depend on reusable packages. The engine must also reserve its own built-in component and system namespace without blocking project and package authors from choosing their own naming scheme.

## Decision

Script-defined component and system types use explicit dotted type ids with at least two lowercase ASCII segments, such as `com.example.health` or `local_project.dialogue_state`.

Machina reserves `machina.*` for engine-owned types. Project and package code must choose explicit non-reserved namespaces. The engine does not provide, recommend, or infer a default project namespace; `game.*` has no special behavior.

Reusable packages should use a namespace they own, such as a reverse-DNS name. Local projects may use any non-reserved dotted namespace they intentionally choose.

## Consequences

Scene files, scripts, editor tools, and reload diagnostics can refer to component and system types without relying on local aliases or hidden defaults.

Project authors must make a namespace decision before registering script-defined ECS types. This is a small amount of friction, but it prevents accidental collisions and makes package boundaries explicit.

Lua bindings and other future scripting bindings must expose registration APIs that validate type ids, reject `machina.*` for project code, and treat duplicate registrations as reload-compatible only when the definition is unchanged.
