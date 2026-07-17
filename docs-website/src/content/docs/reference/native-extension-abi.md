---
title: Native Extension ABI
description: The current C-compatible ABI used by project native extensions.
---

The native extension ABI lives in `src/scrapbot/extension_api`. Odin extension authors should normally import `scrapbot:extension`, which wraps this raw ABI with component and field descriptors plus typed helpers such as `scrapbot.component`, `scrapbot.system`, `scrapbot.read`, `scrapbot.query`, `scrapbot.get`, public ECS UI constructors, and deferred lifecycle helpers.

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
	register_geometry: Register_Geometry_Proc,
	register_material: Register_Material_Proc,
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
- `get_ui_component` and `set_ui_component` for complete public ECS UI value and style payloads;
- full indexed geometry and shared material registration;
- linear HDR emission through the material descriptor's `emissive` vector;
- deferred lifecycle helpers for resource-backed renderable spawns, public UI spawns, despawn, transform, schema-backed payloads, UI payloads, and removal.

Return `nil` on success or a static error string on failure. The host enforces declared access through the callback context.

## ECS UI payloads

`UI_Component_Payload` is the fixed-layout transport for every public `scrapbot.ui_*` component. It includes the complete box, responsive sizing policy, progress value, control value, and style structures used by scene TOML, Luau, and editor chrome. The component name selects the relevant typed member. `UI_Layout_Payload` carries minimum size, per-axis fill and fit-to-content flags, and fixed-child behavior inside fill stacks; `UI_Progress_Payload` carries value, maximum, track/fill styling, inset, corner radius, and direction. Scroll-area payloads include complete scrollbar geometry and colors; panel payloads include disclosure and trailing-action styling; input and checkbox payloads include their complete focus, validation, prefix, caret, border, checkmark, and corner styling.

Text, font resource names, and input prefixes use bounded byte arrays inside the payload instead of allocator-owned Odin strings. The current limits are 1,023 text bytes, 255 font-name bytes, and 63 prefix bytes. Callers must copy values they want to retain; the payload itself remains caller-owned.

`scrapbot.ui_state` is readable through the same API and publishes hover, active, focus, activation, change, validity, submit/cancel edges, and their monotonic revision counters. It is renderer-owned and cannot be passed to `set_ui_component`.

UI mutation and removal are deferred through the callback's command buffer. A `Spawn_Options` value can include up to eight UI payloads and an optional output UUID pointer. The UUID is filled when the spawn command is accepted, allowing other entities in the same deferred batch to refer to the new UI entity by stable identity.

## Current limits

Native extensions cannot yet:

- access ECS storage directly;
- access non-vec3 custom fields;
- allocate through a host allocator.
