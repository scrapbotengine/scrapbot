# ADR-006: Embeddable Scripting Language for Game Logic

**Date:** 2026-07-01

## Context

Machina needs a way for game projects to define behavior without recompiling the engine. The scripting layer should be text-based, embeddable, suitable for hot reload, and practical for agent-authored gameplay logic.

Candidate languages included Lua, Luau, Wren, and similar small embeddable languages. Lua and Luau have strong game-scripting precedent and broad familiarity. Wren has a clean class-based design and an embedding-oriented implementation. The final language choice affects sandboxing, type checking, binding ergonomics, debugging, packaging, and editor tooling.

Machina also needs scripting to scale with an ECS runtime. Most runtime behavior should be represented as systems with declared component access, not as unconstrained object callbacks. That lets the native engine validate dependencies, batch compatible systems, and eventually partition work across threads or multiple script VMs.

## Decision

Machina will target Luau as the initial embeddable scripting language for game logic.

The scripting API is system-first. Scripts declare ECS component and system definitions, including the components each system reads and writes. The native engine owns component storage, validation, scheduling, reload transactions, and future parallelization. Luau VMs execute behavior through an engine-provided ECS facade instead of owning authoritative game state.

Scripts are behavior files, not authoritative scene storage. Scenes and prefabs reference script components, while structural project data remains in engine-defined text formats.

## Consequences

Machina keeps runtime behavior editable and reloadable without requiring native recompilation.

Choosing Luau gives Machina a game-oriented scripting target with room for sandboxing, type annotations, and editor diagnostics. The engine still keeps third-party runtime details behind a scripting subsystem boundary.

The engine must design script APIs carefully so they remain stable, testable, and understandable to both humans and agents. Script failures need structured diagnostics that work in both interactive and headless modes.

The first implementation may support declaration loading before full Luau VM execution. That is acceptable as long as the public project model points at Luau source files and the native engine remains responsible for ECS registration and scheduling.
