# FDR-004: Script Components

**Status:** Planned
**Last reviewed:** 2026-07-01

## Overview

Script components let scenes attach scripted behavior to entities. They exist so game logic can be authored, reviewed, reloaded, and tested as text without recompiling the native engine.

## Behavior

- Scene files can reference script files as components on entities.
- Script files define behavior that can participate in engine lifecycle events exposed by Machina.
- Script load, compile, and runtime errors are reported with file and location information.
- Script components can be validated in headless mode.
- Script components can access supported entity and component operations through the scripting API.
- Scripts can register ECS component and system types through explicit non-reserved dotted ids.
- Script reloads should preserve or intentionally reset state according to explicit lifecycle rules.
- Scripts are behavior files; they do not become the primary storage format for scene structure.

## Design Decisions

### 1. Keep scripts attached through scene data

**Decision:** Scene files reference scripts explicitly through script components.
**Why:** This keeps structure in the scene model and behavior in script files. It follows ADR-001 and ADR-006.
**Tradeoff:** The engine needs a stable component representation before the scripting API is complete.

### 2. Delay the final scripting language until prototype evidence exists

**Decision:** The feature is designed around an embeddable scripting language, with Lua, Luau, and Wren still candidates.
**Why:** Binding ergonomics, diagnostics, sandboxing, and agent-generated script quality need direct evaluation. It follows ADR-006.
**Tradeoff:** Early feature docs cannot yet specify final syntax or runtime library behavior.

### 3. Bind scripts through the entity component runtime

**Decision:** Script components use the engine's entity/component API for runtime state access.
**Why:** This keeps scripts aligned with scenes, validation, editor tooling, and live reload. It follows ADR-008 and ADR-009.
**Tradeoff:** The scripting API depends on the component model becoming explicit enough to bind cleanly.

### 4. Require explicit ids for script-defined ECS types

**Decision:** Script-defined component and system registrations use explicit dotted ids, and the engine does not provide a default project namespace.
**Why:** This keeps package boundaries and reload compatibility explicit. It follows ADR-010.
**Tradeoff:** Project authors must choose a namespace before registering script-defined ECS types.

## Related

- **ADRs:** ADR-001, ADR-003, ADR-006, ADR-008, ADR-009, ADR-010
- **FDRs:** FDR-002, FDR-003, FDR-009, FDR-010, FDR-011

## Open Questions

- Which scripting language becomes the initial supported runtime?
- What lifecycle callbacks should the first script component support?
- How should script APIs expose entity and component access without creating unstable coupling?
- How should script state be preserved or reset across reloads?
