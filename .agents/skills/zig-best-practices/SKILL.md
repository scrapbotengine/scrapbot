---
name: zig-best-practices
description: Use when writing, refactoring, reviewing, or debugging Zig code in this repository. Covers Zig 0.16-era style, allocator ownership, error handling, compile-time boundaries, testing, build-system habits, and Scrapbot-specific Zig conventions.
---

# Zig Best Practices

Use this skill for Zig implementation, review, or architecture work. Treat local project rules in `AGENTS.md` as binding, and use this skill as Zig-specific guidance.

## Baseline

- Check `build.zig.zon` before relying on version-specific APIs. Scrapbot currently requires Zig `0.16.0`.
- Use the local compiler and tests as the final authority: `zig version`, `zig fmt`, `zig build test --summary all`, `mise build`, and `mise test`.
- If a Zig API, build-system API, or language rule is uncertain, verify against the official Zig documentation for the repository's target version before editing.

## Editing Workflow

1. Read the surrounding module first. Match its ownership model, allocation style, error mapping, and test style.
2. Keep changes narrow. Prefer behavior-preserving moves, adapters, or focused helpers over broad rewrites.
3. Format touched Zig files with `zig fmt`.
4. Run the smallest meaningful Zig check after each risky slice; use full `mise build`/`mise test` for broad behavior, renderer, CLI, or runtime changes.

## Names And Modules

- Prefer clear nouns and verbs over generic names such as `Manager`, `Data`, `Value`, `Context`, `utils`, or `misc`.
- Avoid redundant fully-qualified names. A type in `render/resources.zig` does not need to repeat `RenderResources` in every declaration.
- Keep top-level `src/*.zig` files as facades, process entry points, or small cross-cutting modules. Put subsystem implementation under domain directories.
- In Zig, each source file is a struct-like namespace. Use imports and explicit aliases to communicate boundaries; avoid turning facades into implementation sinks.
- Prefer `const` over `var` unless mutation is required.
- For CLI, editor, and tooling JSON output, prefer `std.json.Stringify` over manual string escaping and comma bookkeeping. Use `Stringify.print` only where an existing numeric format is part of the observable output contract.

## Allocation And Ownership

- Functions that allocate should usually accept a `std.mem.Allocator` parameter. Do not hide allocation behind global state.
- Make ownership explicit in names and docs when returning allocated memory. The caller must know what to free and with which allocator.
- Pair allocations with `defer`/`errdefer` in the same scope whenever possible.
- Use arena allocation only when the lifetime is truly bulk-discarded. Do not use arenas for reloadable or replaceable long-lived state unless the whole arena is reset at the same lifetime boundary.
- In tests, prefer `std.testing.allocator` or a local allocator that exposes leaks.

## Errors And Cleanup

- Prefer precise error sets for public or boundary functions when they clarify the contract; use inferred errors for local helpers where the call site remains readable.
- Preserve original error context when diagnostics matter. Map errors at subsystem boundaries, not deep inside generic helpers unless the helper owns the policy.
- Use `try` for straight-line propagation, `catch` only when adding policy, cleanup, fallback, or diagnostics.
- Use `defer` for unconditional cleanup and `errdefer` for rollback on failure. Keep cleanup near resource acquisition.
- Avoid `unreachable` for recoverable input, file, scene, script, or backend failures. Reserve it for invariants the type system or preceding checks make impossible.

## Types And Runtime Safety

- Prefer slices over pointer-plus-length pairs. Use sentinel slices only when the sentinel is part of the contract.
- Be explicit around integer casts, float-to-int casts, alignment, pointer casts, and enum conversions. These are common places for debug-safety traps.
- Use tagged unions for variant data with meaningful active-field semantics. Assign the whole union when changing the active field.
- Keep `anytype` and heavy `comptime` APIs for places where they remove real duplication or express a compile-time contract. Avoid clever generic code in hot runtime paths unless it is measured.
- Do not use `undefined` as a convenience initializer for values that can be cheaply initialized. When using it for buffers or performance, ensure every byte or field is written before read.

## Performance

- Start with simple, clear Zig. Measure before keeping specialized data layouts or bridge/cache optimizations.
- Keep hot loops allocation-free and avoid repeated dynamic lookups where a local value or resolved row can be cached safely.
- Prefer struct-of-arrays or bulk views only for measured hot paths; keep ordinary code easy to inspect.
- Separate Debug-safety failures from ReleaseFast performance questions when evaluating changes.

## Tests

- Zig only runs test declarations that are reachable while resolving a `zig test` root source file. Production imports alone are not a reliable test-discovery mechanism; every test file must be reached from a test root or from a reachable module's explicit `test { _ = @import("..._tests.zig"); }` block.
- Small doctests or very small unit tests may live in the production file when they document the declaration directly.
- For non-trivial modules, prefer a sibling `*_tests.zig` file imported from the production module with a small bottom-of-file `test { _ = @import("foo_tests.zig"); }` block. This mirrors Zig standard library practice such as `std/json.zig` importing `json/test.zig` and keeps test code discoverable without turning production files into mixed test suites.
- Keep command-level or cross-module tests in an explicitly named test root such as `src/cli_tests.zig`, and import that from the executable or library test root. Do not hide broad integration tests at the bottom of a production module.
- Use `std.testing.expectEqual`, `expectError`, `expectEqualStrings`, and approximate float checks instead of hand-written boolean assertions where they produce better failure output.
- Use named tests that describe behavior, not implementation details.
- After changing test wiring, verify the reported test counts in `zig build test --summary all`; a `0 tests passed` executable target usually means the test root is not importing the intended modules.
- In this repository, do not run `zig build test` and `mise test` concurrently because fixed temp paths can collide.

## Scrapbot-Specific Zig Rules

- Engine behavior belongs in Zig. Luau is for project-local game scripting.
- Preserve ECS access checks, generation-aware handles, deferred structural mutation, live-reload staging, diagnostics, and engine-owned backend boundaries.
- Prefer shared ECS, retained UI, renderer, project, and script services over one-off paths.
- For rendering, UI, script diagnostics, docs, ADR/FDR, and TODO changes, use the relevant project skills and verification commands listed in `AGENTS.md`.

## Source References

- Official Zig language reference for the target version: `https://ziglang.org/documentation/0.16.0/`
- Official Zig standard library docs are available locally with `zig std`.
- Project rules: `AGENTS.md`
