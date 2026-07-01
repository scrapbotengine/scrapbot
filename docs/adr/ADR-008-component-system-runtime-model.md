# ADR-008: Component-System Runtime Model

**Date:** 2026-07-01

## Context

Machina scene data already describes entity-like records, but the engine needs a low-level runtime model that can scale beyond renderer-specific fields. Users, agents, scripts, editor tooling, tests, and future import/build workflows need a shared way to reason about game state.

The engine should encourage project authors and coding agents to think in entities, components, and systems. That model fits text-first scene data, structured validation, editor inspection, live reload, and scripting APIs better than ad hoc native state or script-owned object graphs.

## Decision

Machina will use an ECS-ish component-system runtime model in the low-level engine.

The core runtime owns entity identity, component storage, component validation, system scheduling, and query/mutation APIs. Scenes serialize entity and component data as text. Scripts interact with game state through a supported component/system API instead of directly owning authoritative scene structure.

"ECS-ish" means Machina commits to component-oriented data and system-oriented behavior without yet committing to a specific storage layout, archetype design, scheduler, or third-party ECS library.

## Consequences

Scenes, scripts, tests, editor tooling, and agent workflows get one shared mental model for runtime state. Text scene patches can map cleanly onto entity/component changes, and live reload can reason about stable identities and component replacement.

The engine must design stable component schemas, diagnostics, migration behavior, and script bindings. It also needs discipline to prevent subsystem-specific state from bypassing the component model.

Deferring the exact ECS storage strategy keeps early implementation flexible, but it requires explicit follow-up work before performance-sensitive systems arrive.
