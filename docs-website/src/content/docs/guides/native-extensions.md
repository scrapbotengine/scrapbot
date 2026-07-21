---
title: Native Extensions
description: Build project-local Odin dynamic libraries that register component schemas and scheduled systems.
---

Native extensions are the current path for moving project/library behavior toward compiled code. The loaded-library ABI is deliberately small, while Odin extension authors use the `scrapbot:extension` helper package to register component schemas and scheduled systems.

## Declare an extension target

Add a target to `project.toml`:

```toml
[[native_extensions]]
name = "scrappyphysics"
source = "native/scrappyphysics"
```

`name` is the target name used in generated output filenames. `source` is an Odin package directory relative to the project root.

## Write the extension

```odin
package scrappyphysics

import scrapbot "scrapbot:extension"

Rigidbody_Component :: scrapbot.Component {
	name = "scrappyphysics.rigidbody",
	advanced = true,
}
Rigidbody_Velocity :: scrapbot.Vec3_Field{component = Rigidbody_Component, name = "velocity"}
Rigidbody_Drag :: scrapbot.Number_Field{component = Rigidbody_Component, name = "drag"}

@(export)
scrapbot_extension_register :: proc "c" (api: ^scrapbot.API) -> cstring {
	return scrapbot.register(api, register)
}

register :: proc "contextless" (ctx: ^scrapbot.Context) -> cstring {
	reg := scrapbot.registry(ctx)

	fields := [?]scrapbot.Field {
		scrapbot.vec3(Rigidbody_Velocity),
		scrapbot.number_draggable(Rigidbody_Drag, 0.05, 0),
	}
	scrapbot.component(&reg, Rigidbody_Component, fields[:])

	return scrapbot.err(&reg)
}
```

Extensions must export `scrapbot_extension_register`. The helper validates the host table and calls your project-local contextless `register` procedure. Component and field descriptors keep the rest of the extension from repeating string names. Scrapbot currently rebuilds extensions from source and fingerprints the host extension API in each artifact name, keeping host and extension layouts in lockstep; explicit ABI version negotiation is intentionally deferred.

`advanced = true` is optional component presentation metadata. Advanced components remain public, queryable, authorable, and inspectable; the editor simply starts their component panels collapsed so internal simulation state does not dominate the inspector.

## Register a system

Systems declare component access and provide a callback:

```odin
reg := scrapbot.registry(ctx)

accesses := [?]scrapbot.Access {
	scrapbot.read(scrapbot.Transform_Component),
	scrapbot.write(scrapbot.Transform_Component),
	scrapbot.read(Rigidbody_Component),
}
scrapbot.system(&reg, "scrappyphysics.motion", accesses[:], motion_system)

return scrapbot.err(&reg)
```

The callback receives `scrapbot.System_Context`. The context includes a read-only `time` snapshot and can query entities by component names, read/write `scrapbot.transform`, read/write Number, Vec2, Vec3, Vec4, and Color fields on schema-backed custom components, and consume the same public ECS UI payloads used by scenes, Luau, and editor chrome. A Transform's optional `parent` is a stable entity UUID; its position, rotation, and scale are local to that parent, and invalid or cyclic parent writes are rejected. Native and Luau systems share the same scheduler.

Custom schema constructors are `scrapbot.number`, `scrapbot.vec2`, `scrapbot.vec3`, `scrapbot.vec4`, and `scrapbot.color`; each accepts its typed field descriptor or a raw field name. `scrapbot.number_draggable(field, step, minimum?, maximum?)` opts a scalar into inspector scrubbing and publishes its step and bounds through the shared registry. Corresponding `*_value` payload constructors and `scrapbot.get`/`scrapbot.set` overloads avoid packing unrelated scalar settings into vectors.

Native systems with complete, non-conflicting access declarations run concurrently on Scrapbot's worker pool. Conflicting systems preserve registration order, Luau systems remain serial, and systems without access declarations execute exclusively. Parallel native systems queue lifecycle commands privately; Scrapbot merges those commands deterministically after the stage.

System names follow the same ownership convention in Odin and Luau: use one token such as `rigidbody` for project-owned behavior, and a dotted multi-token name such as `scrappyphysics.motion` for engine or library behavior. The runtime does not enforce this convention yet because registration does not carry explicit ownership metadata.

```odin
motion_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		Rigidbody_Component,
	}
	rigidbody_query := scrapbot.query(components[:])

	cursor: scrapbot.Query_Cursor
	for {
		entity, entity_ok := scrapbot.next(ctx, rigidbody_query, &cursor)
		if !entity_ok {
			break
		}

		transform, transform_ok := scrapbot.get(ctx, entity, scrapbot.Transform_Component)
		if !transform_ok {
			return "failed to read transform"
		}

		velocity, velocity_ok := scrapbot.get(ctx, entity, Rigidbody_Velocity)
		if !velocity_ok {
			return "failed to read velocity"
		}

		transform.position.x += velocity.x * ctx.time.delta_time
		transform.position.y += velocity.y * ctx.time.delta_time
		transform.position.z += velocity.z * ctx.time.delta_time

		if !scrapbot.set(ctx, entity, transform) {
			return "failed to write transform"
		}
	}

	return nil
}
```

