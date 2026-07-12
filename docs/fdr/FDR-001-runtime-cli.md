# FDR-001: Runtime CLI

**Status:** Active
**Last reviewed:** 2026-07-12

## Overview

The runtime CLI is the entry point for creating, validating, and running Scrapbot projects. It exists so users and agents can work with project directories before a full editor exists.

## Behavior

- Users can print the engine version.
- Users can initialize a project directory.
- Users can build a host-native runnable game package without running the game.
- Build packages contain project runtime data and active compiled native extensions, while omitting extension source and editor-only generated metadata.
- Packaged executables run their adjacent project directly and default to a windowed WGPU renderer.
- Users can name a build target, but non-host targets are rejected until Scrapbot has target-native Luau, SDL3, and WGPU dependencies.
- Users can validate a project without opening a window.
- Users can run a project through the selected renderer backend.
- Users can request a platform window for renderer runs and limit windowed runs with `--frames`.
- Users can request a headless WGPU PNG framegrab with `--framegrab`.
- Users can pass `--hot-reload` to periodically check `project.toml`, the default scene TOML, `scripts/main.luau`, native extension libraries, and declared native extension source directories while the renderer is running.
- Users can pass `--scheduler-trace` to report native worker count, parallel stage count, and maximum parallel width after a run.
- Users can ask for top-level help or command-specific help.
- `init`, `check`, `build`, and `run` accept `--json` and emit one versioned JSON document with structured diagnostics and command result data.
- JSON diagnostics have stable codes, severity, messages, and optional paths. Project logging is suppressed so machine-readable stdout is not contaminated.
- During development, `mise scrapbot` builds and runs the CLI with forwarded arguments.

## Design Decisions

### 1. Keep commands explicit

**Decision:** Scrapbot routes top-level subcommands directly.
**Why:** The command set is still small, and Odin's bundled parser handles options rather than command routing. See ADR-004.
**Tradeoff:** Scrapbot owns command discovery, top-level help text, and future command-table ergonomics.

### 2. Parse command options with core:flags

**Decision:** Each command uses a typed options struct parsed by `core:flags`.
**Why:** The CLI is expected to grow, and typed option structs are easier to extend than ad hoc argument indexing. See ADR-004.
**Tradeoff:** Command-specific help is generated from struct tags, which may not always match the exact prose style we want.

### 3. Keep machine output singular and versioned

**Decision:** Emit exactly one JSON envelope per command invocation with a schema version, command name, success flag, diagnostic array, and typed result.
**Why:** Agents and automation need deterministic parsing without scraping human prose or combining log streams.
**Tradeoff:** Command result schemas and diagnostic codes become public contracts that must evolve deliberately.

### 4. Ship host packages before cross-target toolchains

**Decision:** `scrapbot build` produces a runnable package for the current host and models an explicit target, while rejecting targets whose native dependency toolchain is unavailable.
**Why:** Odin can emit cross-target code, but a usable game also requires target-built Luau, SDL3, WGPU, and native extensions. A host package provides a complete artifact now without overstating cross-compilation support.
**Tradeoff:** Cross-platform exports require dependency toolchains and packaging rules to be added target by target.

## Related

- **ADRs:** ADR-001, ADR-002, ADR-003, ADR-004, ADR-005, ADR-006, ADR-008
- **FDRs:** FDR-002, FDR-003, FDR-006

## Open Questions

- Should top-level command metadata move into a command table once the CLI has more commands?
- Which validators should gain precise source ranges after the first path-level diagnostic slice?
