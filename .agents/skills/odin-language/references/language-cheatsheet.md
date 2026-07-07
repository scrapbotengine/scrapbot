# Odin Language Cheatsheet

## Contents

- Philosophy and package model
- Declarations and literals
- Control flow
- Procedures and errors
- Types and data layout
- Collections and iteration
- Memory, allocation, and context
- Compile-time features
- Foreign interop
- Attributes and directives
- Common pitfalls

## Philosophy and Package Model

Odin is a general-purpose systems language focused on explicitness, performance, data-oriented programming, and readable tooling. It is not C with nicer syntax, not Go with generics, and not C++ without classes.

- Source files use `.odin`.
- Every file starts with `package name`.
- A directory is one package. Files in that directory must share the package declaration.
- Execution starts at `main :: proc()` in `package main`.
- Import collection prefixes include `base:`, `core:`, `vendor:`, and relative package paths.
- Package declarations are public by default. Use `@(private)` for package-private declarations and `@(private="file")` for file-private declarations.

```odin
package main

import "core:fmt"

main :: proc() {
    fmt.println("Hellope!")
}
```

Build/run packages by directory:

```sh
odin run .
odin build .
odin check .
```

Use `-file` only when treating one file as a complete package:

```sh
odin run demo.odin -file
```

## Declarations and Literals

Odin declarations keep the name on the left and type on the right.

```odin
x: int                  // zero-initialized int
y, z: int               // both int
a: int = 123
b := 123                // inferred int
c:     = 123            // inferred default type
Name :: "constant"      // compile-time constant
Typed : int : 123       // typed constant
```

Important declaration rules:

- `:=` is shorthand for declaration plus assignment.
- Declarations must be unique within a scope.
- Constants use `::` or `: Type :` and must be compile-time evaluable.
- `---` means explicitly uninitialized memory. Use it only when immediately overwritten or otherwise proven safe.
- All ordinary variables are zero-initialized by default.

Literal notes:

- Raw strings use backticks.
- Character literals use single quotes and represent Unicode code points.
- Numeric literals support `_`, `0b`, `0o`, `0x`, floats, and imaginary suffix `i`.
- Untyped constants convert to a target type if representable without precision loss.
- Multi-line comments nest.

## Control Flow

Odin has one loop statement: `for`.

```odin
for i := 0; i < 10; i += 1 {}
for i < 10 {}
for {}
for i in 0..<10 {}
for i in 0..=9 {}
```

Iteration:

```odin
for value in slice {}
for value, index in array {}
for key, value in map_value {}
for &value in slice { value += 1 }
for key, &value in map_value { value += 1 }
```

Notes:

- Iterated values are copies unless using `&value`.
- String iteration yields `rune` values and assumes UTF-8.
- Maps have immutable keys. Values can be iterated by reference.
- Reverse range loops are usually written as ordinary `for i := hi; i >= lo; i -= 1`.

`if` supports an initial statement:

```odin
if value, ok := lookup(); ok {
    use(value)
}
```

`switch`:

- Does not fall through unless `fallthrough` is explicit.
- Allows non-integer and non-constant case expressions.
- Can use ranges.
- `switch` without a condition is equivalent to `switch true`.
- Exhaustiveness is checked for enum/union switches by default. Use `#partial switch` to opt out intentionally.
- `case:` is a catch-all case and is separate from `#partial`.

`when` is compile-time conditional logic:

```odin
when ODIN_OS == .Darwin {
    // checked only when true for this build
} else {
}
```

`defer` runs at scope exit in reverse declaration order. Use it for cleanup.

## Procedures and Errors

Procedures:

```odin
add :: proc(a, b: int) -> int {
    return a + b
}

swap :: proc(a, b: int) -> (int, int) {
    return b, a
}

named :: proc() -> (value: int, ok: bool) {
    value = 123
    ok = true
    return
}
```

Common features:

- Multiple return values are normal.
- Named return values are local variables in the proc body.
- Parameters are immutable by default; shadow a parameter intentionally if mutation helps.
- Use `..T` for variadic parameters and `..slice` to pass a slice as varargs.
- Procedure groups are explicit overload sets: `name :: proc{proc_a, proc_b}`.
- Divergent procedures never return.

Error handling:

- Return `(value, err)` or `(value, ok)` rather than throwing exceptions.
- Use `or_return` to propagate the last return value when it is non-nil or false.
- Use `or_continue` inside loops to skip failed work.
- Prefer explicit `if err != nil` when propagation needs custom behavior or clearer state assignment.

```odin
read_value :: proc() -> (value: int, err: Error) {
    value, err = parse() or_return
    return
}
```

## Types and Data Layout

Primitive and built-in families include:

- Integers: `int`, `uint`, fixed-width signed/unsigned integers, `uintptr`.
- Floats: `f16`, `f32`, `f64`; complex: `complex32`, `complex64`, `complex128`.
- `bool`, `rune`, `string`, `cstring`, `rawptr`, type IDs.
- Endian-specific integer/float types exist for data formats and protocols.

Pointers:

```odin
p: ^int
i := 123
p = &i
p^ = 456
```

- `^T` is a pointer to `T`; zero value is `nil`.
- `&` takes an address; postfix `^` dereferences.
- Struct pointer field access can use `p.field` rather than `p^.field`.
- Use `core:mem.ptr_offset` or `ptr_sub` for pointer arithmetic; do not invent C-style arithmetic.

Structs:

```odin
Vector3 :: struct {
    x, y, z: f32,
}

v := Vector3{z = 1, y = 2} // omitted fields zero
```

Useful struct directives:

