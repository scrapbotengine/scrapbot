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

@(export)
scrapbot_extension_register :: proc "c" (api: ^scrapbot.API) -> cstring {
	return scrapbot.register(api, register)
}

register :: proc "contextless" (ctx: ^scrapbot.Context) -> cstring {
	fields := [?]scrapbot.Field {
		scrapbot.vec3("velocity"),
	}
	return scrapbot.component(ctx, "scrappyphysics.rigidbody", fields[:])
}
```

Extensions must export `scrapbot_extension_register`. The helper checks the ABI version and calls your project-local contextless `register` procedure.

## Register a system

Systems declare component access and provide a callback:

```odin
accesses := [?]scrapbot.Access {
	scrapbot.read(scrapbot.TRANSFORM),
	scrapbot.write(scrapbot.TRANSFORM),
	scrapbot.read("scrappyphysics.rigidbody"),
}
return scrapbot.system(ctx, "scrappyphysics.motion", accesses[:], motion_system)
```

The callback receives `scrapbot.System_Context`. The current context can query entities by component names, read/write `scrapbot.transform`, and read/write vec3 fields on schema-backed custom components. Native and Luau systems share the same scheduler batches.

```odin
motion_system :: proc "c" (ctx: ^scrapbot.System_Context) -> cstring {
	terms := [?]scrapbot.Query_Term {
		scrapbot.term(scrapbot.TRANSFORM),
		scrapbot.term("scrappyphysics.rigidbody"),
	}

	count := scrapbot.query_count(ctx, terms[:])
	if count < 0 {
		return "failed to query rigidbodies"
	}

	for i in 0..<count {
		entity, entity_ok := scrapbot.query_entity_at(ctx, terms[:], i)
		if !entity_ok {
			continue
		}

		transform, transform_ok := scrapbot.get_transform(ctx, entity)
		if !transform_ok {
			return "failed to read transform"
		}

		velocity, velocity_ok := scrapbot.get_vec3(ctx, entity, "scrappyphysics.rigidbody", "velocity")
		if !velocity_ok {
			return "failed to read velocity"
		}

		transform.position.x += velocity.x * ctx.delta_seconds
		transform.position.y += velocity.y * ctx.delta_seconds
		transform.position.z += velocity.z * ctx.delta_seconds

		if !scrapbot.set_transform(ctx, entity, transform) {
			return "failed to write transform"
		}
	}

	return nil
}
```

The raw C-compatible package remains available as `scrapbot:extension_api` for non-Odin bindings and ABI reference work.

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