Use `scrapbot.next` for frame-system iteration. Its cursor advances once through the smallest requested project-component storage, or through world slots when no project component narrows the query. Candidate order and cursor representation are internal details. The indexed `scrapbot.count` and `scrapbot.entity_at` helpers remain available for tooling and explicit random access, but composing them in a loop repeatedly rescans candidates.

For dense arithmetic systems, use a caller-owned query chunk to amortize the extension boundary and make lane-wise work explicit:

```odin
import "base:intrinsics"

motion_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		Rigidbody_Component,
	}
	chunk: scrapbot.Query_Chunk
	if !scrapbot.init_query_chunk(&chunk, scrapbot.query(components[:])) {
		return "failed to initialize motion chunk"
	}
	transforms: [scrapbot.MAX_QUERY_CHUNK_ENTITIES]scrapbot.Transform
	velocities: [scrapbot.MAX_QUERY_CHUNK_ENTITIES]scrapbot.Vec3
	transform_binding, transform_ok := scrapbot.bind_transform(&chunk, transforms[:], .Write)
	_, velocity_ok := scrapbot.bind_vec3(&chunk, Rigidbody_Velocity, velocities[:])
	if !transform_ok || !velocity_ok {
		return "failed to bind motion chunk"
	}

	delta := scrapbot.F32x4(ctx.time.delta_time)
	for {
		count, err := scrapbot.next_chunk(ctx, &chunk)
		if err != nil {
			return err
		}
		if count == 0 {
			break
		}

		lane := 0
		for lane + 4 <= count {
			position := scrapbot.load_transform_positions_x4(transforms[:], lane)
			velocity := scrapbot.load_vec3x4(velocities[:], lane)
			position.x = intrinsics.fused_mul_add(velocity.x, delta, position.x)
			position.y = intrinsics.fused_mul_add(velocity.y, delta, position.y)
			position.z = intrinsics.fused_mul_add(velocity.z, delta, position.z)
			scrapbot.store_transform_positions_x4(transforms[:], position, lane)
			lane += 4
		}
		for lane < count {
			transforms[lane].position.x += velocities[lane].x * ctx.time.delta_time
			transforms[lane].position.y += velocities[lane].y * ctx.time.delta_time
			transforms[lane].position.z += velocities[lane].z * ctx.time.delta_time
			lane += 1
		}

		scrapbot.chunk_write_all(&chunk, transform_binding)
		if err := scrapbot.commit_chunk(ctx, &chunk); err != nil {
			return err
		}
	}
	return nil
}
```

Chunk buffers belong to the extension and never alias ECS storage. A chunk contains at most 64 entities. The host compiles a distinct chunk shape once per native system, retaining its candidate storage and typed field indices across frames and ordinary membership changes. Bindings must be query terms and match the system's declared access. Writes require `chunk_write_all` or an exact `chunk_write_mask`; use masks from SIMD comparisons to avoid writing or invalidating lanes that were removed, rejected, or unchanged. Keep a scalar tail for counts not divisible by four. Cursor iteration remains preferable for sparse, branch-heavy, or lifecycle-dominated systems.

Project system callbacks are ordinary contextless Odin procedures. The extension helper retains their bindings and routes the host's C-compatible callback through an internal trampoline; only the exported `scrapbot_extension_register` entry point needs `proc "c"` in project source.

The raw C-compatible package remains available as `scrapbot:extension_api` for non-Odin bindings and ABI reference work.

See the [Engine Component Reference](/reference/components/) for every engine-owned component name and its public fields. Not every engine component has a predefined Odin helper descriptor yet; construct `scrapbot.Component{name = "scrapbot.<name>"}` when a system only needs to declare or query membership.

## Build ECS UI from native systems

Declare reads and writes for the UI components a system uses, just like gameplay components:

```odin
accesses := [?]scrapbot.Access {
	scrapbot.write(scrapbot.UI_Layout_Component),
	scrapbot.write(scrapbot.UI_Text_Component),
	scrapbot.read(scrapbot.UI_State_Component),
}
scrapbot.system(&reg, "native_ui", accesses[:], native_ui_system)
```

Constructors accept the complete public value and style payload. Defaults are reusable starting points, and every field—including background, border, text colors, and corner radius—can be overridden per entity. A zero corner radius produces square corners.

