# ADR-011: Structured Script Diagnostics

**Date:** 2026-07-01

## Context

Scrapbot executes project Luau scripts during project validation, live reload, and runtime update. Before structured diagnostics, these failures collapsed into generic project errors such as "invalid script" or silent failed update frames. That made the edit-run loop too opaque for humans, editor UI, and coding agents.

Script failures happen at different boundaries: loading Luau source, registering ECS declarations, building schedules, and running systems. Each boundary needs enough context to identify the failing file and system while still preserving last-known-good runtime state.

## Decision

Scrapbot will represent script failures as structured diagnostics with a stage, optional source path, optional system id, optional source positions, and message.

Project validation, live reload, and runtime update paths will preserve this diagnostic data instead of flattening it immediately into generic errors. Command-line output can render the diagnostic as text, while editor and machine-readable surfaces can consume the same structure through JSON output.

The scripting subsystem owns Luau-specific messages. The project runtime owns lifecycle behavior: failed validation or reload keeps the previous valid state active, and runtime system failures are reported without corrupting world state.

Runtime host APIs may provide engine-authored failure messages before the Luau bridge raises the system error. This lets denied ECS access and failed component mutations name the active system, component, field, and operation while still flowing through the same structured diagnostic object.

## Consequences

Script failures become actionable: the engine can report which script failed, what stage failed, and which system failed when relevant.

The runtime can keep generic project error codes for control flow while attaching richer diagnostics for humans, editor panels, and agents.

Diagnostic ownership and lifetime become part of the scripting boundary. Callers that receive diagnostics must either render or free them, and live project state must clear old diagnostics when new operations succeed.

Future diagnostics should add stack frames, severity, and machine-readable codes without replacing the current stage/path/system/location/message model.
