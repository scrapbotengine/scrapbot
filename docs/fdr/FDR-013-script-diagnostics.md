# FDR-013: Script and Native Diagnostics

**Status:** Active
**Last reviewed:** 2026-07-06

## Overview

Diagnostics report Luau, script-ECS, and project-native failures in a form that humans, command-line workflows, editor UI, and coding agents can act on. The feature exists so invalid source edits point back to the relevant stage, file, system, and error message without requiring a restart or manual debugger session.

## Behavior

- Project validation can report script diagnostics for invalid Luau source or invalid script ECS declarations.
- Live script reload can report why a changed script failed while keeping the last known good script program active.
- Project validation and live reload can report native build, native load, and native registration diagnostics for project-local Zig modules.
- Runtime system failures can report the failing system id and source script path when available.
- Runtime failures caused by denied or failed host ECS access report the system id plus the relevant component and field when available.
- Diagnostics identify the failure stage as load, native_build, native_load, native_registration, registration, schedule, or runtime.
- Diagnostics can include source positions. Syntax and runtime errors use Luau-reported line numbers when available; script ECS declarations use the line where the declaration function was called.
- Diagnostics include a human-readable message from Luau, Zig build output, the engine validation layer, or the host ECS access bridge.
- Successful subsequent operations clear stale live diagnostics.
- Command-line commands render diagnostics as text.
- `scrapbot check` can render validation diagnostics as JSON for editor panels, automation, and agent workflows.
- `scrapbot step` can render runtime system diagnostics as JSON alongside the final scene and simulation summaries.
- During the Odin migration, the Odin `check` command loads scripts through the shared Luau C ABI bridge, imports component/system declarations, and can render structured load, registration, and schedule diagnostics. Odin `step`, `bench`, and bounded `run` can execute Luau query/component-field systems, first-pass structural commands, direct entity vec3 methods, prepared query/resolved-row field access, bulk f32/vec3 query views, first-pass Odin-native set-field operations, and first-pass Odin-native lifecycle operations that spawn, add, remove, and despawn through deferred ECS mutation, and can report runtime diagnostics with active system, component field, and runtime error context for denied or failed host-bridge access. Bounded Odin `run --frames` now polls project, scene, script, and native source reloads between frames, reports successful reload event categories, and keeps last-known-good behavior on failed reloads. That reload/poll/startup/update diagnostic path is exposed as a reusable live-project frame tick for the future Odin window loop. Unsupported scheduled Odin-native systems currently report a structured runtime diagnostic at the pending execution boundary instead of being skipped by native-only projects. Wiring the tick into an unbounded presentation loop and richer Luau stack/range diagnostics still remain in the Zig implementation.

## Design Decisions

### 1. Keep diagnostics structured below the CLI

**Decision:** The runtime stores diagnostics as structured data and leaves text formatting to command surfaces.
**Why:** The same failure needs to serve stderr output, editor UI, automated tests, and future machine-readable modes. This follows ADR-011.
**Tradeoff:** Callers must manage diagnostic ownership instead of receiving only a simple error code.

### 2. Track failure stage explicitly

**Decision:** Diagnostics include the stage where the failure occurred: load, native_build, native_load, native_registration, registration, schedule, or runtime.
**Why:** "Invalid script" is too broad. Knowing the stage tells the user whether they broke Luau syntax, native Zig compilation/loading, ECS declarations, dependency scheduling, or executing system logic.
**Tradeoff:** New script lifecycle stages must be added deliberately when the scripting pipeline grows.

### 3. Preserve last-known-good runtime state

**Decision:** Failed script validation or reload reports diagnostics but does not replace the active script program. Runtime failures report diagnostics for the frame without corrupting component state.
**Why:** Live reload should be repairable in place. This follows ADR-009 and ADR-011.
**Tradeoff:** The runtime must retain diagnostic state separately from active game state.

### 4. Start with line-level positions before full source spans

**Decision:** Diagnostics include source line numbers when the engine can derive them, while columns and multi-line ranges remain optional.
**Why:** Line-level locations unblock editor navigation and agent repair loops without requiring a full Luau source map pipeline yet.
**Tradeoff:** Some diagnostics still point at the declaration or failing line rather than the exact expression or token.

### 5. Provide JSON through headless command surfaces

**Decision:** Machine-readable diagnostics are exposed through `scrapbot check --format=json` and `scrapbot step --format=json` before interactive run/reload output.
**Why:** Project validation and deterministic stepping are stable headless surfaces used by agents, tests, and editor integrations. Live run output can stay optimized for human stderr until the editor API is clearer.
**Tradeoff:** Interactive reload diagnostics are not yet emitted as structured events.

### 6. Prefer host-authored runtime access messages

**Decision:** Runtime host APIs provide detailed error messages before the Luau bridge raises the system failure.
**Why:** Generic bridge failures make it hard to tell whether a system forgot a read/write declaration, requested a missing field, or supplied invalid data. Host-authored messages can name the system, component, field, and failed operation.
**Tradeoff:** The bridge must preserve a small host error channel alongside Luau's own last-error string.

## Related

- **ADRs:** ADR-001, ADR-006, ADR-009, ADR-011, ADR-019
- **FDRs:** FDR-003, FDR-010, FDR-011, FDR-012

## Open Questions

- What stable diagnostic codes should Scrapbot expose for editor and agent tooling?
- How should Luau stack traces and full source ranges be represented?
- Should interactive live reload expose structured diagnostic events in addition to stderr text?
