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

Rigidbody_Component :: scrapbot.Component{name = "scrappyphysics.rigidbody"}
Rigidbody_Velocity :: scrapbot.Vec3_Field{component = Rigidbody_Component, name = "velocity"}

@(export)
scrapbot_extension_register :: proc "c" (api: ^scrapbot.API) -> cstring {
	return scrapbot.register(api, register)
}

register :: proc "contextless" (ctx: ^scrapbot.Context) -> cstring {
	reg := scrapbot.registry(ctx)

	fields := [?]scrapbot.Field {
		scrapbot.vec3(Rigidbody_Velocity),
	}
	scrapbot.component(&reg, Rigidbody_Component, fields[:])

	return scrapbot.err(&reg)
}
```

Extensions must export `scrapbot_extension_register`. The helper checks the ABI version and calls your project-local contextless `register` procedure. Component and field descriptors keep the rest of the extension from repeating string names.

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

The callback receives `scrapbot.System_Context`. The current context can query entities by component names, read/write `scrapbot.transform`, and read/write vec3 fields on schema-backed custom components. Native and Luau systems share the same scheduler batches.

```odin
motion_system :: proc "c" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		Rigidbody_Component,
	}
	rigidbody_query := scrapbot.query(components[:])

	count := scrapbot.count(ctx, rigidbody_query)
	if count < 0 {
		return "failed to query rigidbodies"
	}

	for i in 0..<count {
		entity, entity_ok := scrapbot.entity_at(ctx, rigidbody_query, i)
		if !entity_ok {
			continue
		}

		transform, transform_ok := scrapbot.get(ctx, entity, scrapbot.Transform_Component)
		if !transform_ok {
			return "failed to read transform"
		}

		velocity, velocity_ok := scrapbot.get(ctx, entity, Rigidbody_Velocity)
		if !velocity_ok {
			return "failed to read velocity"
		}

		transform.position.x += velocity.x * ctx.delta_seconds
		transform.position.y += velocity.y * ctx.delta_seconds
		transform.position.z += velocity.z * ctx.delta_seconds

		if !scrapbot.set(ctx, entity, transform) {
			return "failed to write transform"
		}
	}

	return nil
}
```

The raw C-compatible package remains available as `scrapbot:extension_api` for non-Odin bindings and ABI reference work.

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

if err := scrapbot.remove(ctx, entity, Promote_Component); err != nil {
	return err
}

spawn_transform := scrapbot.Transform {
	position = {0, -1, 0},
	rotation = {},
	scale = {1, 1, 1},
}
payloads := [?]scrapbot.Component_Payload {payload}
spawn := scrapbot.spawn_options("Native Spawned", &spawn_transform, payloads[:])
if err := scrapbot.spawn(ctx, &spawn); err != nil {
	return err
}
```

Lifecycle writes must be declared in the system access list. For example, adding or removing `Lifetime_Component` requires `scrapbot.write(Lifetime_Component)`.

## Build it

```sh
mise scrapbot -- build examples/minimal
```

`scrapbot check` and `scrapbot run` also build declared extensions automatically.

Build output goes to:

```text
build/extensions/<name>-<source-stamp>.<platform-library-extension>
build/extensions/.scrapbot-extensions
```

Examples:

- macOS: `scrappyphysics-<source-stamp>.dylib`
- Linux: `scrappyphysics-<source-stamp>.so`

`.scrapbot-extensions` records the active output files for the latest build. Older versioned libraries may remain in `build/extensions`.

## Use it from Luau

After the native extension registers a component, Luau can retrieve the handle:

```lua
local RigidbodyComponent =
	scrapbot.component_handle("scrappyphysics.rigidbody") :: ScrappyphysicsRigidbodyComponent
```

Then use it in queries, systems, views, access declarations, and lifecycle APIs like any other schema-backed component.

## Hot reload status

Runtime hot reload watches declared native extension source directories. When source changes, Scrapbot rebuilds declared extensions, updates `.scrapbot-extensions`, reloads the scene and Luau runtime, and loads the newly built library path.

Hot reload also notices active library file changes in `build/extensions` and `project.toml` changes that alter declared extension targets.
