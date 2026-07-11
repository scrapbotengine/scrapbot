---
title: Native Extension ABI
description: The current C-compatible ABI used by project native extensions.
---

The first native extension ABI lives in `src/scrapbot/extension_api`.

## Versioning

```odin
ABI_VERSION :: u32(1)
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

## Current limits

Native extensions can register component schemas only. They cannot yet:

- register native systems;
- access ECS storage directly;
- declare scheduler reads or writes;
- allocate through a host allocator.
