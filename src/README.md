# Source Layout

Scrapbot keeps `src/scrapbot` as the public runtime facade imported by the CLI. Implementation code lives in smaller packages below it:

- `scrapbot/shared` - Shared data contracts used across runtime packages.
- `scrapbot/project` - Project manifests, scene parsing, project creation, and loading.
- `scrapbot/ecs` - World construction and ECS-owned runtime state helpers.
- `scrapbot/component` - Component registry, schema validation helpers, and Luau type generation.
- `scrapbot/schedule` - System access declarations and conflict-free batch planning.
- `scrapbot/platform` - Platform window and event integration.
- `scrapbot/render` - Renderer backend selection and backend implementations.
- `scrapbot_cli` - The command-line entry point.

Prefer adding new implementation code to the narrowest package that owns the behavior. Keep `scrapbot` focused on the public API that tools and the CLI call.
