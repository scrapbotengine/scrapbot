# FDR-004: Script Components

**Status:** Planned
**Last reviewed:** 2026-07-01

## Overview

Script components let scenes attach scripted behavior to entities. They exist so game logic can be authored, reviewed, reloaded, and tested as text without recompiling the native engine.

## Behavior

- Scene files can reference script files as components on entities.
- Script files define behavior that can participate in engine lifecycle events exposed by Scrapbot.
- Script load, compile, and runtime errors are reported with file and location information.
- Script components can be validated in headless mode.
- Script components can access supported entity and component operations through the scripting API.
- Scripts can register ECS component and system types through explicit project-local or qualified non-reserved ids.
- Script reloads should preserve or intentionally reset state according to explicit lifecycle rules.
- Scripts are behavior files; they do not become the primary storage format for scene structure.

## Design Decisions

### 1. Keep scripts attached through scene data

**Decision:** Scene files reference scripts explicitly through script components.
**Why:** This keeps structure in the scene model and behavior in script files. It follows ADR-001 and ADR-006.
**Tradeoff:** The engine needs a stable component representation before the scripting API is complete.

### 2. Use Luau as the scripting target

**Decision:** Script components target Luau.
**Why:** Luau gives Scrapbot a game-oriented scripting language with room for sandboxing, type annotations, editor diagnostics, and agent-readable source. It follows ADR-006.
**Tradeoff:** Scrapbot needs a clear backend boundary for Luau packaging, binding, and cross-platform builds.

### 3. Bind scripts through the entity component runtime

**Decision:** Script components use the engine's entity/component API for runtime state access.
**Why:** This keeps scripts aligned with scenes, validation, editor tooling, and live reload. It follows ADR-008 and ADR-009.
**Tradeoff:** The scripting API depends on the component model becoming explicit enough to bind cleanly.

### 4. Distinguish local and qualified ids for script-defined ECS types

**Decision:** Script-defined component and system registrations use explicit ids: local single-segment ids for project-only types, qualified dotted ids for packages, and `scrapbot.*` for engine-owned types.
**Why:** This keeps local authoring lightweight while making package boundaries and reload compatibility explicit. It follows ADR-010.
**Tradeoff:** Project-local ids require explicit migration if they become reusable package types.

## Related

- **ADRs:** ADR-001, ADR-003, ADR-006, ADR-008, ADR-009, ADR-010
- **FDRs:** FDR-002, FDR-003, FDR-009, FDR-010, FDR-011

## Open Questions

- What lifecycle callbacks should the first script component support?
- How should script APIs expose entity and component access without creating unstable coupling?
- How should script state be preserved or reset across reloads?