```odin
layout := scrapbot.ui_layout_default()
layout.size = {320, 64}
layout.padding = {12, 16, 12, 16}
layout.background = {0.025, 0.030, 0.040, 1}
layout.border_color = {0.20, 0.23, 0.28, 1}
layout.border_width = 1
layout.corner_radius = 8

text_style := scrapbot.ui_text_default()
text_style.size = 16
text_style.color = {0.90, 0.92, 0.95, 1}
text_payload, text_ok := scrapbot.ui_text(text_style, "Native ECS UI", "Inter")
if !text_ok {
	return "native UI text exceeds the ABI buffer"
}

components := [?]scrapbot.UI_Component_Payload {
	scrapbot.ui_layout(layout),
	text_payload,
}
spawn := scrapbot.spawn_options_with_ui("Native UI", components[:])
uuid, err := scrapbot.spawn_with_uuid(ctx, &spawn)
if err != nil {
	return err
}
_ = uuid // stable project-wide identity, also usable as a UI parent
```

Use `scrapbot.get_ui` for a typed read/modify/write cycle and `scrapbot.set_ui` for the deferred update. The same payload supports responsive layout fields such as `min_size`, `fill_width`, and `fit_content_height`; proportional and pointer-resizable `scrapbot.ui_table` columns; reusable `scrapbot.ui_progress` values; and numeric `scrapbot.ui_input` controls with optional horizontal scrubbing (`draggable = true`) and optional prefix badges. `scrapbot.UI_State_Component` is readable but renderer-owned and cannot be written. Its activation, change, submit, and cancel revisions are stable edge counters for native systems that react less frequently than rendering; `valid` exposes numeric validation.

The raw ABI stores text, font names, and input prefixes in fixed inline buffers rather than passing allocator-owned Odin strings across the dynamic-library boundary. The Odin helper handles those buffers through `ui_text`, `ui_panel`, `ui_button`, `ui_input`, `ui_payload_text`, `ui_payload_font`, and `ui_payload_prefix`.

## Queue lifecycle commands

Native systems can queue the same deferred lifecycle commands as Luau systems. Commands are applied after the scheduled frame step, so query iteration remains stable while systems run.

```odin
fields := [?]scrapbot.Component_Vec3_Field {
	scrapbot.vec3_value(Lifetime_Timer, {0, 4, 0}),
}
payload := scrapbot.payload(Lifetime_Component, fields[:])

if err := scrapbot.add(ctx, entity, &payload); err != nil {
	return err
}

if err := scrapbot.remove(ctx, entity, Source_Component); err != nil {
	return err
}

spawn_transform := scrapbot.Transform {
	position = {0, -1, 0},
	rotation = {},
	scale = {1, 1, 1},
}
payloads := [?]scrapbot.Component_Payload {payload}
cube := scrapbot.cube_geometry(2)
geometry := scrapbot.register_generated_geometry(&reg, "cube", &cube)
material := scrapbot.material(&reg, "orange", {0.95, 0.38, 0.18, 1})
neon := scrapbot.emissive_material(&reg, "neon", {2, 0.2, 6})
spawn := scrapbot.spawn_options("Native Spawned", &spawn_transform, &geometry, &material, payloads[:])
if err := scrapbot.spawn(ctx, &spawn); err != nil {
	return err
}
```

Lifecycle writes must be declared in the system access list. A renderable spawn declares writes for transform, `scrapbot.geometry`, and `scrapbot.material` alongside its gameplay components.

## Build it

```sh
mise scrapbot -- build examples/minimal
```

`scrapbot check` and `scrapbot run` also build declared extensions automatically.

Scrapbot chooses an Odin optimization profile for each workflow: `check` uses `-o:minimal` for short iteration, `run` and hot reload use `-o:speed`, and packaged `build` uses `-o:speed`. The profile is part of the cached library name, so a fast check cannot overwrite or masquerade as the optimized play artifact.

Development cache output goes to:

```text
.scrapbot/cache/extensions/<name>-<profile>-<source-stamp>.<platform-library-extension>
.scrapbot/cache/extensions/.scrapbot-extensions
```

Examples:

- macOS: `scrappyphysics-performance-<source-stamp>.dylib`
- Linux: `scrappyphysics-performance-<source-stamp>.so`

`.scrapbot-extensions` records the active output files for the latest build. Older versioned libraries may remain in `.scrapbot/cache/extensions`.

## Use it from Luau

After the native extension registers a component, Luau can retrieve the handle:

```lua
local RigidbodyComponent =
	scrapbot.component_handle("scrappyphysics.rigidbody") :: ScrappyphysicsRigidbodyComponent
```

Then use it in queries, systems, views, access declarations, and lifecycle APIs like any other schema-backed component.

## Hot reload status

Runtime hot reload watches declared native extension source directories. When source changes, Scrapbot rebuilds declared extensions, updates `.scrapbot-extensions`, reloads the scene and Luau runtime, and loads the newly built library path.

Hot reload also notices active library file changes in `.scrapbot/cache/extensions` and `project.toml` changes that alter declared extension targets.
