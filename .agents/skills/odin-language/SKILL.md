---
name: odin-language
description: Work effectively in Odin programming language codebases. Use when reading, writing, reviewing, testing, refactoring, or documenting `.odin` files; when choosing idiomatic Odin syntax, packages, allocators, error handling, foreign bindings, tests, build flags, or data-oriented designs; or when translating concepts from C, C++, Go, Lua, or scripting languages into Odin.
---

# Odin Language

Use this skill to make Odin changes that match the language rather than approximating C, Go, or C++ habits. Odin is a compiled, statically typed, procedural, data-oriented systems language with explicit memory/resource management, strong package conventions, and an opinionated standard library split into `base:`, `core:`, and `vendor:`.

## First Steps

1. Inspect the existing Odin code before editing: package names, import style, allocator patterns, error return conventions, `context` use, tests, and build scripts.
2. Prefer local idioms over generic examples. If the repo has wrappers around `core:mem`, logging, Luau, rendering, or platform APIs, reuse them.
3. Run the narrowest available Odin check after edits. Prefer existing project commands; otherwise use `odin check <dir>`, `odin test <dir>`, or `odin test <dir> -all-packages` as appropriate.
4. If uncertain about current Odin behavior, verify against official docs or installed compiler output. Odin is pre-1.0 and evolves.

## Load References

- Read [language-cheatsheet.md](references/language-cheatsheet.md) when writing or reviewing Odin syntax, type system details, procedures, control flow, collections, memory, `context`, foreign calls, attributes, or build directives.
- Read [idioms-and-style.md](references/idioms-and-style.md) when making design choices, translating from another language, choosing error handling, allocation strategy, APIs, naming, visibility, or data layout.
- Read [tooling-and-testing.md](references/tooling-and-testing.md) when running compiler commands, tests, vetting, build flags, build tags, `#config` options, nightly/release differences, or project automation.
- Read [packages-and-ecosystem.md](references/packages-and-ecosystem.md) when selecting standard library packages, vendor bindings, examples, package docs, or external learning material.

## Core Rules

- Think in packages as directories. A package directory contains `.odin` files with one package name. Imports use collections like `core:fmt`, `core:mem`, `vendor:...`, or relative package paths.
- Keep declarations regular: `name: Type`, `name := value`, `Name :: constant_or_proc`, `Name : Type : constant`. Do not write C-style declarations.
- Use explicit resource management. Allocate intentionally, pair owned resources with `defer delete(...)`, `defer free(...)`, `defer os.close(...)`, or a local cleanup convention.
- Prefer multiple return values for errors or `ok` results. Odin has no exceptions; use `or_return` and `or_continue` when they make the normal path clearer.
- Use slices and arrays before pointer arithmetic. Odin pointers are `^T`; there is no C-style pointer arithmetic. Use `core:mem` helpers or multi-pointers only when needed for low-level/foreign interop.
- Preserve data-oriented designs. Prefer plain structs, arrays/slices, SoA facilities, enums, unions, bit sets, and explicit procedures over object-oriented class hierarchies.
- Be careful with zero values. Variables are zero-initialized unless assigned `---`; use `---` only when skipping initialization is deliberate and safe.
- For foreign libraries, use Odin's `foreign import`, `foreign` blocks, `core:c` types, `cstring`, attributes like `@(link_name=...)`, and existing `vendor:` bindings before hand-rolling large bindings.

## Useful Commands

```sh
odin check .
odin build .
odin run .
odin test .
odin test . -all-packages
odin test . -define:ODIN_TEST_NAMES=package.test_name
```

Use stricter checks if the project already expects them:

```sh
odin check . -vet -strict-style -vet-tabs -warnings-as-errors
```

## Primary References

- Official docs: https://odin-lang.org/docs/
- Overview: https://odin-lang.org/docs/overview/
- Package docs: https://pkg.odin-lang.org/
- Demo file: https://odin-lang.org/docs/demo/
- Tests: https://odin-lang.org/docs/testing/
- FAQ: https://odin-lang.org/docs/faq/
- Examples: https://github.com/odin-lang/examples
- Compiler/source: https://github.com/odin-lang/Odin
