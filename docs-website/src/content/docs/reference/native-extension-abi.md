---
title: Native Extension ABI
description: The current C-compatible ABI used by project native extensions.
---

The native extension ABI lives in `src/scrapbot/extension_api`. Odin extension authors should normally import `scrapbot:extension`, which wraps this raw ABI with component and field descriptors plus typed helpers such as `scrapbot.component`, `scrapbot.system`, `scrapbot.read`, `scrapbot.query`, `scrapbot.get`, and deferred lifecycle helpers.

## Entry point

Extensions export:

```odin
@(export)
scrapbot_extension_register :: proc "c" (api: ^scrapbot_api.API) -> cstring
```

Return `nil` on success or a static error string on failure.

## API table

```odin
API :: struct {
	userdata: rawptr,
	register_library_component: Register_Library_Component_Proc,
	register_system: Register_System_Proc,
}
```

The API table is host-owned and only valid for the registration call.

Scrapbot currently compiles project extensions from source and treats this layout as lockstep engine code. There is no version negotiation until precompiled third-party extensions become a supported distribution model.

## Component definitions

```odin
Field_Type :: enum c.int {
	Vec3 = 1,
}

Field_Definition :: struct {
	name: cstring,
	field_type: Field_Type,
}

Component_Definition :: struct {
	name: cstring,
	fields: [^]Field_Definition,
	field_count: c.int,
}
```

Rules:

- component names must be dotted;
- native extensions cannot register the reserved `scrapbot` namespace;
- field names must be single identifier tokens;
- the first supported field type is vec3;
- the maximum field count is 16.

## System definitions

Native systems register during `scrapbot_extension_register` after any component schemas they reference:

```odin
Access_Mode :: enum c.int {
	Read = 1,
	Write = 2,
}

System_Access :: struct {
	component: cstring,
	mode: Access_Mode,
}

System_Definition :: struct {
	name: cstring,
	accesses: [^]System_Access,
	access_count: c.int,
	callback: System_Proc,
	userdata: rawptr,
}
```

System access components must already be registered. Native systems and Luau systems are planned by the same access-aware scheduler. Conflict-free native systems execute concurrently on the runtime worker pool, while conflicting systems preserve registration order. Luau systems and systems without access declarations execute as serial barriers.

## System context

Native callbacks receive a host-owned `System_Context`:

```odin
System_Proc :: #type proc "c" (ctx: ^System_Context) -> cstring
```

This raw callback type is the dynamic-library boundary. Odin projects using `scrapbot:extension` register ordinary `proc "contextless"` callbacks; the helper supplies the C-compatible trampoline and stable callback storage.

The context includes:

- a read-only `time` snapshot with delta time, smoothed delta time, elapsed time, and frame index;
- extension `userdata`;
- query helpers for component-name terms;
- `get_transform` and `set_transform`;
- `get_vec3_field` and `set_vec3_field` for schema-backed custom components;
- full indexed geometry and shared material registration;
- deferred lifecycle helpers for resource-backed renderable spawns, despawn, transform, schema-backed payloads, and removal.

Return `nil` on success or a static error string on failure. The host enforces declared access through the callback context.

## Current limits

Native extensions cannot yet:

- access ECS storage directly;
- access non-vec3 custom fields;
- allocate through a host allocator.
