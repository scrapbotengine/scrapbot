# ADR-008: Component-System Runtime Model

**Date:** 2026-07-01

## Context

Machina scene data already describes entity-like records, but the engine needs a low-level runtime model that can scale beyond renderer-specific fields. Users, agents, scripts, editor tooling, tests, and future import/build workflows need a shared way to reason about game state.

The engine should encourage project authors and coding agents to think in entities, components, and systems. That model fits text-first scene data, structured validation, editor inspection, live reload, and scripting APIs better than ad hoc native state or script-owned object graphs.

## Decision

Machina will use an ECS-oriented component-system runtime model in the low-level engine.

The core runtime owns entity identity, component storage, component validation, system scheduling, structural mutation, and query/mutation APIs. Scenes serialize entity and component data as text. Scripts interact with game state through a supported component/system API instead of directly owning authoritative scene structure.

Storage starts as sparse column tables: one table per component type, dense entity rows per table, sparse entity-to-row lookup, and typed SoA columns per component field. This supports engine and Luau-registered schemas without requiring native structs for every component.

Machina does not yet commit to chunked archetypes, a third-party ECS library, or a final scheduler implementation.

## Consequences

Scenes, scripts, tests, editor tooling, and agent workflows get one shared mental model for runtime state. Text scene patches can map cleanly onto entity/component changes, and live reload can reason about stable identities and component replacement.

The engine must design stable component schemas, diagnostics, migration behavior, and script bindings. It also needs discipline to prevent subsystem-specific state from bypassing the component model.

The sparse SoA table layout gives early systems a real ECS data path, including entity creation/destruction and component insertion/removal. It still requires explicit follow-up work for generation-safe handles, deferred command buffers, chunking/archetypes, migration, and parallel iteration.
