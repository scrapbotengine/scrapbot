# FDR-001: Runtime CLI

**Status:** Active
**Last reviewed:** 2026-07-19

## Overview

The runtime CLI is the entry point for creating, validating, running, and opening the first editor shell around Scrapbot projects.

## Behavior

- Users can print the engine version.
- Users can initialize a new or existing project directory without overwriting any owned project file; omitted project names derive from the destination directory.
- Users can build a host-native runnable game package without running the game.
- Build packages contain project runtime data and active compiled native extensions, while omitting extension source and editor-only generated metadata.
- Packaged executables run their adjacent project directly and default to a windowed WGPU renderer.
- Users can name a build target, but non-host targets are rejected until Scrapbot has target-native Luau, SDL3, and WGPU dependencies.
- Users can validate a project without opening a window.
- Source-project runs default to a windowed WGPU renderer with hot reload enabled.
- Visible runs request a 1600×900 logical window by default. Projects may override the startup width and height through `[window]` in `project.toml`; oversized requests preserve their aspect ratio while fitting within 90% of the primary display's usable area.
- Users can select another renderer, force headless execution, disable hot reload, and limit runs with `--frames`.
- Users can request a headless WGPU PNG framegrab with `--framegrab`.
- Users can pass `--editor` to start with editor chrome visible, while `Cmd/Ctrl+E` toggles it during a windowed run.
- Users can pass `--no-hot-reload` to disable the default periodic checks of `project.toml`, the default scene TOML, `scripts/main.luau`, native extension libraries, and declared native extension source directories. `--hot-reload` remains available as an explicit, backward-compatible spelling.
- Users can pass `--scheduler-trace` to report native worker count, parallel stage count, and maximum parallel width after a run.
- Users can pass `--runtime-stats` to collect early/late engine-frame cost through render preparation, engine-allocator bytes, and detailed ECS storage checkpoints for bounded runs.
- Windowed runtime-stat runs require a nonzero `--frames` limit; unbounded sessions are rejected because they have no deterministic late sample window.
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

### 5. Report deterministic growth signals before OS process metrics

**Decision:** Instrument bounded runs with opt-in engine-frame timing through render-list preparation, Odin engine-allocator bytes including a post-teardown checkpoint, and per-storage ECS slot counts, then expose the report through the existing structured run result.
**Why:** Comparing warm steady-state windows catches workload and memory growth without relying on noisy CPU percentages or platform-specific resident-memory accounting.
**Tradeoff:** The report excludes allocations owned directly by Luau, SDL, WGPU, GPU drivers, and the operating system. Those require a separate process/GPU telemetry layer.

### 6. Optimize source-project runs for the interactive loop

**Decision:** Make WGPU, a visible window, and hot reload the defaults for `scrapbot run <project>`. Keep packaged executables windowed but without source hot reload. Provide `--headless`, `--backend null`, and `--no-hot-reload` as explicit automation controls.
**Why:** Running a game during development is the primary human path and should require only the project path. Automation benefits more from explicit execution constraints than from inheriting historical development defaults.
**Tradeoff:** Existing scripts that relied on an implicit null renderer must add explicit deterministic flags. WGPU still requires a usable platform graphics environment.

## Related

- **ADRs:** ADR-001, ADR-002, ADR-003, ADR-004, ADR-005, ADR-006, ADR-008
- **FDRs:** FDR-002, FDR-003, FDR-006, FDR-008

## Open Questions

- Should top-level command metadata move into a command table once the CLI has more commands?
- Which validators should gain precise source ranges after the first path-level diagnostic slice?
