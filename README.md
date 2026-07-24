<img alt="Scrapbot Engine" src="https://github.com/user-attachments/assets/dbb0eb91-449d-49b1-99ea-93429b10734c" />

# Scrapbot Engine

A compact, experimental, and probably mostly useless game engine that tries to answer the question: what if a game engine was 100% agentically engineered, and structured specifically so agents can help you build your game?

> [!WARNING]
> **Do not expect this engine to be useful**. In particular, **do not try to make a game with it**! It's a **research project** with no aims to be production-ready, stable, or even particularly usable. It is a playground for exploring agentic workflows and game engine design and not much else. You have been warned. (We still love you though!)

## Contributing

Scrapbot is maintained as an agent-first codebase. Before opening a PR, read [`CONTRIBUTING.md`](CONTRIBUTING.md) for contributor expectations and [`AGENTS.md`](AGENTS.md) for the rules coding agents must follow when changing this repository.

The high-level roadmap is below. Active follow-up work lives in [`docs/TODO.md`](docs/TODO.md), with architecture and feature decisions tracked in [`docs/adr/`](docs/adr/) and [`docs/fdr/`](docs/fdr/). Project vocabulary lives in [`docs/GLOSSARY.md`](docs/GLOSSARY.md).

The documentation website includes a conceptual [ECS overview](https://scrapbot.dev/guides/ecs/) plus exact references for engine components, Luau, native extensions, project files, and ECS UI.

## What's Inside

Scrapbot is a small Odin CLI and runtime with an embedded Luau scripting layer, a native ECS, a GPU-driven WebGPU renderer, and a first-party editor — all operable through structured CLI output, so agents (and scripts) can build, run, inspect, and screenshot projects without a human at the keyboard.

### CLI

- `scrapbot init [path] [name]` safely creates a runnable text-first project without overwriting existing files. Authored data lives in `assets/`, `native/`, `resources/`, `scenes/`, and `scripts/`; generated types and caches live under ignored `.scrapbot/` state; distributable packages live under `build/`.
- `scrapbot check [path] [--json]` builds declared native extensions, validates the manifest, default scene, and Luau component schemas, refreshes generated Luau LSP types, and runs Luau static analysis when `luau-analyze` is available.
- `scrapbot build [path] [--target host] [--json]` creates a host-native runnable package under `build/<target>` with the game executable, project data, and native extension artifacts.
- `scrapbot run [path] [options]` loads the scene into a native ECS world, executes `scripts/main.luau`, runs native and script systems, and renders through the selected backend. Ordinary development is simply `scrapbot run <path>` (windowed WGPU with hot reload). Options include `--backend null|wgpu`, `--window|--headless`, `--hot-reload|--no-hot-reload`, `--editor`, `--frames n`, `--framegrab out.png`, `--scheduler-trace`, `--runtime-stats`, `--ui-script`, `--ui-dump`, and `--cpu-culling` (deterministic CPU reference path for GPU culling).
- `scrapbot help <command>` prints command-specific options parsed by Odin's `core:flags`.
- Every command emits structured `--json` output with stable diagnostic codes — the automation contract for agents. Headless runs support final-frame PNG framegrabs and semantic UI scripting: `--ui-script` targets reconciled controls by UUID, name, or text, replays interactions, and asserts state; `--ui-dump` exposes the full logical and screen-space UI tree as JSON.

During development, use `mise build` to compile the optimized CLI and `mise scrapbot -- [args...]` to compile and run it. `mise build-dev` emits a fast `-o:minimal` binary; `mise benchmark-profiles` compares build profiles on a bounded run. Run `mise setup` once after cloning to install pinned tools, initialize source dependencies, download checksum-verified external fixtures, and configure the tracked Git hooks (`mise setup-assets` / `mise check-assets` manage only the fixtures).

### ECS and Scripting

- Reflected components with stable project-wide entity UUIDs (distinct from editable names), generation-aware handles, and component lifecycle hooks.
- Scheduled, access-declared native systems running in parallel, with deferred mutations and SIMD-accelerated chunked queries.
- Luau scripting with typed queries, scheduled systems, deferred lifecycle commands, generated type declarations, analyzer checks, and hot reload. `mise luau-workspace-types` rebuilds the tracked type aggregate for editor completion.
- Native Odin extensions through a small C ABI, also hot-reloadable.
- Derived state is change-driven: UI, render-instance, camera, and light membership update from structural dirty queues and compact active sets instead of per-frame world scans.

### Rendering

- Pluggable backends: a deterministic `null` backend for headless smoke tests, and a full `wgpu` backend.
- GPU-driven pipeline: persistent slot-addressed instance storage, dirty-only transform uploads, a growing retained draw database, compute camera/shadow frustum culling, depth prepass with adaptive Hi-Z occlusion, screen-radius LOD selection, and indexed indirect draws with asynchronous GPU timing readback.
- HDR lighting and post: shared metallic-roughness GGX materials with mipmapped PBR maps, ambient/directional/point lights, GPU-clustered point lighting, four stabilized shadow cascades, image-based lighting or a procedural haze sky via one `scrapbot.world_environment` component, half-resolution GTAO over indirect diffuse light, temporal antialiasing with reprojection, screen-space reflections, a compute bloom pyramid, and an ACES-style composite.
- Per-camera render-feature policy: TAA, fast AA, AO, and bloom are authored booleans on `scrapbot.camera`; disabled effects skip their GPU work.
- UUID-backed resources in `resources/**/*.resource.toml` (materials, textures, glTF models, HDR environments, generated LOD chains) with hot reload, targeted reimport, and import diagnostics; scenes serialize stable UUID references that the runtime resolves to generational registry handles.

### Retained UI

- ECS-first retained UI: responsive box model, fixed/proportional stacks, overlays, draggable separators, hidden subtrees, smooth clipped scroll areas, selectable lists, progress indicators, collapsible panels, equal/proportional tables, buttons, checkboxes, numeric controls, and keyboard-focused text inputs with Tab traversal.
- MTSDF text with auto-atlased project fonts (embedded Inter fallback) and SDF-rounded styling for backgrounds, borders, and controls.
- One public component contract: scene TOML, Luau systems, native Odin extensions, and the editor all construct and mutate the same typed UI values; the renderer publishes read-only interaction state.
- Revision-driven paint with independent project, editor, and world-overlay GPU streams — unchanged domains skip reconciliation, layout, paint, and uploads entirely.

### Editor

- Toggleable ECS-built shell (`Cmd/Ctrl+E`, or `--editor` to start open) framing an aspect-correct live viewport with resizable scene and inspector panels, status bar, and scroll panes.
- Entity browser, expandable UUID-backed hierarchy with drag-to-reparent, and runtime type-inspected component panels — no per-component UI code, everything derives from the component registry.
- Play/Pause/Step (`Cmd/Ctrl+R`, `Cmd/Ctrl+T`) with a non-destructive in-memory authoring baseline, stopped-mode Undo/Redo, explicit project-wide Save, and scene Revert.
- RMB-captured WASD fly camera, precise entity picking, and translation/rotation/scale gizmos with plane and center handles.
- System profiler publishing engine, project-Odin, Luau, and CPU render-phase timings from a rolling window.

### Examples

Example projects live in [`examples/`](examples/):

- `minimal` — Luau- and Odin-defined components and systems (`mise scrapbot run examples/minimal`).
- `ecs-showcase` — object fountain with spawned renderables, animated point lights, emissive bloom, and a procedural 30-second day/night cycle.
- `ecs-stress` — roughly 3,000 glowing renderables sustained through retained query plans, chunked storage, and SIMD integration.
- `clustered-lights` — 320 animated HDR point lights through GPU-computed view-frustum clusters in a bloom-soaked tunnel.
- `gltf-showcase` — the pinned Khronos Damaged Helmet through the real glTF importer, lit by a pinned CC0 HDR environment.
- `pbr-materials` — deterministic authored metallic/roughness reference grid for isolating material and lighting changes.
- `sponza` — the Khronos Sponza atrium as 103 ECS renderables with 25 PBR materials, directional shadows, and clustered point lights.

### Testing

Run the full local suite with `mise test` (includes a 2,000-frame lifecycle CPU/RAM growth gate). `mise test-soak` runs the extended 10,000-frame check; `mise test-sanitize` runs the Linux AddressSanitizer lane. CI covers macOS, Linux, and Windows, plus the ASan lane on Linux.

## Features / Roadmap

### Engine Core

- Runtime
  - [x] Single-binary CLI
  - [ ] Cross-platform runtime
  - [ ] Interactive commands
  - [x] Headless commands
- Projects
  - [x] Text-first projects
  - [x] TOML scene files
  - [x] Standalone UUID-backed project resource files
  - [x] Project initialization
  - [ ] Project templates
  - [ ] Scene migrations
- Reloading
  - [x] Live reload
  - [x] Structured diagnostics
- Distribution
  - [x] Host game builds
  - [ ] Package dependencies
  - [ ] Cross-platform exports
  - [ ] Console/mobile publishing

### ECS Runtime

- World Model
  - [x] Shared ECS runtime
  - [x] Reflected components
  - [x] Stable project-wide entity UUIDs
  - [x] Generation-aware entities
  - [x] Component registry
  - [x] Component lifecycles
  - [x] ID-keyed custom component storage
  - [x] Engine-owned frame time resource
  - [x] Incremental render and retained-UI membership reconciliation
  - [x] Revision-driven retained UI paint and independent GPU streams
  - [ ] World snapshots
- Scheduling
  - [x] Scheduled systems
  - [x] Access-controlled systems
  - [x] Deferred mutations
  - [x] Parallel native system scheduling
- Queries
  - [x] Bulk Luau query views
  - [x] Multi-component Luau queries
  - [x] Typed three-component Luau queries
  - [ ] Advanced queries

### Scripting And Native Extensions

- Luau
  - [x] Luau scripting
  - [x] Luau type definitions
  - [x] Luau analyzer checks
  - [x] Basic script components
  - [x] Basic script systems
  - [x] Script hot reload
  - [x] Reflected script components
  - [x] Scheduled script systems
  - [ ] Editor scripting
- Native
  - [x] Native Odin modules
  - [x] Native hot reload
  - [x] Native ECS systems
  - [x] Chunked native queries with portable SIMD helpers
  - [x] Native extension examples
  - [ ] Static native packaging
- Developer Experience
  - [ ] Script/native diagnostics
  - [x] Performance documentation

### Rendering

- Backend
  - [x] WebGPU surface smoke
  - [x] Headful rendering smoke
  - [x] WebGPU triangle render loop
  - [x] Headless WebGPU framegrab
  - [x] WebGPU ECS cube renderer
  - [x] Multi-entity WebGPU cube renderer
  - [x] General indexed-geometry WebGPU renderer
  - [ ] Offscreen render comparison
- Scene Data
  - [x] Basic cameras
  - [x] Lighting
  - [x] Generated cube, plane, icosphere, UV sphere, pyramid, and cylinder geometry
  - [x] Shared metallic-roughness materials with mipmapped PBR texture channels
  - [x] ECS-owned editor scene camera and captured fly navigation
- Pipeline
  - [x] Geometry/material render batching
  - [x] Four stabilized directional-shadow cascades with explicit caster/receiver components
  - [x] HDR rendering
  - [x] Imported image-based lighting with opt-in independently configured HDR backgrounds and per-camera exposure
  - [x] Authored ECS world environments with a renderer-native procedural haze sky
  - [x] Depth-aware temporal antialiasing, horizon-integrated GTAO, material-aware screen-space reflections, multi-scale bloom, and tone-mapping postprocessing
  - [x] Compute camera and shadow frustum culling
  - [x] GPU-computed clustered point lighting
  - [x] Persistent GPU instances, visibility compaction, and indexed indirect drawing
  - [x] Compact dirty-transform uploads with GPU matrix and bounds expansion
  - [x] Dynamically growing retained draw database
  - [x] Dirty-only retained render extraction and incremental existing-batch membership
  - [x] Depth prepass and adaptive Hi-Z occlusion culling
  - [x] GPU screen-radius LOD selection
  - [x] Asynchronous per-pass GPU timestamps and visibility/LOD counters
  - [x] Ambient, directional, and point-light rendering
- Assets
  - [x] Incremental static glTF 2.0/GLB model imports with embedded, data-URI, and external metallic-roughness PBR images
  - [x] glTF opaque/cutout alpha materials and double-sided rendering across color, depth, and shadows
  - [x] Selected-scene glTF closure imports with semantic reimport identity and authored texture samplers
  - [x] PNG texture assets
  - [x] UUID-backed texture and model resources
  - [x] UUID-backed Radiance HDR environments with source-resolution skies and high-quality importer-built diffuse/specular cubes
  - [x] Targeted live Reimport, import diagnostics, texture thumbnails, and stale model-product retirement
  - [x] UUID-backed material resources
  - [x] UUID-backed generated geometry LOD resources
- Tooling
  - [x] Resource hot reload
  - [ ] Hi-Z, visibility, and LOD debug views

### Input And UI

- Input
  - [x] ECS keyboard and pointer input singletons
  - [x] Luau/native runtime input snapshots with held and edge state
  - [x] UI pointer position and primary-button input
  - [ ] Controller input
- Retained UI
  - [x] Retained UI primitives
  - [x] Box-model layout with horizontal, vertical, and overlay composition
  - [x] Element hover and active hit-testing state
  - [ ] UI command events
  - [x] Smooth clipped vertical scroll areas
  - [x] Collapsible titled panels
  - [x] Equal or proportional tables with draggable column separators
  - [x] Selectable lists and progress indicators
  - [ ] Canvas scaling
  - [x] Built-in scalable UI text
  - [x] MTSDF-based font rendering
  - [x] Auto-atlased project TTF/OTF fonts with embedded Inter fallback
  - [x] UI gallery
  - [x] Semantic headless UI replay, assertions, tree dumps, and target framegrabs
- Controls
  - [x] Text and pointer-styled button controls
  - [x] Reusable SDF checkbox controls
  - [x] Reusable numeric editor controls with validation, stepping, and opt-in scrubbing
  - [ ] Additional form controls
  - [x] Single-line text input with cursor movement and selection
  - [x] Keyboard focus with Tab and Shift+Tab traversal
  - [ ] Clipboard support
- Styling
  - [x] Scene-defined UI API
  - [x] Margins, padding, hidden subtrees, backgrounds, rounded corners, and borders
  - [ ] UI themes

### Editor

- Shell
  - [x] Toggleable editor shell
  - [x] Aspect-correct live game viewport
  - [x] Resizable panels
  - [ ] Dockable editor workspace
- Inspection
  - [x] System profiler
  - [x] Entity browser
  - [x] Entity selection
  - [x] Runtime type-inspected component panels with generic Bool, String, Number, Vec2, Vec3, Vec4, and Color controls
  - [x] Material resource-reference picker and inline resource fields
  - [x] ECS-built material resource browser with selection and inline inspection
  - [ ] Specialized enum, color, entity-reference, array, and nested-value editors
  - [ ] Searchable browser
  - [x] Expandable UUID-backed spatial hierarchy with drag-to-reparent
- Editing
  - [x] Live transform, camera, light, and custom Number/Vec2/Vec3/Vec4/Color inspector editing
  - [x] UUID-addressed authoring transactions with inspector and gizmo undo/redo
  - [x] Registry-driven, namespaced Add Component picker and panel-title removal actions with undo/redo
  - [x] Entity create, duplicate, rename, delete, and runtime promotion
  - [x] Resource create, duplicate, rename, move, delete, usage lookup, and structural undo/redo
  - [x] Explicit stopped-mode scene persistence by stable entity UUID
  - [x] Recoverable project-wide Save transactions across scene and resource files
  - [ ] Multi-selection editing
  - [x] Bounded field and structural editor transactions
- Scene Tools
  - [x] Play/Pause/Step with an in-memory authoring baseline, non-destructive Stop, stopped-mode Undo/Redo, explicit Save, and scene-only Revert
  - [x] RMB-captured WASD/Space/Ctrl scene-camera navigation
  - [x] Pickable editor-only wireframe bodies and projection frusta for project camera entities
  - [x] World/local translation, rotation, and scale gizmo orientation
  - [x] Translation, rotation, and scale gizmo modes
  - [x] Two-axis plane handles and center free/uniform transform handles
  - [x] Precise viewport entity picking
- Extensibility
  - [ ] Asset browser
  - [ ] Editor plugins

### Testing And Tooling

- Commands
  - [x] Project validation
  - [ ] Deterministic stepping
  - [ ] Benchmark runner
  - [x] JSON command output
- Verification
  - [ ] Gameplay test fixtures
  - [ ] Offscreen render verification
  - [ ] Editor screenshot tests
  - [x] Compile-time-gated world-integrity validation
  - [x] Seeded editor lifecycle state-machine tests
  - [x] Large-scene persistence torture tests with exact-text, savepoint, schema-roundtrip, and failure-injection coverage
  - [x] Project-save rollback and crash-recovery fault matrix across every filesystem phase
  - [x] Native extension tests
  - [x] Lifecycle CPU/RAM growth gate
  - [x] Linux AddressSanitizer lane
- Project Support
  - [x] Example projects
  - [x] Documentation site
  - [x] Agent workflow docs
  - [x] macOS, Linux, and Windows CI workflow
  - [x] Docs checks
  - [ ] Benchmark trend reporting

### Assets, Simulation, And Larger Systems

- Assets
  - [x] Primitive geometry helpers
  - [x] Embedded UI font
  - [ ] Asset references
  - [ ] Asset import pipeline
  - [ ] Asset browser
- Scene Composition
  - [ ] Prefabs
  - [ ] Scene instancing
- Simulation
  - [ ] Physics
  - [ ] Animation clips
  - [ ] Skeletal meshes
  - [ ] Animation state machines
- Runtime Systems
  - [ ] Audio resources
  - [ ] Runtime audio
  - [ ] Networking
  - [ ] Terrain streaming
  - [ ] Large-world streaming

## License

Scrapbot is licensed under the [Apache License 2.0](LICENSE). Vendored dependencies under [`third_party/`](third_party/) retain their own licenses.