- `#align(n)`
- `#packed`
- `#raw_union`
- `#min_field_align(n)`
- `#max_field_align(n)`
- `#simple`
- `#all_or_none`

Other core types:

- `enum` for named alternatives. Use exhaustive switches.
- `union{A, B}` for tagged alternatives; `#no_nil` removes nil variant.
- `bit_set[...]` for flag sets; use set literals and `card`.
- `distinct T` for strong domain-specific types.
- Type aliases only when you intentionally want assignment compatibility.
- Procedure types are first-class values.

Data-oriented tools:

- Favor arrays/slices of structs or struct-of-arrays where locality matters.
- Use `#soa` arrays/slices for structure-of-arrays layouts when appropriate.
- Prefer handles, indices, and dense arrays when ownership/lifetime are central.

## Collections and Iteration

Arrays:

```odin
a: [3]int
b := [3]int{1, 2, 3}
c := [?]int{1, 2, 3} // length inferred
```

Slices:

```odin
s: []int
s = b[:]
```

Dynamic arrays and maps:

```odin
xs: [dynamic]int
defer delete(xs)
append(&xs, 1)

m: map[string]int
defer delete(m)
m["answer"] = 42
```

Notes:

- Dynamic arrays and maps allocate; delete them when owned.
- Dynamic literals may require `#+feature dynamic-literals` depending on compiler/project settings.
- Prefer slices for APIs that do not need ownership transfer.
- Use `core:slice`, `core:sort`, `core:container/*`, and project-local containers before adding ad hoc container code.

## Memory, Allocation, and Context

Odin has no garbage collector. Memory management is explicit and allocator-aware.

Common operations:

```odin
p := new(T)
defer free(p)

xs := make([]T, count)
defer delete(xs)

buf := make([]u8, 0, capacity)
defer delete(buf)
```

Rules of thumb:

- Document ownership in API shape and naming.
- Prefer caller-provided buffers, slices, arenas, or allocators for hot code.
- Use `defer` for normal cleanup and `testing.cleanup` only for tests that may panic or time out before `defer` runs.
- Avoid hidden allocation in utility procs unless that is the explicit contract.
- Make zero values useful where possible.

Implicit context:

- Each scope has an implicit `context` value.
- Procedure calls receive context implicitly.
- Context carries allocator, logger, error handler, and other runtime hooks.
- You can shadow or mutate `context` in a nested scope to change allocation/logging behavior for called code.
- Treat context changes as scoped configuration, not global state.

## Compile-Time Features

Odin's compile-time model is part of normal language semantics.

- `when` selects compile-time branches.
- `#config(NAME, default)` reads command-line `-define:NAME=value` configuration.
- `#assert` checks compile-time facts.
- `$` parameters require compile-time constants for parametric polymorphism.
- `$T: typeid` passes types as compile-time values.
- `type_of`, `typeid_of`, `size_of`, `align_of`, `offset_of`, and reflection facilities support metaprogramming and layout checks.

Parametric polymorphism:

```odin
make_array :: proc($N: int, $T: typeid) -> (res: [N]T) {
    return
}

Table_Slot :: struct($Key, $Value: typeid) {
    key: Key,
    value: Value,
}
```

Implicit polymorphic names:

```odin
identity :: proc(x: $T) -> T {
    return x
}
```

Use parapoly when it materially improves type safety or removes duplication. Avoid turning simple code into a generic framework.

## Foreign Interop

Use Odin's foreign system for C ABI interop.

```odin
foreign import kernel32 "system:kernel32.lib"

foreign kernel32 {
    @(link_name="LoadLibraryA")
    load_library_a :: proc(name: cstring) -> rawptr ---
}
```

Interop guidance:

- Check `vendor:` first for common libraries.
- Use `core:c` for C-compatible types.
- Use `cstring` for zero-terminated C strings. Converting `string` to `cstring` may allocate unless constant.
- Preserve upstream C naming in bindings when direct portability matters.
- Attach attributes such as `@(link_name=...)`, `@(default_calling_convention=...)`, `@(link_prefix=...)`, `@(link_suffix=...)`, and `@(require_results)` as needed.
- Isolate unsafe/raw interop behind a small Odin wrapper API.

## Attributes and Directives

Common attributes:

- `@(private)` and `@(private="file")`
- `@(test)`
- `@(require)` on imports or declarations that must be retained
- `@(deprecated="message")`
- `@(static)` for local static variables
- `@(thread_local)`
- `@(init)` and `@(fini)`
- `@(export)` and linker attributes
- `@(deferred_*=proc)` for APIs that auto-defer a paired call

Common directives:

- `#partial switch`
- `#force_inline` and `#no_inline`
- `#bounds_check` toggles in carefully audited code
- `#config`
- `#assert`
- `#+build` and `#+feature` file directives

Prefer attributes/directives that express a real contract. Do not add them as decoration.

## Common Pitfalls

- Do not use `++`, `--`, exceptions, constructors, destructors, RAII, inheritance, or method syntax. Odin does not have them.
- Do not assume assignment transfers ownership. Copies are byte-for-byte copies unless the type's API says otherwise.
- Do not expose raw pointers when a slice, index, handle, or typed wrapper is clearer.
- Do not forget to `delete` owned dynamic arrays, maps, allocated slices, strings, arenas, and other allocated resources.
- Do not use `---` as a performance reflex.
- Do not make everything generic. Plain procedures over concrete types are often the idiomatic choice.
- Do not hide platform differences in runtime branches when `when ODIN_OS` or build tags are clearer.
- Do not rely on map iteration order.
- Do not mutate values yielded by `for value in slice`; use `for &value in slice` or index assignment.
