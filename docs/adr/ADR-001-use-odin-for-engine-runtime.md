# ADR-001: Use Odin for the engine runtime

**Date:** 2026-07-07

## Context

Scrapbot is an experimental game engine focused on agent-assisted development, ECS-first runtime design, 3D rendering, scripting, hot reload, and project-local native extension code. The runtime needs a systems language that is practical for low-level engine code while staying small enough for fast iteration.

## Decision

Use Odin as the implementation language for the Scrapbot engine runtime and CLI.

## Consequences

Odin gives the engine direct control over memory layout, manual resource lifetimes, and data-oriented constructs such as `#soa` storage. It also ships useful vendor bindings for graphics, windowing, audio, and platform APIs, which keeps the early dependency surface compact.

The project inherits Odin's ecosystem tradeoffs. Some libraries are bundled, but others may require direct C bindings or project-owned integration work. The engine should prefer Odin's standard and vendor packages when they fit, and avoid introducing extra build systems until a feature needs them.
