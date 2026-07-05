---
title: Live Reload
description: How Scrapbot reloads project metadata, scenes, scripts, and native modules while preserving last-known-good state.
---

Live reload is a core Scrapbot runtime capability.

During `scrapbot run`, Scrapbot tracks:

- Project metadata.
- The active scene file.
- Project-listed Luau script files.
- The optional project-local native Zig source file.

Valid edits swap into the running renderer. Invalid edits keep the last-known-good project and scene active.

## What Reloads

| Source | Reload behavior |
| --- | --- |
| `project.toml` | Reloads project metadata and may switch default scene/scripts/native source. |
| Scene TOML | Revalidates and swaps scene data on success. |
| Luau scripts | Rebuilds script declarations and systems. |
| Native Zig source | Rebuilds dynamic library, reloads registrations, rebuilds schedule, then validates scene. |

## Last-Known-Good Behavior

Failed reloads do not destroy the running project state.

Examples:

- A Luau syntax error reports a diagnostic and keeps the previous script program active.
- A script runtime failure during update reports the active system and keeps the process alive.
- A native compile failure keeps the previous native module active.
- A scene validation error keeps the previous scene active.

## Startup Systems and Reloads

Startup systems run once for a loaded project/scene generation.

Script-only reloads do not replay startup over existing live world state. This avoids duplicating startup-spawned entities when only behavior changes.

## Native Reloads

For project-local native code, Scrapbot:

1. Rebuilds the dynamic library into `.scrapbot/native/`.
2. Opens the library.
3. Calls `scrapbot_register`.
4. Rebuilds the ECS registry and schedule.
5. Validates the current scene against the new registry.
6. Swaps only if all stages succeed.

Diagnostics identify the failing stage as native build, native load, native registration, registration, schedule, or runtime.

## Good Reload-Friendly Practices

- Keep authored data in text files.
- Use stable entity ids.
- Keep component schemas explicit.
- Keep project-native modules small and registration-focused.
- Preserve staged validation when adding new runtime resources.
- Avoid hidden side channels that cannot be rebuilt from project text.
