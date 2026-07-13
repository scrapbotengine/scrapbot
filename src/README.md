# Source Layout

Scrapbot keeps `src/scrapbot` as the public runtime facade imported by the CLI. Implementation code lives in smaller packages below it:

- `scrapbot/shared` - Shared data contracts used across runtime packages.
- `scrapbot/project` - Project manifests, scene parsing, project creation, and loading.
- `scrapbot/ecs` - World construction, ECS-owned runtime state helpers, and deferred world command application.
- `scrapbot/component` - Component registry, schema validation helpers, and Luau type generation.
- `scrapbot/schedule` - System access declarations and conflict-free batch planning.
- `scrapbot/diagnostic` - Stable machine-readable diagnostic records shared by tools and command output.
- `scrapbot/package.odin` - Host-native game packaging and target selection.
- `scrapbot/script` - Luau runtime lifecycle, API bindings, component and system registration, queries, commands, and value marshaling.
- `scrapbot/native` - Native extension builds and discovery, dynamic loading, ABI registration, and system execution.
- `scrapbot/resources` - Geometry, PNG texture, and material resource ownership plus generated primitive geometry.
- `scrapbot/ui` - Retained ECS UI reconciliation, layout, paint lists, and embedded bitmap text.
- `scrapbot/extension_api` - The stable C-compatible contract exposed to native extensions.
- `scrapbot/extension` - The higher-level Odin wrapper used by extension authors.
- `scrapbot/platform` - Platform window and event integration.
- `scrapbot/render` - Renderer selection, null and WGPU backends, WGPU setup, shader source, render math, and PNG output.
- `scrapbot_cli` - The command-line entry point.

Prefer adding new implementation code to the narrowest package that owns the behavior. Keep `scrapbot` focused on the public API that tools and the CLI call.
