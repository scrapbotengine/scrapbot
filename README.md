<img alt="Scrapbot Engine" src="https://github.com/user-attachments/assets/dbb0eb91-449d-49b1-99ea-93429b10734c" />

# Scrapbot Engine

A compact, experimental, and probably mostly useless game engine that tries to answer the question: what if a game engine was 100% agentically engineered, and structured specifically so agents can help you build your game?

> [!WARNING]
> **Do not expect this engine to be useful**. In particular, **do not try to make a game with it**! It's a **research project** with no aims to be production-ready, stable, or even particularly usable. It is a playground for exploring agentic workflows and game engine design and not much else. You have been warned. (We still love you though!)

## Contributing

Scrapbot is maintained as an agent-first codebase. Before opening a PR, read [`CONTRIBUTING.md`](CONTRIBUTING.md) for contributor expectations and [`AGENTS.md`](AGENTS.md) for the rules coding agents must follow when changing this repository.

The high-level roadmap is below. Active follow-up work lives in [`docs/TODO.md`](docs/TODO.md), with architecture and feature decisions tracked in [`docs/adr/`](docs/adr/) and [`docs/fdr/`](docs/fdr/). Project vocabulary lives in [`docs/GLOSSARY.md`](docs/GLOSSARY.md).

The documentation website includes a conceptual [ECS overview](https://scrapbot.dev/guides/ecs/) plus exact references for engine components, Luau, native extensions, project files, and ECS UI.

## Current Runtime Slice

Scrapbot currently has a small Odin CLI and runtime skeleton:

- `scrapbot init [path] [name]` safely creates a runnable text-first project without overwriting existing project files. Authored data lives in `assets/`, `native/`, `resources/`, `scenes/`, and `scripts/`; generated types and caches live under ignored `.scrapbot/` state; distributable packages live under `build/`.
- `scrapbot check [path] [--json]` builds declared native extensions, validates the project manifest, default scene, and project Luau component schemas, refreshes generated Luau LSP types, and runs Luau static analysis when `luau-analyze` is available.
- `scrapbot build [path] [--target host] [--json]` creates a host-native runnable package under `build/<target>`, including the game executable, project data, and active native extension artifacts.
- `scrapbot run [path] [--backend null|wgpu] [--cpu-culling] [--window|--headless] [--hot-reload|--no-hot-reload] [--editor] [--scheduler-trace] [--runtime-stats] [--frames n] [--framegrab out.png] [--framegrab-region x,y,width,height] [--ui-script actions.json] [--ui-dump tree.json] [--json]` builds declared native extensions, loads the scene into a tiny native ECS world, executes `scripts/main.luau` if present, runs registered native and script systems, and submits the world through the selected renderer backend. Source-project runs default to a windowed WGPU renderer with hot reload, so ordinary development is simply `scrapbot run <path>`. Visible windows default to 1600×900 logical pixels, accept `[window]` overrides from `project.toml`, and proportionally fit oversized requests to the primary display's usable area. Use `--headless`, `--backend null`, and `--no-hot-reload` for deterministic automation; `--cpu-culling` keeps WGPU indirect drawing but replaces compute visibility with the deterministic CPU reference path. `Cmd/Ctrl+E` toggles the editor shell in a visible window, and `--editor` starts it open; hiding the shell always starts or resumes playback. While the editor is open, `Cmd/Ctrl+R` plays or resumes when stopped or paused and stops when running; `Cmd/Ctrl+T` pauses or advances one fixed step. Scheduler tracing reports native worker utilization. Runtime statistics report early/late engine-frame cost through render preparation, engine-allocator bytes including post-teardown retention, and ECS storage high-water marks. Windowed runtime statistics require a bounded `--frames` value. Framegrab regions preserve 1:1 output pixels and use top-left coordinates. UI diagnostic scripts semantically target reconciled ECS controls by UUID, name, or text, automatically reveal clipped targets, replay interactions, assert state, and select tight capture regions; UI dumps expose the final logical and screen-space tree as structured JSON.
- `scrapbot help <command>` prints command-specific options parsed by Odin's `core:flags`.

During development, use `mise build` to compile the optimized CLI and `mise scrapbot -- [args...]` to compile and run it with arguments forwarded to Scrapbot. `mise build-dev` emits a fast-to-compile `-o:minimal` binary, while `mise benchmark-profiles` compares it with the ordinary `-o:speed` build on a bounded project run.

Run `mise setup` once after cloning to install pinned tools, initialize source dependencies, download checksum-verified external development fixtures, and configure the tracked Git hooks. Heavy or license-constrained fixtures remain ignored local state and are never committed or included in Scrapbot's own releases. Use `mise setup-assets` to refresh only those fixtures or `mise check-assets` to verify them offline.

`scrapbot check <project>` refreshes that project's ignored Luau declarations. Engine contributors can run `mise luau-workspace-types` to check the self-contained examples and rebuild the tracked aggregate used for Luau completion and diagnostics when the repository root is open in VS Code. Fixture-backed examples retain their own project-local editor declarations.

After setup, `mise scrapbot run examples/gltf-showcase --editor` renders the pinned Khronos Damaged Helmet through the real glTF importer and WGPU material path, lit by a pinned CC0 Poly Haven HDR environment.

For a substantially larger real-world workload, `mise scrapbot run examples/sponza --editor` imports and renders the pinned Khronos Sponza atrium as 103 ordinary ECS renderables with 25 generated PBR materials, directional shadows, a pinned CC0 pure-sky environment, and clustered point lights. The external source assets remain checksum-verified ignored development state.

This first slice intentionally uses a narrow schema-driven TOML reader instead of a complete TOML implementation. Every scene entity has a required project-wide UUID distinct from its editable name, and runtime spawns receive fresh UUIDs. Rendering is pluggable at the runtime boundary. The `null` backend supports headless smoke tests, while the `wgpu` backend renders full indexed geometry with shared metallic-roughness GGX materials, mipmapped base-color/normal/occlusion/emissive maps, ECS ambient/directional/point lights, GPU-computed clustered point-light assignment, four stabilized directional-shadow cascades, backend-owned GPU caches, persistent slot-addressed instance storage, compact dirty-transform uploads with GPU matrix/bounds expansion, a geometrically growing draw database, compute camera/shadow frustum culling, a depth prepass and adaptive Hi-Z occlusion, GPU screen-radius LOD selection, compacted visibility, indexed indirect draws, asynchronous GPU timing/counter readback, depth-aware temporal antialiasing, a compute bloom pyramid, live window resizing, and a retained ECS UI overlay with independent revision-driven project, editor, and world-overlay GPU streams, a responsive box model, fixed or proportional horizontal and vertical stacks, draggable separators, per-axis fill and fit-to-content sizing, hidden subtrees, smooth clipped scroll areas, selectable lists, reusable progress indicators, renderer-backed interactive Model/Material/Texture/World viewports with pooled adaptive render targets, collapsible titled panels with SDF disclosure icons, horizontally aligned MTSDF text, pointer-aware buttons, keyboard-focused single-line inputs, reusable SDF checkboxes, and SDF-rounded backgrounds and borders. Scene TOML, Luau systems, native Odin extensions, and transient editor chrome construct and mutate the same typed UI component values and per-entity styles; the renderer publishes shared read-only interaction state. UI, render-instance, camera, and light membership update from structural dirty queues and compact active sets instead of being discovered by rescanning the complete world every frame; retained UI parent/child/sibling links make changed layout and paint work linear in the affected visible hierarchy, while unchanged project and editor domains skip hierarchy reconciliation, layout, paint traversal, hashing, vertex generation, and uploads. A transient ECS-built editor shell can frame the live project viewport with top, status, resizable scene and inspector chrome, independently smoothed scroll panes, an ECS-owned fly camera, and a system profiler that publishes engine, project-Odin, Luau, and granular CPU render-phase timings every five frames from a rolling 50-frame window. Headless WGPU can write a final-frame PNG with `--framegrab`. Luau scripting is embedded from a pinned source dependency and exposes the ECS, full geometry/material resource creation, scheduled systems, deferred lifecycle commands, generated types, native extension integration, and hot reload.

Authored project resources live outside ECS and scenes as UUID-identified `resources/**/*.resource.toml` files. Materials, imported textures/models/HDR environments, and generated icosphere LOD chains are supported. Scenes serialize stable resource UUID references, while the runtime resolves them to generational registry handles.

World geometry and an independently configured imported or procedural environment background render into a floating-point HDR target. One authored `scrapbot.world_environment` scene component selects image-based lighting and sky presentation; a fresh project uses the built-in procedural haze sky with live sky/ground color, turbidity, thickness, horizon, and an HDR sun whose elevation drives its disc, directional light, hemispherical fill, twilight, and night transition. The depth prepass produces half-resolution, depth-aware ambient occlusion before world-environment and active-camera exposure feed an eight-sample jittered temporal resolve with camera reprojection, previous-depth rejection, and neighborhood clamping. AO therefore shares the retained temporal history instead of shimmering independently during camera motion. A five-level compute bloom pyramid and one ACES-style composite pass follow. Project UI, gizmos, and editor chrome stay crisp in the later overlay pass.

Example projects live in [`examples/`](examples/). The minimal example demonstrates Luau-defined and Odin-defined components and systems, and can be verified with `mise scrapbot run examples/minimal`. The ECS showcase runs a native object fountain with visible spawned cube renderables, velocity, lifetime, spin, despawn, animated point lights, editor-movable static point lights, emissive bloom, and Luau systems for floating motion and a configurable 30-second procedural day/night cycle. The ECS stress test sustains roughly 3,000 glowing renderables through retained native query plans, 64-entity chunks, SIMD integration, and bounded runtime lifecycle churn. The Cluster Cathedral drives 320 animated HDR point lights through GPU-computed view-frustum clusters and growable light storage inside a dark, bloom-soaked architectural tunnel.

Run the full local test suite with `mise test`; it includes a 2,000-frame lifecycle CPU/RAM growth gate. Use `mise test-soak` for the extended 10,000-frame check and `mise test-sanitize` for the Linux AddressSanitizer lane. Linux CI runs both the normal suite and AddressSanitizer.

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
  - [x] Depth-aware temporal antialiasing, depth-reconstructed ambient occlusion, multi-scale bloom, and tone-mapping postprocessing
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

Scrapbot is licensed under the [Apache License 2.0](LICENSE). Third-party notices and vendored dependency license details are tracked in [NOTICE](NOTICE).
