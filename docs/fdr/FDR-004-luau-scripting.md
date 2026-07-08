# FDR-004: Luau scripting

**Status:** Active
**Last reviewed:** 2026-07-08

## Overview

Luau scripting lets project directories include fast-iteration game code without rebuilding Scrapbot. The first slice is intentionally small: the runtime loads and executes `scripts/main.luau` during `scrapbot run`.

## Behavior

- Projects may include `scripts/main.luau`.
- `scrapbot init` creates a starter `scripts/main.luau`.
- `scrapbot run` executes the script after scene loading and ECS world construction.
- Script errors fail the run with a Luau diagnostic.
- Scripts can call `scrapbot.log(message)`.
- Scripts can read `scrapbot.entity_count()` and `scrapbot.renderable_count()`.

## Design Decisions

### 1. Start with one project entry script

**Decision:** Execute `scripts/main.luau` if it exists.
**Why:** A single conventional entry point is enough to verify embedding, project layout, and CLI behavior before introducing modules or script systems.
**Tradeoff:** There is no script scheduling, dependency loading, or hot reload yet.

### 2. Expose read-only ECS inspection first

**Decision:** The initial API exposes logging and ECS counts only.
**Why:** Read-only calls prove the Odin/Luau bridge without committing to component mutation semantics too early.
**Tradeoff:** Useful gameplay scripting still needs component APIs, queries, and system scheduling.

### 3. Vendor Luau from source

**Decision:** Keep Luau as a pinned git submodule and build static libraries through `mise`.
**Why:** The local package manager distribution provides a CLI but not the embeddable headers and libraries Scrapbot needs.
**Tradeoff:** Build tasks now own native dependency compilation and platform-specific linker flags.

## Related

- **ADRs:** ADR-001, ADR-002, ADR-006
- **FDRs:** FDR-001, FDR-002

## Open Questions

- What shape should script systems take in the ECS scheduler?
- How should component schemas and Luau type definitions be generated?
- Should Luau modules resolve from project-local script directories, engine packages, or both?
- What file-watching contract should drive script hot reload?
