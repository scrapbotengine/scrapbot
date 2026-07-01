---
name: machina-script-diagnostics
description: Use when changing Machina script diagnostics, Luau bridge error reporting, `machina check` diagnostic output, script reload/runtime failure handling, Luau declaration origins, or editor/agent-facing diagnostic surfaces.
---

# Script Diagnostics

Use this workflow for changes that affect how Machina reports script load, registration, schedule, reload, or runtime failures.

## Core Expectations

- Preserve last-known-good behavior: failed script validation, reload, or runtime execution must not destroy the active project state.
- Keep diagnostics structured below command output. Text and JSON rendering should be command-surface concerns.
- Keep `machina check --format=json` stable for editor and agent workflows.
- Prefer adding structured diagnostic fields over requiring tools to scrape human-readable messages.
- Update [ADR-011](../../../docs/adr/ADR-011-structured-script-diagnostics.md) when the diagnostic architecture or ownership model changes.
- Update [FDR-013](../../../docs/fdr/FDR-013-script-diagnostics.md) when user-visible diagnostic behavior changes.

## Implementation Touchpoints

- `src/script.zig`: diagnostic data model, Luau load/registration/runtime diagnostics, source-origin tracking.
- `src/luau_bridge.cpp` and `src/luau_bridge.h`: Luau error messages and declaration metadata exposed to Zig.
- `src/root.zig`: project validation, live reload, last-known-good state, diagnostic cloning.
- `src/main.zig`: CLI formatting for text and JSON diagnostics.

## Verification

Run the normal script-diagnostics checks:

1. `mise build`
2. `mise test`
3. `./zig-out/bin/machina check examples/minimal --format=json`
4. Create a temporary copy of `examples/minimal`, break `scripts/gameplay.luau`, and verify:
   - text output is human-readable,
   - JSON output contains `ok: false`,
   - JSON diagnostic contains `stage`, `path`, `message`,
   - JSON diagnostic contains `start.line` when the engine can derive one.

For reload/runtime changes, add or update tests that prove a broken script reports a diagnostic and a subsequent fix recovers without restarting.

## Review Notes

- Check diagnostic ownership carefully. Any allocated `path`, `system_id`, or `message` data must be freed by the recipient or cloned explicitly.
- Check that JSON uses stable machine values, not localized or decorative text labels.
- Check that text output remains useful without forcing humans to read JSON.
- If runtime failures print every frame, decide whether that is acceptable for the current slice or whether duplicate suppression belongs in the same change.
