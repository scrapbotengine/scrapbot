# Odin Idioms and Style

## Contents

- Design stance
- API design
- Error handling
- Allocation and ownership
- Data layout
- Naming and visibility
- Translating from other languages
- Review checklist

## Design Stance

Odin rewards direct code. Start with concrete data and free procedures, then add abstraction only when it simplifies real call sites.

Prefer:

- Plain structs plus procedures.
- Slices for borrowed sequences.
- Dynamic arrays/maps only where mutation and allocation are part of the contract.
- Explicit allocator/context choices.
- Multiple return values for failure.
- Small packages with clear data ownership.

Avoid:

- Class hierarchies, hidden lifetimes, implicit allocation, exception-like control flow, over-generic helpers, and C preprocessor habits.

## API Design

Shape APIs around ownership:

```odin
// Borrowed input, caller owns memory.
process_bytes :: proc(bytes: []u8) -> Error

// Output into caller-provided storage.
format_into :: proc(buf: []u8, value: Value) -> (out: string, ok: bool)

// Allocates with current context allocator; caller deletes result.
build_table :: proc(items: []Item) -> (table: Table, err: Error)
```

Guidelines:

- Prefer `[]T` parameters over `[dynamic]T` unless the proc appends/resizes.
- Pass dynamic arrays by pointer when mutating their header: `append(&xs, value)`.
- Return `(value, err)` or `(value, ok)` when failure is expected.
- Use named return values when `or_return` needs to set trailing status values or when the names clarify a multi-return contract.
- Keep package globals rare. Prefer explicit state structs.
- Use `@(require_results)` for APIs where ignoring return values is likely a bug.

## Error Handling

Odin does not have exceptions by design. The usual choices are:

- Return `err` for error domains with useful variants.
- Return `ok` for lookup/parse/probe operations where boolean failure is enough.
- Use `assert` for programmer errors and invariants, not recoverable failures.
- Use `panic` only when the process or subsystem cannot sensibly continue.

Good pattern:

```odin
file, err := os.open(path)
if err != os.ERROR_NONE {
    return err
}
defer os.close(file)
```

Use `or_return` when it compresses a common propagation path without hiding important behavior:

```odin
data := load(path) or_return
parsed := parse(data) or_return
```

Do not use `or_return` when you need to translate errors, add context, release extra resources early, or assign non-trivial return values.

## Allocation and Ownership

Treat allocation as part of API design.

- Use caller-owned buffers for formatting, serialization, and hot loops.
- Use arenas for batch lifetime.
- Use `context.allocator` when the allocation should follow the caller's scoped policy.
- Delete what you own in the same scope where possible.
- Do not store slices into temporary dynamic arrays, arenas, or stack buffers beyond their lifetime.

Typical cleanup:

```odin
arena: mem.Arena
mem.arena_init(&arena)
defer mem.arena_destroy(&arena)

arena_allocator := mem.arena_allocator(&arena)
context.allocator = arena_allocator
```

When changing `context`, keep the scope tight:

```odin
{
    old_context := context
    context.allocator = arena_allocator
    defer context = old_context

    run_batch()
}
```

If the project already has a context/allocator helper, use that instead of writing a new save/restore pattern.

## Data Layout

Odin is a strong fit for data-oriented code:

- Keep stable IDs/handles separate from dense storage.
- Prefer arrays/slices of simple structs for iteration.
- Use SoA (`#soa`) for hot per-field traversal when profiling or domain knowledge justifies it.
- Use bit sets for flags instead of integer flag constants.
- Use distinct types for units, IDs, handles, and domain-separated integers.
- Use `#packed` and raw unions only for binary formats or ABI layout, not ordinary optimization guesses.

Before changing layout, check:

- Is the data hot?
- Who owns it?
- Does iteration need stable order?
- Are pointers invalidated by dynamic array growth?
- Does the layout cross a foreign ABI or serialized format boundary?

## Naming and Visibility

Follow local style first. General Odin style:

- Package names are short, lower-case, and usually match the directory/import path.
- Types and constants commonly use PascalCase or domain-specific established names.
- Procedures and variables commonly use snake_case.
- Preserve upstream names for foreign bindings and direct ports where it helps comparison.
- Use `@(private)` deliberately; public-by-default does not mean everything is intended API.

For examples intended for upstream `odin-lang/examples`, their README asks examples to compile with strict vet/style flags and links a naming/style convention. In project code, match the project's stricter local rules if present.

## Translating From Other Languages

From C:

- Replace pointer+length pairs with slices.
- Replace macros with `when`, constants, inline procs, or `#config`.
- Replace integer flags with `bit_set`.
- Replace header/source separation with packages and exported declarations.
- Use `core:c` and foreign blocks for ABI boundaries only.

From C++:

- Replace constructors with useful zero values and explicit init procedures.
- Replace destructors/RAII with `defer`.
- Replace classes with structs plus procedures.
- Replace templates with parapoly only when concrete duplication is worse.
- Remember copies are byte-for-byte; there are no move/copy constructors or ownership semantics.

From Go:

- There is no garbage collector. Own and delete allocations.
- There are no methods/interfaces in the same sense; use procedures, procedure values, and explicit data.
- Use Odin's package and build systems, not Go module assumptions.

From Lua/Luau:

- Make data shapes explicit with structs/unions/enums.
- Use explicit error values instead of dynamic nil/error conventions.
- Avoid converting script-level dynamic patterns directly into maps of `any`-like data unless the boundary requires it.

## Review Checklist

Before finalizing an Odin change:

- Does every owned allocation/resource have a matching cleanup?
- Are borrowed slices/pointers never stored past their lifetime?
- Are errors or `ok` values checked?
- Are enum/union switches intentionally exhaustive or explicitly `#partial`?
- Does the code preserve local package/import conventions?
- Could a slice, index, or handle replace a raw pointer?
- Are `---`, `#bounds_check` changes, foreign calls, and pointer casts narrowly justified?
- Did tests/checks cover the package touched?
