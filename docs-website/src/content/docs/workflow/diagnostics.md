---
title: Diagnostics
description: Understand Scrapbot's structured diagnostics for scripts, native modules, schedules, and runtime host API failures.
---

Scrapbot diagnostics are designed for command-line users, editor integrations, and coding agents.

Diagnostics try to identify:

- Stage.
- File path.
- System id.
- Component and field context.
- Human-readable message.
- Source position when available.

## Diagnostic Stages

| Stage | Meaning |
| --- | --- |
| `load` | Luau source failed to load. |
| `native_build` | Project-local Zig source failed to compile. |
| `native_load` | Native dynamic library failed to open or export `scrapbot_register`. |
| `native_registration` | Native component/system registration failed. |
| `registration` | Script declarations failed to register. |
| `schedule` | System schedule construction failed. |
| `runtime` | A Luau or native system failed while running. |

## JSON Output

Use JSON mode for editor or agent workflows:

```sh
scrapbot check examples/showcase --format json
scrapbot step examples/showcase --format json
```

Successful JSON output preserves project metadata and schedule summaries. Failure output includes diagnostics where possible.

## Runtime Host API Errors

Host API errors should include the active system and relevant component/field context.

Examples of failures Scrapbot can report:

- Querying a component without declaring read or write access.
- Writing a component without declaring write access.
- Writing a non-finite `f32` or `vec3`.
- Adding an unknown component.
- Adding an unknown field.
- Despawning an entity without write access to all attached components.
- Native callback failure without a more specific host error.

## Last-Known-Good Runtime

In headful live reload, diagnostics should not destroy the currently running project. Invalid reloads keep the last-known-good state active until the next successful edit.

This behavior is especially important for agent workflows: a broken edit should produce useful evidence, not wipe out the runtime being inspected.
