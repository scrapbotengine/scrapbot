---
title: Native Extensions
description: Build project-local Odin dynamic libraries that register component schemas and scheduled systems.
---

Native extensions are the current path for moving project/library behavior toward compiled code. The ABI is deliberately small: native code can register library component schemas and scheduled systems.

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

import c "core:c"
import api "scrapbot:extension_api"

@(export)
scrapbot_extension_register :: proc "c" (scrapbot: ^api.API) -> cstring {
	if scrapbot == nil {
		return "Scrapbot API is not available"
	}
	if scrapbot.abi_version != api.ABI_VERSION {
		return "unsupported Scrapbot extension ABI"
	}

	fields := [?]api.Field_Definition {
		{name = "velocity", field_type = .Vec3},
	}
	definition := api.Component_Definition {
		name = "scrappyphysics.rigidbody",
		fields = raw_data(fields[:]),
		field_count = c.int(len(fields)),
	}
	return scrapbot.register_library_component(scrapbot, &definition)
}
```

Extensions must export `scrapbot_extension_register`.

## Register a system

Systems declare component access and provide a callback:

```odin
accesses := [?]api.System_Access {
	{component = "scrapbot.transform", mode = .Read},
	{component = "scrapbot.transform", mode = .Write},
	{component = "scrappyphysics.rigidbody", mode = .Read},
}
system := api.System_Definition {
	name = "scrappyphysics.motion",
	accesses = raw_data(accesses[:]),
	access_count = c.int(len(accesses)),
	callback = motion_system,
}
return scrapbot.register_system(scrapbot, &system)
```

The callback receives `api.System_Context`. The current context can query entities by component names, read/write `scrapbot.transform`, and read/write vec3 fields on schema-backed custom components. Native and Luau systems share the same scheduler batches.

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
