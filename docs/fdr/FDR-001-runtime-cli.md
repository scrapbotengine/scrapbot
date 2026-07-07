# FDR-001: Runtime CLI

**Status:** Active
**Last reviewed:** 2026-07-07

## Overview

The runtime CLI is the entry point for creating, validating, and running Scrapbot projects. It exists so users and agents can work with project directories before a full editor exists.

## Behavior

- Users can print the engine version.
- Users can initialize a project directory.
- Users can validate a project without opening a window.
- Users can run a project through the selected renderer backend.
- Users can request a platform window for renderer runs and limit windowed runs with `--frames`.
- Users can request a headless WGPU PNG framegrab with `--framegrab`.
- Users can ask for top-level help or command-specific help.
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

## Related

- **ADRs:** ADR-001, ADR-002, ADR-003, ADR-004, ADR-005
- **FDRs:** FDR-002, FDR-003

## Open Questions

- Should top-level command metadata move into a command table once the CLI has more commands?
- Should `scrapbot check` gain machine-readable diagnostics before more validators are added?
