# ADR-009: Live Reload as a Core Runtime Capability

**Date:** 2026-07-01

## Context

Machina is intended for fast human and agent iteration. Project state is text-first, scripting is embeddable, and the engine binary supports both interactive and headless modes. Restart-only workflows would make scene edits, script edits, editor development, and automated repair loops slower and harder to verify.

Live reload also affects architecture: entity identity, component mutation, script lifecycle, diagnostics, resource ownership, and testability all need to be designed around reloadable state instead of process restarts.

## Decision

Machina treats live reload of scripts, scenes, and related text-authored runtime resources as a core runtime capability, not an editor-only convenience.

The runtime tracks loaded source files, detects changes in interactive modes, validates replacement data before applying it, applies compatible scene and script changes in place, and reports structured diagnostics. When a reload fails, the runtime keeps the last known good state active.

Headless commands must be able to exercise reload behavior deterministically as the feature matures.

## Consequences

Users and agents get a fast edit-run loop without restarting the engine for every script or scene change. The future editor can use the same reload path as headful game runs and headless tests.

The engine needs stable entity identity, staged validation, component patching, script lifecycle rules, resource lifetime management, file watching, debounce behavior, and clear diagnostics.

Live reload increases implementation complexity, but making it foundational prevents early systems from baking in restart-only assumptions.
