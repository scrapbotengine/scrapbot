# ADR-007: Engine-Hosted UI for Editor Tooling

**Date:** 2026-07-01

## Context

Scrapbot is expected to grow an editor, but the editor should not be a separate application stack disconnected from the runtime. Engines such as Godot demonstrate the value of building editor tooling with the engine's own UI and rendering systems.

An engine-hosted UI also supports in-game tooling, diagnostics overlays, runtime inspectors, and agent-facing repair workflows using the same primitives.

## Decision

Scrapbot will provide UI primitives inside the engine and use them to build editor tooling.

The UI system must support runtime overlays and eventual editor panels, inspectors, menus, trees, property controls, docking or layout regions, and text editing surfaces. UI definitions that belong to projects or tools should follow the text-first project model.

## Consequences

The editor and runtime share rendering, input, styling, layout, and diagnostics infrastructure. Tooling can run in the same environment as games and can expose engine state directly.

The UI system becomes an engine subsystem, not an optional sample. It must be designed with enough seriousness to support real tools.

Building an engine-hosted editor is slower initially than using an external GUI framework, but it keeps Scrapbot coherent and makes editor behavior more portable across interactive and headless-adjacent workflows.
