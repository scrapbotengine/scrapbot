# ADR-021: Domain-Oriented Source Layout

**Date:** 2026-07-06

## Context

The engine started with a small number of top-level Zig files. As renderer, editor, script, project, UI, and ECS responsibilities grew, those files became harder to scan and more expensive for agents to modify safely. Large mixed-ownership files also made compile-time-oriented refactors harder because unrelated implementation details shared the same module.

## Decision

Organize engine implementation by domain directories while keeping narrow compatibility facades where they reduce import churn. Public or widely used top-level files such as `src/runtime.zig`, `src/script.zig`, `src/ui_layout.zig`, and `src/ui_font.zig` may remain as re-export facades, but subsystem implementation should live under focused directories such as `src/runtime/`, `src/script/`, `src/project/`, `src/ui/`, `src/editor/`, and `src/render/`.

When splitting a large module, prefer behavior-preserving moves and narrow adapters over broad rewrites. Each slice should be independently testable, and files over roughly 1,500 lines should be treated as candidates for further ownership-based extraction unless they are generated or intentionally table-like.

## Consequences

Domain ownership is easier to see from paths, and future changes can target smaller files with clearer dependencies. Compatibility facades keep existing imports stable during the transition, but they add a small amount of alias boilerplate. Runtime and rendering still contain large implementation files, so this decision sets the direction for continued splits rather than finishing all possible decomposition at once.
