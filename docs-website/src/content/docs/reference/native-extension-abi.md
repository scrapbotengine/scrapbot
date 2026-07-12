---
title: Native Extension ABI
description: The current C-compatible ABI used by project native extensions.
---

The native extension ABI lives in `src/scrapbot/extension_api`. Odin extension authors should normally import `scrapbot:extension`, which wraps this raw ABI with component and field descriptors plus typed helpers such as `scrapbot.component`, `scrapbot.system`, `scrapbot.read`, `scrapbot.query`, `scrapbot.get`, and deferred lifecycle helpers.

## Versioning

```odin
ABI_VERSION :: u32(3)
```

Extensions should reject unknown ABI versions during registration.

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
	abi_version: u32,
	userdata: rawptr,
	register_library_component: Register_Library_Component_Proc,
	register_system: Register_System_Proc,
}
```

The API table is host-owned and only valid for the registration call.

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

System access components must already be registered. Native systems and Luau systems are batched together by the same scheduler. Batches still execute serially.

## System context

Native callbacks receive a host-owned `System_Context`:

```odin
System_Proc :: #type proc "c" (ctx: ^System_Context) -> cstring
```

The context includes:

- `delta_seconds`;
- extension `userdata`;
- query helpers for component-name terms;
- `get_transform` and `set_transform`;
- `get_vec3_field` and `set_vec3_field` for schema-backed custom components;
- deferred lifecycle helpers for spawn, despawn, add transform, add schema-backed component payload, and remove component.

Return `nil` on success or a static error string on failure. The host enforces declared access through the callback context.

## Current limits

Native extensions cannot yet:

- access ECS storage directly;
- access non-vec3 custom fields;
- spawn renderable mesh components;
- allocate through a host allocator.
